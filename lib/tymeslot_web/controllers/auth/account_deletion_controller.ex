defmodule TymeslotWeb.AccountDeletionController do
  @moduledoc """
  Final step of a user deleting their own account.

  `TymeslotWeb.Dashboard.ProfileSettings.DeleteAccountComponent` checks the
  confirmation in the LiveView (for inline errors) and then submits its form
  here as a plain HTTP request. Scheduling the deletion revokes every session
  and disconnects the user's live sockets; done from the LiveView, that
  disconnect would race the redirect and land the user on the login page with
  a "session expired" error. Here the browser is already on a full page
  request, so the session can be cleared and the flash shown on the login page.

  The confirmation is checked again: this endpoint must hold on its own, not
  rely on the LiveView having checked first.
  """

  use TymeslotWeb, :controller
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Auth
  alias Tymeslot.Security.RateLimiter
  alias TymeslotWeb.Helpers.ClientIP

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, params) do
    user = conn.assigns.current_user
    confirmation = Map.get(params, "delete_account", %{})

    with :ok <- RateLimiter.check_auth_rate_limit(user.email, ClientIP.get(conn)),
         :ok <- Auth.verify_deletion_confirmation(user, confirmation),
         {:ok, _user} <- Auth.request_account_deletion(user, :self) do
      # The session rows are already gone (the request revoked them). The
      # cookie is cleared and renewed rather than dropped: a dropped session
      # takes the flash below with it.
      conn
      |> clear_session()
      |> configure_session(renew: true)
      |> put_flash(
        :info,
        dgettext(
          "dashboard_profile",
          "Your account has been scheduled for deletion. All your data will be removed shortly."
        )
      )
      |> redirect(to: ~p"/auth/login")
    else
      error ->
        conn
        |> put_flash(:error, error_message(error))
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  defp error_message({:error, :rate_limited, message}), do: message

  defp error_message({:error, :last_admin}),
    do:
      dgettext(
        "dashboard_profile",
        "You are the only admin. Promote another user to admin before deleting your account."
      )

  defp error_message({:error, reason}) when reason in [:invalid_password, :email_mismatch],
    do:
      dgettext(
        "dashboard_profile",
        "Your account was not deleted: the confirmation did not match."
      )

  defp error_message(_error),
    do: dgettext("dashboard_profile", "Could not delete your account. Please try again.")
end
