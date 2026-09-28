defmodule Tymeslot.Integrations.AccessRevocation do
  @moduledoc """
  Revokes, at the provider, the OAuth access a user granted Tymeslot through
  their calendar and video integrations. Run by account deletion before the
  integration rows (and the tokens in them) are deleted.

  Deleting a row only forgets the token; the provider still lists Tymeslot as
  authorised on the person's account until the grant is revoked. What can be
  revoked depends on the provider:

    * **Google** (Calendar, Meet) — `GoogleOAuthHelper.revoke_token/1`. One
      grant covers every Google integration on the account, so it is revoked
      once per Google account.
    * **Zoom** — `ZoomOAuthHelper.revoke_token/1`.
    * **Microsoft** (Outlook, Teams) — Microsoft offers no per-app token
      revocation (only signing the person out of every app), so nothing is
      called; the tokens die with the row and the person can remove the app's
      consent from their Microsoft account.

  A provider account that another user also has an integration on is skipped:
  revoking would disconnect that user too (Zoom additionally calls our
  deauthorization webhook, which removes every integration on the account).

  Google push channels and Microsoft Graph subscriptions are not stopped
  either: no code stops them (not even on an ordinary disconnect), they expire
  by themselves within days, and a notification for a channel no integration
  owns any more is ignored by `Tymeslot.Integrations.Calendar.Webhooks`.

  Everything is best effort. A failure is logged and counted, never raised:
  the account deletion that runs this must not be held up by a provider.
  """

  require Logger

  alias Tymeslot.Integrations.Calendar.CalendarIntegrationQueries
  alias Tymeslot.Integrations.Google.GoogleOAuthHelper
  alias Tymeslot.Integrations.Video.VideoIntegrationQueries
  alias Tymeslot.Integrations.Video.Zoom.ZoomOAuthHelper

  @google_calendar_providers ["google"]
  @google_video_providers ["google_meet"]

  @microsoft_calendar_providers ["outlook"]
  @microsoft_video_providers ["teams"]

  @type summary :: %{
          revoked: non_neg_integer(),
          skipped: non_neg_integer(),
          failed: non_neg_integer()
        }

  @doc """
  Whether the user has an Outlook or Teams integration, whose consent this
  module cannot revoke (see the moduledoc).
  """
  @spec microsoft_consent?(pos_integer()) :: boolean()
  def microsoft_consent?(user_id) do
    Enum.any?(
      CalendarIntegrationQueries.list_all_for_user(user_id),
      &(&1.provider in @microsoft_calendar_providers)
    ) or
      Enum.any?(
        VideoIntegrationQueries.list_all_for_user(user_id),
        &(&1.provider in @microsoft_video_providers)
      )
  end

  @doc """
  Revokes the user's Google and Zoom grants. Returns how many grants were
  revoked, skipped (shared account, or no token to revoke) and failed.
  """
  @spec revoke_for_user(pos_integer()) :: summary()
  def revoke_for_user(user_id) do
    calendar = CalendarIntegrationQueries.list_all_for_user(user_id)
    video = VideoIntegrationQueries.list_all_for_user(user_id)

    grants =
      google_grants(calendar, video) ++
        Enum.map(Enum.filter(video, &(&1.provider == "zoom")), &zoom_grant/1)

    Enum.reduce(grants, %{revoked: 0, skipped: 0, failed: 0}, fn grant, acc ->
      outcome = revoke(grant, user_id)
      Map.update!(acc, outcome, &(&1 + 1))
    end)
  end

  # Google integrations are grouped by account: every one of them holds a
  # token for the same grant, and one revocation ends it. The refresh token is
  # preferred — revoking it also invalidates the access tokens issued from it.
  defp google_grants(calendar, video) do
    (Enum.filter(calendar, &(&1.provider in @google_calendar_providers)) ++
       Enum.filter(video, &(&1.provider in @google_video_providers)))
    |> Enum.group_by(& &1.provider_account_id)
    |> Enum.map(fn {account_id, integrations} ->
      %{
        provider: :google,
        account_id: account_id,
        token: Enum.find_value(integrations, &(&1.refresh_token || &1.access_token)),
        integration_ids: Enum.map(integrations, & &1.id)
      }
    end)
  end

  defp zoom_grant(integration) do
    %{
      provider: :zoom,
      account_id: integration.provider_account_id,
      token: integration.access_token,
      integration_ids: [integration.id]
    }
  end

  defp revoke(%{token: nil} = grant, _user_id) do
    log_skip(grant, :no_token)
    :skipped
  end

  defp revoke(%{account_id: account_id} = grant, user_id) when is_binary(account_id) do
    if shared_with_other_user?(grant, user_id) do
      log_skip(grant, :shared_account)
      :skipped
    else
      call_provider(grant)
    end
  end

  # No recorded account id means the account can't be checked for other
  # users — an integration from before account ids were stored. Revoking
  # blind could cut off someone else, so it is left alone.
  defp revoke(grant, _user_id) do
    log_skip(grant, :unknown_account)
    :skipped
  end

  defp shared_with_other_user?(%{provider: :google, account_id: account_id}, user_id) do
    CalendarIntegrationQueries.account_used_by_other_user?(
      @google_calendar_providers,
      account_id,
      user_id
    ) or
      VideoIntegrationQueries.account_used_by_other_user?(
        @google_video_providers,
        account_id,
        user_id
      )
  end

  defp shared_with_other_user?(%{provider: :zoom, account_id: account_id}, user_id) do
    VideoIntegrationQueries.account_used_by_other_user?(["zoom"], account_id, user_id)
  end

  defp call_provider(%{provider: provider, token: token} = grant) do
    result =
      case provider do
        :google -> GoogleOAuthHelper.revoke_token(token)
        :zoom -> ZoomOAuthHelper.revoke_token(token)
      end

    case result do
      :ok ->
        Logger.info("Revoked OAuth access at provider",
          provider: provider,
          integration_ids: grant.integration_ids
        )

        :revoked

      {:error, reason} ->
        Logger.warning("Could not revoke OAuth access at provider",
          provider: provider,
          integration_ids: grant.integration_ids,
          reason: inspect(reason)
        )

        :failed
    end
  end

  defp log_skip(grant, reason) do
    Logger.info("Skipped OAuth revocation",
      provider: grant.provider,
      integration_ids: grant.integration_ids,
      reason: reason
    )
  end
end
