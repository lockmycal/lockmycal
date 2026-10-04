defmodule TymeslotWeb.Themes.Shared.Components.OwnCalendar do
  @moduledoc """
  The booker's own calendar copy of a booking (`Tymeslot.Meetings.BookerCalendar`),
  as the booking flow presents it:

    * `field/1` — on the booking form, for a signed-in visitor with a calendar
      that can take the booking and no remembered choice: whether to save the
      meeting there, and whether to remember the answer.
    * `signed_out_hint/1` — on the booking form, for a visitor who is not
      signed in: that signing in first saves the booking straight to their
      calendar, with a sign-in link that returns to the form.

  Follows the shared-component pattern of `ApprovalNotice`: neutral class
  names here, visual treatment in each theme's own CSS.
  """

  use TymeslotWeb, :verified_routes
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  import TymeslotWeb.Components.CoreComponents, only: [icon: 1, input: 1]

  alias Tymeslot.Infrastructure.Config

  attr :form, Phoenix.HTML.Form, required: true
  attr :offer, :map, default: nil, doc: "the offer from `BookerCalendar.offer/2`"

  @doc "The save-to-my-calendar choice on the booking form, when one is offered."
  @spec field(map()) :: Phoenix.LiveView.Rendered.t()
  def field(assigns) do
    ~H"""
    <div :if={ask?(@offer)} class="own-calendar-field" data-testid="own-calendar-field">
      <label class="own-calendar-field__option">
        <.input
          field={@form[:save_to_own_calendar]}
          value={@form[:save_to_own_calendar].value || "true"}
          type="checkbox"
          class="own-calendar-field__checkbox"
        />
        <span class="own-calendar-field__text">
          {dgettext("booking", "Save to my default calendar (%{calendar})",
            calendar: @offer.calendar_name
          )}
        </span>
      </label>
      <label class="own-calendar-field__option own-calendar-field__option--secondary">
        <.input
          field={@form[:remember_own_calendar_choice]}
          type="checkbox"
          class="own-calendar-field__checkbox"
        />
        <span class="own-calendar-field__text">
          {dgettext("booking", "Remember for next time")}
        </span>
      </label>
    </div>
    """
  end

  defp ask?(%{choice: :ask}), do: true
  defp ask?(_offer), do: false

  attr :login_path, :string,
    default: nil,
    doc: "the sign-in path that returns to this form; `nil` for a signed-in visitor"

  attr :embedded, :boolean, default: false

  @doc """
  The sign-in hint on the booking form, for a visitor not signed in: signing
  in first brings them back to this form with the same slot, where the copy is
  offered. Not shown inside an embed, whose frame carries no session to sign
  in to.
  """
  @spec signed_out_hint(map()) :: Phoenix.LiveView.Rendered.t()
  def signed_out_hint(assigns) do
    assigns = assign(assigns, :registration_enabled, Config.registration_enabled?())

    ~H"""
    <div :if={@login_path && !@embedded} class="own-calendar-hint" data-testid="own-calendar-hint">
      <.icon name="hero-calendar-days" class="own-calendar-hint__icon" />
      <p class="own-calendar-hint__text">
        {dgettext(
          "booking",
          "Have an account? Sign in before booking and the meeting is saved straight to your calendar too."
        )}
        <.link href={@login_path} class="own-calendar-hint__link" data-testid="own-calendar-sign-in">
          {dgettext("booking", "Sign in")}
        </.link>
        <.link
          :if={@registration_enabled}
          href={~p"/auth/signup"}
          target="_blank"
          rel="noopener"
          class="own-calendar-hint__link"
        >
          {dgettext("booking", "Create an account")}
        </.link>
      </p>
    </div>
    """
  end
end
