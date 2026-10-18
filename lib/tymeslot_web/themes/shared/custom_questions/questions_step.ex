defmodule TymeslotWeb.Themes.Shared.CustomQuestions.QuestionsStep do
  @moduledoc """
  The scheduling LiveView's side of the `:questions` step: recording answers,
  moving through the wizard with Next and Back, leaving it for `:booking` or
  `:schedule`, and the engine snapshot taken on entering the step.

  `TymeslotWeb.Themes.Shared.SchedulingLive` delegates here and passes its own
  `transition_to/3`, as it does for `InfoHandlers`.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Tymeslot.CustomFields
  alias Tymeslot.Locales
  alias TymeslotWeb.Themes.Shared.CustomQuestions.Engine, as: QEngine
  alias TymeslotWeb.Themes.Shared.LiveHelpers

  @type socket :: Phoenix.LiveView.Socket.t()
  @type transition_to :: (socket(), atom(), map() -> socket())

  @doc "Handles a `{:step_event, :questions, event, data}` from the questions component."
  @spec handle_event(socket(), atom(), term(), transition_to()) :: {:noreply, socket()}
  def handle_event(socket, event, data, transition_to) do
    case event do
      :answer ->
        {id, value} = data
        engine = QEngine.answer(socket.assigns.engine, id, value)
        {:noreply, assign(socket, :engine, engine)}

      :next ->
        handle_next(socket, transition_to)

      :back ->
        handle_back(socket, transition_to)

      _other ->
        {:noreply, socket}
    end
  end

  @doc """
  Re-syncs the engine snapshot on entering `:questions`, so forward/back
  navigation always reflects the latest custom field definitions for this
  meeting type. Only re-inits when the definitions actually changed, so
  back-navigation preserves answers.
  """
  @spec enter(socket()) :: socket()
  def enter(socket) do
    meeting_type = socket.assigns[:meeting_type] || %{}
    locale = socket.assigns[:locale] || Locales.booking_default_locale()
    defs = CustomFields.snapshot_for(meeting_type, locale)

    engine =
      if defs != socket.assigns.engine.definitions,
        do: LiveHelpers.init_questions_engine(socket, defs),
        else: socket.assigns.engine

    assign(socket, :engine, engine)
  end

  # Advance within the questions wizard, or proceed to :booking when all
  # questions have been answered and validated.
  #
  # Transitions to :booking only when the booker is already on the last
  # question and presses Next — this ensures a single optional question is
  # always shown before the wizard exits, even when it validates as empty.
  defp handle_next(socket, transition_to) do
    engine = socket.assigns.engine

    if QEngine.skipped?(engine) do
      {:noreply, transition_to.(socket, :booking, %{})}
    else
      last_index = QEngine.total(engine) - 1

      cond do
        engine.current_index < last_index ->
          case QEngine.next(engine) do
            {:ok, engine} -> {:noreply, assign(socket, :engine, engine)}
            {:error, engine} -> {:noreply, assign(socket, :engine, engine)}
          end

        engine.current_index == last_index ->
          case QEngine.validate_all(engine) do
            {:ok, _answers} ->
              socket = assign(socket, :engine, QEngine.mark_reviewed(engine))
              {:noreply, transition_to.(socket, :booking, %{})}

            {:error, _errors} ->
              case QEngine.next(engine) do
                {:ok, engine} -> {:noreply, assign(socket, :engine, engine)}
                {:error, engine} -> {:noreply, assign(socket, :engine, engine)}
              end
          end

        true ->
          {:noreply, socket}
      end
    end
  end

  # Move backwards within the wizard, or return to :schedule from the first question.
  defp handle_back(socket, transition_to) do
    engine = socket.assigns.engine

    if engine.current_index == 0 do
      {:noreply, transition_to.(socket, :schedule, %{})}
    else
      {:noreply, assign(socket, :engine, QEngine.prev(engine))}
    end
  end
end
