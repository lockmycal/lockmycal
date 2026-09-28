defmodule TymeslotWeb.Dashboard.PaymentsSettings.ConnectCta do
  @moduledoc """
  Call-to-action shown when the host has no Stripe connect account yet.

  Stateless function component rendered by `PaymentsSettingsComponent`. Posts
  to the Stripe Connect onboarding endpoint via a plain form (not a LiveView
  event) so the controller can issue the OAuth redirect.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.MeetingPayments

  @spec connect_cta(map()) :: Phoenix.LiveView.Rendered.t()
  def connect_cta(assigns) do
    assigns =
      assigns
      |> assign_new(:country_options, fn -> MeetingPayments.country_options() end)
      |> assign_new(:default_country, fn -> MeetingPayments.default_country() end)

    ~H"""
    <.detail_card title={dgettext("dashboard_payments", "Connect Stripe")}>
      <p class="text-neutral-700 dark:text-neutral-200 mb-6">
        {dgettext(
          "dashboard_payments",
          "Connect Stripe to start charging for meetings. Money goes directly to your Stripe account."
        )}
      </p>
      <%!--
        Opening Stripe takes a moment (two Stripe API calls before the
        redirect). `data-submit-loading` lets the global submit handler show a
        spinner and disable the button so a slow redirect cannot be rage-clicked.
      --%>
      <form
        id="stripe-connect-form"
        action={~p"/dashboard/payments/connect"}
        method="post"
        data-submit-loading
      >
        <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
        <.input
          type="select"
          name="country"
          label={dgettext("dashboard_payments", "Your country")}
          value={@default_country}
          options={@country_options}
          class="mb-4"
        >
          <:description>
            {dgettext(
              "dashboard_payments",
              "Where you're legally based — Stripe uses this to determine what identity and payout information it will ask for."
            )}
          </:description>
        </.input>
        <.action_button type="submit" variant={:primary}>
          <span data-submit-spinner class="hidden items-center gap-2">
            <.spinner /> {dgettext("dashboard_payments", "Connecting…")}
          </span>
          <span data-submit-label>{dgettext("dashboard_payments", "Connect Stripe")}</span>
        </.action_button>
      </form>
    </.detail_card>
    """
  end
end
