defmodule Tymeslot.Security.AuditLogTest do
  @moduledoc """
  The database audit log behind `SecurityLogger`: which events it keeps, how
  it throttles rate-limit noise, paging and filtering for the admin tab, and
  retention.
  """

  use Tymeslot.DataCase, async: false
  use Oban.Testing, repo: Tymeslot.Repo

  @moduletag :security
  @moduletag :auth

  import Tymeslot.AppSettingsEnvHelpers, only: [restore_app_settings_env: 1]

  alias Tymeslot.AppSettings
  alias Tymeslot.Auth.{AccountStatus, AdminRoles}
  alias Tymeslot.Security.AuditLog
  alias Tymeslot.Security.AuditLog.AuditEventQueries
  alias Tymeslot.Security.AuditLog.AuditEventSchema
  alias Tymeslot.Security.AuditLog.Catalog
  alias Tymeslot.Security.SecurityLogger
  alias Tymeslot.Workers.AuditLogPruneWorker

  setup :restore_app_settings_env

  defp events(type), do: Repo.all(from(e in AuditEventSchema, where: e.event_type == ^type))

  describe "recording through SecurityLogger" do
    test "stores the canonical fields and the full email, with additional_data as metadata" do
      SecurityLogger.log_authentication_attempt("Jane.Doe@example.com", false, "bad_password", %{
        ip_address: "203.0.113.7",
        user_agent: "Mozilla/5.0"
      })

      assert [event] = events("authentication_failure")
      assert event.email == "jane.doe@example.com"
      assert event.email_masked == "j***@example.com"
      assert event.ip_address == "203.0.113.7"
      assert event.user_agent == "Mozilla/5.0"
      assert event.metadata == %{"login_method" => "email_password"}
    end

    test "does not store an identifier that is not an email address" do
      SecurityLogger.log_security_event("account_deletion_success", %{
        user_id: 42,
        email: "not-an-email-token"
      })

      assert [event] = events("account_deletion_success")
      assert event.email == nil
      assert event.email_masked == nil
    end

    test "leaves input-hygiene and bot noise in the text log only" do
      for type <- [
            "calendar_integration_form_validation_success",
            "calendar_integration_form_validation_failure",
            "input_truncated",
            "video_integration_unknown_provider",
            "signup_honeypot_triggered"
          ] do
        SecurityLogger.log_security_event(type, %{ip_address: "203.0.113.8"})
      end

      assert Repo.aggregate(AuditEventSchema, :count) == 0
    end

    test "keeps at most one rate-limit violation per minute per IP and limit type" do
      for _attempt <- 1..3 do
        SecurityLogger.log_rate_limit_violation("a@example.com", "auth", %{
          ip_address: "198.51.100.1"
        })
      end

      SecurityLogger.log_rate_limit_violation("a@example.com", "signup", %{
        ip_address: "198.51.100.1"
      })

      SecurityLogger.log_rate_limit_violation("a@example.com", "auth", %{
        ip_address: "198.51.100.2"
      })

      assert length(events("rate_limit_violation")) == 3
    end

    test "records admin actions with the acting admin" do
      admin = insert(:user, is_admin: true)
      target = insert(:user)

      {:ok, _disabled} = AccountStatus.disable(admin, target.id)
      {:ok, _promoted} = AdminRoles.promote(admin, target.id)

      assert [disabled] = events("account_disabled")
      assert disabled.user_id == target.id
      assert disabled.actor_user_id == admin.id

      assert [promoted] = events("admin_promoted")
      assert promoted.actor_user_id == admin.id
    end
  end

  describe "per-category switches (App Settings → Audit log)" do
    test "a category switched off is no longer recorded" do
      {:ok, _settings} = AppSettings.update(%{audit_log_events: %{"password_change" => false}})

      SecurityLogger.log_security_event("password_change", %{user_id: 1})
      SecurityLogger.log_security_event("csrf_violation", %{user_id: 1})

      assert events("password_change") == []
      assert [_kept] = events("csrf_violation")
    end

    test "a category that is off by default can be switched on" do
      {:ok, _settings} =
        AppSettings.update(%{
          audit_log_events: %{"form_validation" => true, "suspicious_input" => true}
        })

      SecurityLogger.log_security_event("calendar_integration_form_validation_failure", %{})
      SecurityLogger.log_blocked_input(:message, "sql_injection", %{ip: "192.0.2.10"})

      assert [_validation] = events("calendar_integration_form_validation_failure")
      assert [blocked] = events("suspicious_input_sanitised")
      assert blocked.ip_address == "192.0.2.10"
      assert blocked.metadata == %{"field" => "message", "check" => "sql_injection"}
    end

    test "an unknown category or a non-boolean value is rejected" do
      assert {:error, _changeset} = AppSettings.update(%{audit_log_events: %{"nope" => true}})

      assert {:error, _changeset} =
               AppSettings.update(%{audit_log_events: %{"session" => "yes"}})
    end

    test "every event type falls into a category, unknown ones into other" do
      assert Catalog.category_for("session_created") == "session"
      assert Catalog.category_for("signup_honeypot_resend") == "honeypot"
      assert Catalog.category_for("mirotalk_integration_validation_success") == "form_validation"
      assert Catalog.category_for("admin_demoted") == "admin_role"
      assert Catalog.category_for("something_new") == "other"
      assert Catalog.enabled?("other", %{})
      refute Catalog.enabled?("honeypot", %{})
    end
  end

  describe "list_events/3" do
    test "pages newest first and filters by type and user" do
      user = insert(:user)

      for _n <- 1..55 do
        SecurityLogger.log_security_event("password_change", %{user_id: user.id})
      end

      SecurityLogger.log_security_event("csrf_violation", %{user_id: insert(:user).id})

      first = AuditLog.list_events(%{event_type: "password_change"}, 1, 50)
      assert length(first.entries) == 50
      assert %{page: 1, per_page: 50, total: 55, total_pages: 2} = first

      second = AuditLog.list_events(%{event_type: "password_change"}, 2, 50)
      assert length(second.entries) == 5
      assert second.page == 2

      assert Enum.max(Enum.map(second.entries, & &1.id)) <
               Enum.min(Enum.map(first.entries, & &1.id))

      assert %{entries: [_only]} = AuditLog.list_events(%{event_type: "csrf_violation"})
      assert %{entries: [], total: 0, total_pages: 1} = AuditLog.list_events(%{user_ids: []})
      assert length(AuditLog.list_events(%{user_ids: [user.id]}, 1, 100).entries) == 55
    end

    test "defaults to 20 rows, ignores other page sizes and clamps the page" do
      for _n <- 1..25,
          do: {:ok, _event} = AuditEventQueries.insert(%{event_type: "password_change"})

      assert %{per_page: 20, total_pages: 2} = page = AuditLog.list_events(%{})
      assert length(page.entries) == 20
      assert %{per_page: 20} = AuditLog.list_events(%{}, 1, 7)

      assert %{page: 2, entries: last} = AuditLog.list_events(%{}, 99, 20)
      assert length(last) == 5
      assert %{page: 1} = AuditLog.list_events(%{}, 0, 20)
    end

    test "filters by category the same way events are categorised" do
      for type <- [
            "session_created",
            "booking_honeypot_triggered",
            "mirotalk_integration_validation_failure",
            "something_new",
            # `_` must not act as a LIKE wildcard: this is no session event.
            "sessionXcreated"
          ] do
        {:ok, _event} = AuditEventQueries.insert(%{event_type: type})
      end

      for {category, expected} <- [
            {"session", ["session_created"]},
            {"honeypot", ["booking_honeypot_triggered"]},
            {"form_validation", ["mirotalk_integration_validation_failure"]},
            {"other", ["sessionXcreated", "something_new"]},
            {"unknown-category", []}
          ] do
        types =
          %{category: category}
          |> AuditLog.list_events()
          |> Map.fetch!(:entries)
          |> Enum.map(& &1.event_type)
          |> Enum.sort()

        assert types == expected, "category #{category}"
        assert Enum.all?(types, &(Catalog.category_for(&1) == category))
      end
    end

    test "filters by time range" do
      {:ok, event} = AuditEventQueries.insert(%{event_type: "password_change"})
      at = event.inserted_at

      assert [_event] = AuditLog.list_events(%{from: at, to: DateTime.add(at, 1)}).entries
      assert [] = AuditLog.list_events(%{from: DateTime.add(at, 1)}).entries
      assert [] = AuditLog.list_events(%{to: at}).entries
    end

    test "offers known event types grouped by category, plus logged ones" do
      {:ok, _event} =
        AuditEventQueries.insert(%{event_type: "kmeet_integration_validation_failure"})

      groups = Map.new(AuditLog.event_types_by_category())

      assert Enum.map(AuditLog.event_types_by_category(), &elem(&1, 0)) == Catalog.keys()
      assert groups["admin_role"] == ["admin_demoted", "admin_promoted"]
      assert groups["form_validation"] == ["kmeet_integration_validation_failure"]
      assert groups["other"] == []
    end
  end

  describe "retention" do
    test "defaults to 90 days and follows the admin setting" do
      assert AuditLog.retention_days() == 90

      {:ok, _settings} = AppSettings.update(%{audit_log_retention_days: 30})
      assert AuditLog.retention_days() == 30

      assert {:error, _changeset} = AppSettings.update(%{audit_log_retention_days: 0})
    end

    test "the prune worker deletes only events past the retention period" do
      {:ok, _settings} = AppSettings.update(%{audit_log_retention_days: 30})
      now = DateTime.utc_now()

      old =
        Repo.insert!(%AuditEventSchema{
          event_type: "old",
          inserted_at: DateTime.add(now, -31, :day)
        })

      recent =
        Repo.insert!(%AuditEventSchema{
          event_type: "recent",
          inserted_at: DateTime.add(now, -29, :day)
        })

      assert :ok = perform_job(AuditLogPruneWorker, %{})

      refute Repo.get(AuditEventSchema, old.id)
      assert Repo.get(AuditEventSchema, recent.id)
    end
  end
end
