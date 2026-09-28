defmodule Tymeslot.Security.AuditLog.Catalog do
  @moduledoc """
  The categories of events (security and payments) the audit log can keep,
  and which are on out of the box. An admin switches categories on and off in the dashboard
  (App Settings → Audit log); the choice is stored as overrides in the
  `:audit_log_events` app setting, and a category without an override uses
  its default here.

  Categories rather than raw event types, because several event types are
  built dynamically (`<form>_validation_failure`, `<form>_honeypot_triggered`)
  and would otherwise each need a switch of their own. An event type no
  category claims falls into `"other"`, which is on, so a new event added to
  `SecurityLogger` is recorded until someone decides otherwise.

  Off by default: input-hygiene and bot noise that describes no action by a
  person and, during an attack, would fill the table with one row per request.

  `:known` lists the concrete event types a category is known to produce, so
  the Audit tab's filter can offer them before any has been logged; a
  category matching only by pattern lists what its emitters use literally.
  """

  @categories [
    %{
      key: "authentication",
      default: true,
      prefixes: ["authentication_"],
      known: ["authentication_success", "authentication_failure"]
    },
    %{
      key: "social_auth",
      default: true,
      prefixes: ["social_auth_"],
      known: ["social_auth_success", "social_auth_failure"]
    },
    %{
      key: "session",
      default: true,
      prefixes: ["session_"],
      known: ["session_created", "session_deleted"]
    },
    %{key: "account_lockout", default: true, exact: ["account_lockout"]},
    %{key: "rate_limit_violation", default: true, exact: ["rate_limit_violation"]},
    %{key: "csrf_violation", default: true, exact: ["csrf_violation"]},
    %{key: "password_change", default: true, exact: ["password_change"]},
    %{
      key: "account_deletion",
      default: true,
      prefixes: ["account_deletion_"],
      known: ["account_deletion_request_success", "account_deletion_success"]
    },
    %{key: "account_status", default: true, exact: ["account_disabled", "account_enabled"]},
    %{key: "admin_role", default: true, exact: ["admin_promoted", "admin_demoted"]},
    %{
      key: "form_validation",
      default: false,
      suffixes: ["_validation_success", "_validation_failure"]
    },
    %{
      key: "honeypot",
      default: false,
      contains: ["_honeypot_"],
      known: [
        "booking_honeypot_triggered",
        "poll_register_honeypot_triggered",
        "signup_honeypot_resend",
        "signup_honeypot_triggered"
      ]
    },
    %{key: "suspicious_input", default: false, exact: ["suspicious_input_sanitised"]},
    %{key: "input_truncated", default: false, exact: ["input_truncated"]},
    %{
      key: "video_integration_unknown_provider",
      default: false,
      exact: ["video_integration_unknown_provider"]
    },
    %{
      key: "booking_payments",
      default: true,
      prefixes: ["booking_payment_", "booking_refund_", "booking_dispute_"],
      known: [
        "booking_payment_paid",
        "booking_payment_failed",
        "booking_payment_expired",
        "booking_refund_issued",
        "booking_refund_failed",
        "booking_dispute_opened",
        "booking_dispute_closed"
      ]
    },
    %{
      key: "subscription_payments",
      default: true,
      prefixes: [
        "subscription_payment_",
        "subscription_checkout_",
        "subscription_charge_",
        "subscription_refund_",
        "subscription_dispute_"
      ],
      known: [
        "subscription_payment_paid",
        "subscription_payment_failed",
        "subscription_checkout_expired",
        "subscription_charge_failed",
        "subscription_refund_issued",
        "subscription_dispute_opened",
        "subscription_dispute_closed"
      ]
    },
    %{key: "other", default: true}
  ]

  @keys Enum.map(@categories, & &1.key)

  @type category :: %{key: String.t(), default: boolean()}

  @doc "Every category, in the order the admin page lists them."
  @spec categories() :: [category()]
  def categories, do: Enum.map(@categories, &Map.take(&1, [:key, :default]))

  @doc "Every category key."
  @spec keys() :: [String.t()]
  def keys, do: @keys

  @doc """
  The event types known to belong to `category_key`: its `:known` list, else
  its exact names. Pattern-only categories without a `:known` list (form
  validation, `"other"`) return `[]`.
  """
  @spec known_event_types(String.t()) :: [String.t()]
  def known_event_types(category_key) do
    case Enum.find(@categories, &(&1.key == category_key)) do
      nil -> []
      category -> Map.get(category, :known, Map.get(category, :exact, []))
    end
  end

  @doc """
  How `category_key` matches event types, for building a query:
  `{:match, patterns}` with the `:exact`, `:prefixes`, `:suffixes` and
  `:contains` lists, or `{:none_of, [patterns]}` for `"other"` — every event
  type no other category claims.
  """
  @spec matcher(String.t()) :: {:match, map()} | {:none_of, [map()]}
  def matcher("other") do
    {:none_of, @categories |> Enum.reject(&(&1.key == "other")) |> Enum.map(&patterns/1)}
  end

  def matcher(category_key) do
    case Enum.find(@categories, &(&1.key == category_key)) do
      nil -> {:match, %{}}
      category -> {:match, patterns(category)}
    end
  end

  defp patterns(category), do: Map.take(category, [:exact, :prefixes, :suffixes, :contains])

  @doc "The category an event type belongs to; `\"other\"` when none claims it."
  @spec category_for(String.t()) :: String.t()
  def category_for(event_type) do
    case Enum.find(@categories, &matches?(&1, event_type)) do
      nil -> "other"
      category -> category.key
    end
  end

  @doc """
  Whether events of `category_key` are recorded, given the admin's overrides
  (`%{category_key => boolean}`).
  """
  @spec enabled?(String.t(), map() | nil) :: boolean()
  def enabled?(category_key, overrides) do
    case overrides do
      %{^category_key => value} when is_boolean(value) -> value
      _no_override -> default(category_key)
    end
  end

  defp default(category_key) do
    case Enum.find(@categories, &(&1.key == category_key)) do
      nil -> true
      category -> category.default
    end
  end

  defp matches?(category, event_type) do
    event_type in Map.get(category, :exact, []) or
      Enum.any?(Map.get(category, :prefixes, []), &String.starts_with?(event_type, &1)) or
      Enum.any?(Map.get(category, :suffixes, []), &String.ends_with?(event_type, &1)) or
      Enum.any?(Map.get(category, :contains, []), &String.contains?(event_type, &1))
  end
end
