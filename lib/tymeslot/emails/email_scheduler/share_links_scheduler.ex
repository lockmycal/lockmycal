defmodule Tymeslot.Emails.EmailScheduler.ShareLinksScheduler do
  @moduledoc """
  Schedules the "here are my booking links" email a host sends from the
  dashboard (`Tymeslot.ShareLinks`) — one job per recipient.

  Only link keys travel in the job args; the worker rebuilds the URLs from the
  host's current profile when it runs.
  """

  alias Ecto.Changeset
  alias Tymeslot.Emails.EmailScheduler.Helpers
  alias Tymeslot.Workers.EmailWorker

  require Logger

  # Guards against a double-submitted form mailing the same person twice.
  @unique_period 60

  @spec schedule_share_links_email(pos_integer(), String.t(), [String.t()], String.t()) :: :ok
  def schedule_share_links_email(user_id, recipient_email, link_keys, message) do
    result =
      %{
        "action" => "send_share_links",
        "user_id" => user_id,
        "recipient_email" => recipient_email,
        "link_keys" => link_keys,
        "message" => message
      }
      |> EmailWorker.new(
        queue: :emails,
        priority: 1,
        unique: [period: @unique_period, fields: [:args, :queue]]
      )
      |> Oban.insert()

    case result do
      {:ok, _job} ->
        :ok

      {:error, %Changeset{errors: [unique: _details]}} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to schedule share links email",
          user_id: user_id,
          error: Helpers.format_insert_error(reason)
        )

        :ok
    end
  end
end
