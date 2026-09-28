defmodule TymeslotWeb.Dashboard.Admin.AuditEventRows do
  @moduledoc """
  The "Logged events" section of the Audit log settings tab: one row per
  event category of `Tymeslot.Security.AuditLog.Catalog`, each with an
  Enabled/Disabled switch that records or skips that category in the audit
  log.

  Its own section rather than the generic loop in
  `TymeslotWeb.Dashboard.Admin.SettingsView` because the whole list is one
  app setting (`:audit_log_events`, a map of overrides) rather than a setting
  per row. It reuses the generic rows' look; every switch fires
  `"set_audit_event"`, handled by `TymeslotWeb.Dashboard.Admin.HubComponent`.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Security.AuditLog.Catalog
  alias TymeslotWeb.Dashboard.Admin.Formatters

  attr :overrides, :map, required: true, doc: "category_key => boolean"
  attr :target, :any, required: true

  @spec audit_events_section(map()) :: Phoenix.LiveView.Rendered.t()
  def audit_events_section(assigns) do
    rows =
      Enum.map(Catalog.categories(), fn %{key: key} ->
        %{key: key, enabled: Catalog.enabled?(key, assigns.overrides)}
      end)

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <section>
      <.subsection_header
        icon="hero-list-bullet"
        title={Formatters.section_label(:audit_events)}
        class="mb-3"
      />

      <div class="card-glass p-0! overflow-hidden divide-y divide-neutral-100 dark:divide-twilight-indigo-800">
        <div
          :for={row <- @rows}
          id={"admin-audit-event-row-#{row.key}"}
          class="px-8 py-6 flex items-start justify-between gap-6 flex-wrap sm:flex-nowrap"
        >
          <div class={["min-w-0", !row.enabled && "opacity-60"]}>
            <p class="text-token-base font-bold text-neutral-900 dark:text-neutral-50">
              {category_label(row.key)}
            </p>
            <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200 mt-1">
              {description(row.key)}
            </p>
            <p
              :if={event_types(row.key) != ""}
              class="text-token-xs text-neutral-400 dark:text-twilight-indigo-300 mt-1 font-mono"
            >
              {event_types(row.key)}
            </p>
          </div>

          <div
            role="group"
            aria-label={dgettext("dashboard_admin", "Set %{name}", name: category_label(row.key))}
            class="inline-flex p-1 bg-white dark:bg-twilight-indigo-950 border-2 border-neutral-300 dark:border-twilight-indigo-700 rounded-token-xl shadow-sm gap-1 shrink-0"
          >
            <.event_tag
              key={row.key}
              state="true"
              label={dgettext("dashboard_admin", "Enabled")}
              active={row.enabled}
              target={@target}
            />
            <.event_tag
              key={row.key}
              state="false"
              label={dgettext("dashboard_admin", "Disabled")}
              active={!row.enabled}
              target={@target}
            />
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :key, :string, required: true
  attr :state, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true
  attr :target, :any, required: true

  defp event_tag(assigns) do
    ~H"""
    <button
      type="button"
      phx-target={@target}
      phx-click="set_audit_event"
      phx-value-key={@key}
      phx-value-state={@state}
      disabled={@active}
      aria-pressed={to_string(@active)}
      class={[
        "px-3 py-1.5 rounded-token-lg text-token-xs font-black uppercase tracking-wider transition-all",
        if(@active,
          do: "bg-primary-600 text-white cursor-default",
          else:
            "text-neutral-500 dark:text-neutral-50 hover:bg-neutral-50 dark:hover:bg-twilight-indigo-800 hover:text-neutral-900 dark:hover:text-neutral-50 cursor-pointer"
        )
      ]}
    >
      {@label}
    </button>
    """
  end

  @doc "The admin-facing name of an audit event category."
  @spec category_label(String.t()) :: String.t()
  def category_label("authentication"), do: dgettext("dashboard_admin", "Password sign-ins")
  def category_label("social_auth"), do: dgettext("dashboard_admin", "Social and SSO sign-ins")
  def category_label("session"), do: dgettext("dashboard_admin", "Sessions")
  def category_label("account_lockout"), do: dgettext("dashboard_admin", "Account lockouts")
  def category_label("rate_limit_violation"), do: dgettext("dashboard_admin", "Rate limit hits")
  def category_label("csrf_violation"), do: dgettext("dashboard_admin", "CSRF failures")
  def category_label("password_change"), do: dgettext("dashboard_admin", "Password changes")
  def category_label("account_deletion"), do: dgettext("dashboard_admin", "Account deletions")

  def category_label("account_status"),
    do: dgettext("dashboard_admin", "Account disabled or enabled")

  def category_label("admin_role"), do: dgettext("dashboard_admin", "Admin role changes")
  def category_label("form_validation"), do: dgettext("dashboard_admin", "Form validation")
  def category_label("honeypot"), do: dgettext("dashboard_admin", "Bot honeypot hits")
  def category_label("suspicious_input"), do: dgettext("dashboard_admin", "Suspicious input")
  def category_label("input_truncated"), do: dgettext("dashboard_admin", "Truncated input")

  def category_label("video_integration_unknown_provider"),
    do: dgettext("dashboard_admin", "Unknown video provider")

  def category_label("booking_payments"), do: dgettext("dashboard_admin", "Booking payments")

  def category_label("subscription_payments"),
    do: dgettext("dashboard_admin", "Subscription payments")

  def category_label("other"), do: dgettext("dashboard_admin", "Other security events")

  defp description("authentication"),
    do: dgettext("dashboard_admin", "Successful and failed sign-ins with email and password.")

  defp description("social_auth"),
    do: dgettext("dashboard_admin", "Successful and failed sign-ins with Google, GitHub or OIDC.")

  defp description("session"),
    do: dgettext("dashboard_admin", "A session started (sign-in) or ended (sign-out).")

  defp description("account_lockout"),
    do: dgettext("dashboard_admin", "An account locked after too many failed sign-in attempts.")

  defp description("rate_limit_violation"),
    do:
      dgettext(
        "dashboard_admin",
        "Requests refused for exceeding a rate limit. At most one entry per minute per IP address and limit."
      )

  defp description("csrf_violation"),
    do: dgettext("dashboard_admin", "A form submitted with a missing or invalid security token.")

  defp description("password_change"),
    do: dgettext("dashboard_admin", "A user changed their password.")

  defp description("account_deletion"),
    do: dgettext("dashboard_admin", "An account deletion requested and completed.")

  defp description("account_status"),
    do: dgettext("dashboard_admin", "An admin disabled or re-enabled an account.")

  defp description("admin_role"),
    do: dgettext("dashboard_admin", "An admin promoted a user to admin or demoted one.")

  defp description("form_validation"),
    do:
      dgettext(
        "dashboard_admin",
        "Results of validating dashboard forms (integrations, availability). Mostly noise."
      )

  defp description("honeypot"),
    do:
      dgettext(
        "dashboard_admin",
        "A bot filled in a hidden trap field on the signup, booking or poll form. High volume during spam waves."
      )

  defp description("suspicious_input"),
    do:
      dgettext(
        "dashboard_admin",
        "Text that looked like an injection attempt was cleaned before saving. Often a false positive."
      )

  defp description("input_truncated"),
    do: dgettext("dashboard_admin", "Input longer than allowed was shortened.")

  defp description("video_integration_unknown_provider"),
    do:
      dgettext(
        "dashboard_admin",
        "A video integration form named a provider that does not exist."
      )

  defp description("booking_payments"),
    do:
      dgettext(
        "dashboard_admin",
        "Attendees paying for bookings: paid, failed or expired checkouts, refunds and chargebacks."
      )

  defp description("subscription_payments"),
    do:
      dgettext(
        "dashboard_admin",
        "Users paying for their subscription: paid and failed payments, expired checkouts, declined charges, refunds and chargebacks."
      )

  defp description("other"),
    do: dgettext("dashboard_admin", "Any security event not covered by the categories above.")

  # The concrete event types a category covers, as they appear in the Audit
  # log tab, so an admin can match a row there to its switch here.
  defp event_types("authentication"), do: "authentication_success, authentication_failure"
  defp event_types("social_auth"), do: "social_auth_success, social_auth_failure"
  defp event_types("session"), do: "session_created, session_deleted"
  defp event_types("account_status"), do: "account_disabled, account_enabled"
  defp event_types("admin_role"), do: "admin_promoted, admin_demoted"

  defp event_types("account_deletion"),
    do: "account_deletion_request_success, account_deletion_success"

  defp event_types("form_validation"), do: "*_validation_success, *_validation_failure"
  defp event_types("honeypot"), do: "*_honeypot_*"
  defp event_types("suspicious_input"), do: "suspicious_input_sanitised"

  defp event_types("booking_payments"),
    do: "booking_payment_*, booking_refund_*, booking_dispute_*"

  defp event_types("subscription_payments"),
    do:
      "subscription_payment_*, subscription_checkout_expired, subscription_charge_failed, subscription_refund_issued, subscription_dispute_*"

  defp event_types("other"), do: ""
  defp event_types(key), do: key
end
