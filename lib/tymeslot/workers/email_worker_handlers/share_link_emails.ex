defmodule Tymeslot.Workers.EmailWorkerHandlers.ShareLinkEmails do
  @moduledoc """
  Handles the booking-links email a host sends from the dashboard
  (`Tymeslot.ShareLinks`).

  Links are rebuilt from the host's current profile and meeting types, not
  taken from the job args: a link whose meeting type was deleted or
  deactivated since the send was requested is dropped, and a job left with no
  link at all is discarded rather than mailing an empty invitation.
  """

  require Logger

  alias Tymeslot.Emails.Delivery
  alias Tymeslot.Emails.Templates.ShareLinks, as: ShareLinksEmail
  alias Tymeslot.Profiles
  alias Tymeslot.ShareLinks
  alias Tymeslot.Workers.DeliveryClaims

  @spec handle_share_links(%{String.t() => term()}, DeliveryClaims.job_id()) ::
          :ok | {:error, term()} | {:discard, String.t()}
  def handle_share_links(
        %{
          "user_id" => user_id,
          "recipient_email" => recipient_email,
          "link_keys" => link_keys,
          "message" => message
        },
        job_id
      ) do
    with {:ok, profile} <- Profiles.get_profile_by_user_id(user_id),
         [_first | _rest] = links <-
           profile |> ShareLinks.links_for() |> ShareLinks.select_links(link_keys) do
      result =
        DeliveryClaims.once(job_id, "recipient", fn ->
          profile
          |> ShareLinksEmail.render(links, recipient_email, message)
          |> Delivery.deliver()
        end)

      case result do
        {:error, reason} -> {:error, reason}
        _delivered -> :ok
      end
    else
      {:error, :not_found} ->
        Logger.warning("Skipping share links email — host profile not found", user_id: user_id)
        {:discard, "profile not found"}

      [] ->
        Logger.info("Skipping share links email — none of the shared links exist any more",
          user_id: user_id
        )

        {:discard, "no shareable links left"}
    end
  end
end
