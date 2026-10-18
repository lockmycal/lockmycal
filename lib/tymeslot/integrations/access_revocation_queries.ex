defmodule Tymeslot.Integrations.AccessRevocationQueries do
  @moduledoc """
  The reads `Tymeslot.Integrations.AccessRevocation` needs before revoking a
  provider grant: whether another user still has an integration on the same
  provider account.

  Revoking OAuth access at Google or Zoom ends the grant for the whole
  provider account, so account deletion checks this before revoking and
  leaves the grant alone while someone else still depends on it.
  """

  import Ecto.Query

  alias Tymeslot.Integrations.Calendar.CalendarIntegrationSchema
  alias Tymeslot.Integrations.Video.VideoIntegrationSchema
  alias Tymeslot.Repo

  @doc """
  Whether a user other than `user_id` has a calendar integration on the
  provider account `provider_account_id` under any of `providers`.
  """
  @spec calendar_account_used_by_other_user?([String.t()], String.t(), integer()) :: boolean()
  def calendar_account_used_by_other_user?(providers, provider_account_id, user_id)
      when is_binary(provider_account_id) do
    CalendarIntegrationSchema
    |> where([c], c.provider in ^providers)
    |> where([c], c.provider_account_id == ^provider_account_id)
    |> where([c], c.user_id != ^user_id)
    |> Repo.exists?()
  end

  @doc """
  Video counterpart of `calendar_account_used_by_other_user?/3`; deleted video
  integrations do not count.
  """
  @spec video_account_used_by_other_user?([String.t()], String.t(), integer()) :: boolean()
  def video_account_used_by_other_user?(providers, provider_account_id, user_id)
      when is_binary(provider_account_id) do
    VideoIntegrationSchema
    |> where([v], is_nil(v.deleted_at))
    |> where([v], v.provider in ^providers and v.provider_account_id == ^provider_account_id)
    |> where([v], v.user_id != ^user_id)
    |> Repo.exists?()
  end
end
