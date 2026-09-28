defmodule Tymeslot.Integrations.Calendar.ConnectionLimit do
  @moduledoc """
  The per-user calendar limit (`Tymeslot.Features.limit(user_id,
  :calendar_integrations)`), which caps two things:

    * how many integrations a user may *own*, paused ones included — a new
      connection is refused at the limit
      (`PrimarySelection.create_with_auto_primary/1` enforces it on every
      creation path);
    * how many may be *active* at once — turning a paused one back on is
      refused at the limit (`CalendarManagement.toggle_with_primary_rebalance/1`).

  A user can end up owning more than the limit (e.g. once a plan that allowed
  more has ended). `deactivate_over_limit/1` then pauses the surplus; the user
  keeps every connection and chooses which ones are active.

  Without a feature checker imposing a limit (Core's default) all of this is
  `:unlimited` and nothing is ever refused. Reached through the
  `Tymeslot.Integrations.Calendar` facade.
  """

  alias Tymeslot.Dashboard.DashboardContext
  alias Tymeslot.Features
  alias Tymeslot.Integrations.Calendar.CalendarIntegrationQueries
  alias Tymeslot.Integrations.{CalendarManagement, CalendarPrimary}

  @type t :: %{
          count: non_neg_integer(),
          active: non_neg_integer(),
          limit: non_neg_integer() | :unlimited,
          reached?: boolean(),
          activation_reached?: boolean()
        }

  @doc """
  The user's integrations against their limit: `reached?` refuses a new
  connection, `activation_reached?` refuses turning a paused one on.
  """
  @spec status(pos_integer()) :: t()
  def status(user_id) when is_integer(user_id) do
    count = CalendarIntegrationQueries.count_for_user(user_id)
    active = CalendarIntegrationQueries.count_active_for_user(user_id)
    limit = Features.limit(user_id, :calendar_integrations)

    %{
      count: count,
      active: active,
      limit: limit,
      reached?: at_limit?(count, limit),
      activation_reached?: at_limit?(active, limit)
    }
  end

  @doc """
  `:ok` while the user may connect another calendar, otherwise
  `{:error, :calendar_limit_reached}` — for refusing a new connection up
  front, before any provider round trip, rather than only at insert time.
  """
  @spec check_new(pos_integer()) :: :ok | {:error, :calendar_limit_reached}
  def check_new(user_id) do
    if status(user_id).reached?, do: {:error, :calendar_limit_reached}, else: :ok
  end

  @doc """
  Whether the user may have one more active integration — for a reconnect
  that would otherwise turn a paused integration back on.
  """
  @spec may_activate?(pos_integer()) :: boolean()
  def may_activate?(user_id), do: not status(user_id).activation_reached?

  @doc """
  Pauses the user's active integrations beyond their limit. The primary
  calendar stays active, then the oldest connections; the most recently
  connected are paused. Returns the paused integrations' ids.
  """
  @spec deactivate_over_limit(pos_integer()) :: {:ok, [pos_integer()]}
  def deactivate_over_limit(user_id) when is_integer(user_id) do
    case Features.limit(user_id, :calendar_integrations) do
      :unlimited ->
        {:ok, []}

      limit ->
        primary_id = primary_integration_id(user_id)

        paused =
          user_id
          |> CalendarIntegrationQueries.list_active_for_user()
          # `false` sorts before `true`: the primary first, then oldest first.
          |> Enum.sort_by(&{&1.id != primary_id, DateTime.to_unix(&1.inserted_at), &1.id})
          |> Enum.drop(limit)
          |> Enum.flat_map(&pause/1)

        if paused != [], do: DashboardContext.invalidate_integration_status(user_id)
        {:ok, paused}
    end
  end

  defp at_limit?(_count, :unlimited), do: false
  defp at_limit?(count, limit), do: count >= limit

  defp primary_integration_id(user_id) do
    case CalendarPrimary.get_primary_calendar_integration(user_id) do
      {:ok, primary} -> primary.id
      {:error, _reason} -> nil
    end
  end

  # Through the regular toggle, so pausing does exactly what a user pausing it
  # would (primary rebalancing, health state).
  defp pause(integration) do
    case CalendarManagement.toggle_with_primary_rebalance(integration) do
      {:ok, %{is_active: false}} -> [integration.id]
      _other -> []
    end
  end
end
