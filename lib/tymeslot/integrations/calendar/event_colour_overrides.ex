defmodule Tymeslot.Integrations.Calendar.EventColourOverrides do
  @moduledoc """
  Per-event colour overrides: a user's durable choice to display one specific
  meeting or external event in a colour different from its provider-synced
  (or default) one.

  Distinct from `Tymeslot.Integrations.Calendar.EventColour`, which is the
  palette itself (which keys exist and what each maps to per provider) — this
  module is the mutation/lookup API for a user's per-event choices within
  that palette.
  """

  alias Tymeslot.Integrations.Calendar.CalendarIntegrationSchema
  alias Tymeslot.Integrations.Calendar.ColourOverrideQueries
  alias Tymeslot.Integrations.Calendar.ColourResolver
  alias Tymeslot.Integrations.Calendar.ColourWriteBack

  @type user_id :: pos_integer()
  @type integration_id :: pos_integer()
  @type integration :: CalendarIntegrationSchema.t()
  @type colour_target :: {:meeting, Ecto.UUID.t()} | {:external, integration_id(), String.t()}

  @doc """
  Sets a durable per-event colour override for `user_id` on `target`, then
  (for external events) best-effort writes it back to the provider. Returns the
  persisted override.
  """
  @spec set(user_id(), colour_target(), String.t()) ::
          {:ok, term()} | {:error, Ecto.Changeset.t()}
  def set(user_id, {:meeting, meeting_id}, colour),
    do: ColourOverrideQueries.set_meeting(user_id, meeting_id, colour)

  def set(user_id, {:external, integration_id, uid}, colour) do
    with {:ok, override} <-
           ColourOverrideQueries.set_external(user_id, integration_id, uid, colour) do
      ColourWriteBack.enqueue(user_id, integration_id, uid, colour)
      {:ok, override}
    end
  end

  @doc """
  Clears a per-event colour override for `user_id` on `target`. For external
  events the host calendar is left untouched; the next sync reconciles.
  """
  @spec clear(user_id(), colour_target()) :: :ok
  def clear(user_id, {:meeting, meeting_id}),
    do: ColourOverrideQueries.clear_meeting(user_id, meeting_id)

  def clear(user_id, {:external, integration_id, uid}) do
    # Clearing drops the override only; the host calendar is left untouched and
    # the next sync reconciles — so no write-back is enqueued here.
    ColourOverrideQueries.clear_external(user_id, integration_id, uid)
  end

  @doc """
  Returns a user's colour overrides as a lookup map keyed for the resolver:
  `{:meeting, id}` / `{:external, integration_id, uid}` => palette key.
  """
  @spec overrides_for(user_id()) :: %{optional(tuple()) => String.t()}
  def overrides_for(user_id), do: ColourOverrideQueries.for_user(user_id)

  @doc """
  Resolves the palette key to display for an event: the user's durable
  override wins, else the provider-synced colour, else `nil` (caller applies
  its own source/integration default).
  """
  @spec resolve(override :: String.t() | nil, provider_colour :: String.t() | nil) ::
          String.t() | nil
  def resolve(override, provider_colour),
    do: ColourResolver.resolve(override, provider_colour)
end
