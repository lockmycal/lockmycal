defmodule TymeslotWeb.Dashboard.ThemeSettings.BookingTextForm do
  @moduledoc """
  Dashboard form for the booking page's introductory heading, greeting and
  instruction.

  The wording is stored on the profile and applies to every theme, so this form
  spells out what a single heading replaces in each of them: the two themes open
  differently by default, and an organiser editing one field needs to see both
  sentences it displaces.

  ## Saving

  Every change persists on its own; there is no save button. Text edits autosave
  on a debounce, and the switch persists immediately. `:save_status` drives the
  indicator, mirroring the meeting-type editor's vocabulary:

  | Atom        | Indicator copy            | When set                                        |
  |-------------|---------------------------|-------------------------------------------------|
  | `:idle`     | nothing                   | Nothing has changed yet this session.            |
  | `:saved`    | "All changes saved"       | Persist succeeded.                               |
  | `:incomplete`| "Complete the form to save" | A required line is blank mid-edit.            |
  | `:unsaved`  | "Unsaved changes"         | Validation rejected the edit, so nothing wrote.  |
  | `:throttled`| "Too many changes…"       | Rate limit hit; the edit is held and retried.    |
  | `:error`    | "Couldn't save changes"   | Unexpected persistence failure.                  |

  The rate limit behind `:throttled` is shared with every other theme-
  customisation write, so hitting it is rarely the host's own doing and the
  edit in hand is not theirs to lose: with no save button and a debounce that
  fires after they have stopped typing, dropping it would leave the last thing
  they wrote unwritten while the indicator promised otherwise. The params are
  therefore held and retried on a backoff until they land, a later edit
  replacing whatever is held.

  ## Per-locale translations

  A language tab-switcher above the three fields lets the organiser add a
  per-locale override for each (`Tymeslot.Profiles.ProfileBookingTextTranslation`).
  The default-locale tab edits the base columns exactly as before; any other
  tab edits that locale's row instead, upserted on save
  (`shape_save_params/2`) — never both at once, and never wiping the other
  locales' rows or the base text.

  ## Turning the customisation off

  Switching off clears the three columns rather than parking them: the booking
  page goes back to the built-in, translated wording and no stale copy of an old
  heading survives in the database. Switching back on seeds the fields from the
  current defaults, which keeps the record valid at every instant. That matters
  more than it looks: with no save button, an "on but blank" state could never be
  written, so the switch would silently disagree with what was stored.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Ecto.Changeset
  alias Ecto.UUID
  alias Phoenix.HTML.Form
  alias Tymeslot.Locales
  alias Tymeslot.Profiles
  alias Tymeslot.Profiles.InputValidation
  alias Tymeslot.Profiles.ProfileBookingTextTranslation
  alias Tymeslot.Profiles.ProfileSchema
  alias Tymeslot.Security.RateLimiter
  alias Tymeslot.Themes.Catalog
  alias Tymeslot.Validation.Constraints
  alias TymeslotWeb.Components.Dashboard.LocaleTabSwitcher
  alias TymeslotWeb.Components.UI.StatusSwitch
  alias TymeslotWeb.Live.Dashboard.Shared.DashboardHelpers
  alias TymeslotWeb.Live.Scheduling.PreviewMode
  alias TymeslotWeb.Themes.Shared.BookingText

  @text_fields [:booking_heading, :booking_greeting, :booking_instruction]

  # Backoff before a held save is retried. The shared bucket allows 150 writes
  # per five minutes, so a retry every five seconds contributes at most 60 to a
  # window: quick enough to write the edit soon after the bucket clears, sparse
  # enough that the retry cannot keep it saturated by itself.
  @retry_after_ms 5_000

  @impl Phoenix.LiveComponent
  # A retry the component scheduled for itself; it carries no profile, so it
  # cannot go through the ordinary update path.
  def update(%{retry_save: true}, socket), do: {:ok, retry(socket)}

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:preview_token, fn -> System.system_time() end)
      |> assign_new(:save_status, fn -> :idle end)
      |> assign_new(:pending_params, fn -> nil end)
      |> assign_new(:retry_scheduled?, fn -> false end)
      |> assign_new(:active_translation_locale, fn -> Locales.default_locale() end)
      |> assign_form(ProfileSchema.booking_text_changeset(assigns.profile, %{}))

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id={@id} class="mt-16">
      <.section_header
        icon="hero-chat-bubble-bottom-center-text"
        title={dgettext("dashboard_appearance", "Booking Page Text")}
      />

      <div class="mb-10 max-w-2xl">
        <p class="text-xl text-tymeslot-500 font-medium leading-relaxed">
          {dgettext(
            "dashboard_appearance",
            "Replace the wording that introduces you at the top of your booking page. Applies to every theme."
          )}
        </p>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-10">
        <%!-- `phx-submit` exists only so pressing Enter in a field flushes the
        pending debounce instead of reloading the page; the change handler is
        what normally saves. --%>
        <.form
          for={@form}
          id={"#{@id}-form"}
          phx-change="save"
          phx-submit="save"
          phx-target={@myself}
          class="card-glass p-8 space-y-6"
          novalidate
        >
          <div class="flex items-start justify-between gap-6">
            <div>
              <p class="label mb-1">
                {dgettext("dashboard_appearance", "Use my own wording")}
              </p>
              <p class="text-token-xs text-tymeslot-500 font-medium normal-case tracking-normal">
                {dgettext(
                  "dashboard_appearance",
                  "Turn this off to go back to the built-in text, which is translated into every language Tymeslot supports. Your own wording is discarded."
                )}
              </p>
            </div>
            <StatusSwitch.status_switch
              id={"#{@id}-enabled"}
              checked={enabled?(@form)}
              on_change="toggle_enabled"
              target={@myself}
              class="shrink-0 mt-1"
              aria_label={dgettext("dashboard_appearance", "Use my own wording")}
            />
          </div>

          <%!-- The switch is a button, not a form control, so the flag needs a
          field of its own to travel with the submitted form. --%>
          <input
            type="hidden"
            name={@form[:booking_text_enabled].name}
            value={to_string(enabled?(@form))}
          />

          <%!-- Disabled rather than hidden, so the section keeps its shape and
          the organiser can still read what the switch controls. A disabled input
          submits nothing, which is what stops the empty fields from being
          validated as missing while the customisation is off. --%>
          <div class={["space-y-6", not enabled?(@form) && "opacity-60"]}>
            <%!-- The default-locale tab edits the base fields directly, below;
            every other tab edits the matching row of the profile's
            `booking_text_translations`, upserted on save (see `shape_save_params/2`). --%>
            <LocaleTabSwitcher.locale_tab_switcher
              active_value={@active_translation_locale}
              click_event="switch_translation_locale"
              target={@myself}
            />

            <.input
              :if={@active_translation_locale == Locales.default_locale()}
              field={@form[:booking_heading]}
              type="text"
              required={enabled?(@form)}
              disabled={not enabled?(@form)}
              phx-debounce="600"
              maxlength={Constraints.booking_heading_max_length()}
              label={dgettext("dashboard_appearance", "Heading")}
              placeholder={BookingText.default_heading(current_theme_key(@profile), name(@profile))}
            />

            <.input
              :if={@active_translation_locale == Locales.default_locale()}
              field={@form[:booking_greeting]}
              type="text"
              required={enabled?(@form)}
              disabled={not enabled?(@form)}
              phx-debounce="600"
              maxlength={Constraints.booking_welcome_line_max_length()}
              label={dgettext("dashboard_appearance", "Greeting")}
              placeholder={BookingText.default_greeting(name(@profile))}
            />

            <.input
              :if={@active_translation_locale == Locales.default_locale()}
              field={@form[:booking_instruction]}
              type="text"
              required={enabled?(@form)}
              disabled={not enabled?(@form)}
              phx-debounce="600"
              maxlength={Constraints.booking_welcome_line_max_length()}
              label={dgettext("dashboard_appearance", "Instruction")}
              placeholder={BookingText.default_instruction()}
            />

            <div :if={@active_translation_locale != Locales.default_locale()} class="space-y-6">
              <% translation = current_translation(@profile, @active_translation_locale) %>
              <.input
                name="profile_schema[translation][booking_heading]"
                type="text"
                disabled={not enabled?(@form)}
                phx-debounce="600"
                maxlength={Constraints.booking_heading_max_length()}
                label={dgettext("dashboard_appearance", "Heading")}
                value={(translation && translation.booking_heading) || ""}
                placeholder={@profile.booking_heading || ""}
              />

              <.input
                name="profile_schema[translation][booking_greeting]"
                type="text"
                disabled={not enabled?(@form)}
                phx-debounce="600"
                maxlength={Constraints.booking_welcome_line_max_length()}
                label={dgettext("dashboard_appearance", "Greeting")}
                value={(translation && translation.booking_greeting) || ""}
                placeholder={@profile.booking_greeting || ""}
              />

              <.input
                name="profile_schema[translation][booking_instruction]"
                type="text"
                disabled={not enabled?(@form)}
                phx-debounce="600"
                maxlength={Constraints.booking_welcome_line_max_length()}
                label={dgettext("dashboard_appearance", "Instruction")}
                value={(translation && translation.booking_instruction) || ""}
                placeholder={@profile.booking_instruction || ""}
              />
            </div>

            <.info_box variant={:info}>
              <p class="font-bold mb-2">
                {dgettext("dashboard_appearance", "Your heading replaces:")}
              </p>
              <ul class="space-y-1">
                <li :for={{theme_name, theme_key} <- heading_defaults()}>
                  <span class="font-semibold">{theme_name}</span>
                  <span class="text-tymeslot-500">
                    &ldquo;{BookingText.default_heading(theme_key, name(@profile))}&rdquo;
                  </span>
                  <span :if={theme_key == current_theme_key(@profile)} class="text-turquoise-600">
                    {dgettext("dashboard_appearance", "(your current theme)")}
                  </span>
                </li>
              </ul>
            </.info_box>

            <p class="text-token-sm text-tymeslot-500">
              {dgettext(
                "dashboard_appearance",
                "Your own wording is shown to everyone, in whatever language they pick. Only the built-in text is translated."
              )}
            </p>
          </div>

          <div class="flex justify-end pt-2 min-h-6">
            <.save_indicator status={@save_status} />
          </div>
        </.form>

        <div class="space-y-3">
          <p class="text-token-sm font-bold text-tymeslot-600 uppercase tracking-wider">
            {dgettext("dashboard_appearance", "Live Preview")}
          </p>
          <%= if preview_url = preview_url(@profile, @preview_token) do %>
            <iframe
              src={preview_url}
              title={dgettext("dashboard_appearance", "Booking page preview")}
              class="w-full h-[600px] rounded-token-2xl border-2 border-tymeslot-100 bg-tymeslot-50"
              loading="lazy"
            ></iframe>
            <p class="text-token-sm text-tymeslot-500">
              {dgettext("dashboard_appearance", "The preview updates as your changes are saved.")}
            </p>
          <% else %>
            <.empty_state
              message={dgettext("dashboard_appearance", "No preview yet")}
              secondary_message={
                dgettext(
                  "dashboard_appearance",
                  "Pick a username for your booking page to see it here."
                )
              }
            >
              <:icon>
                <.icon name="hero-eye-slash" class="w-8 h-8 text-tymeslot-400" />
              </:icon>
            </.empty_state>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp save_indicator(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5 text-token-sm" aria-live="polite">
      <%= case @status do %>
        <% :saved -> %>
          <.icon name="hero-check-circle-mini" class="w-4 h-4 text-green-500" />
          <span class="text-tymeslot-500">
            {dgettext("dashboard_appearance", "All changes saved")}
          </span>
        <% :incomplete -> %>
          <.icon name="hero-information-circle-mini" class="w-4 h-4 text-tymeslot-400" />
          <span class="text-tymeslot-500">
            {dgettext("dashboard_appearance", "Complete the form to save")}
          </span>
        <% :unsaved -> %>
          <.icon name="hero-arrow-path-mini" class="w-4 h-4 text-amber-500" />
          <span class="text-amber-500">{dgettext("dashboard_appearance", "Unsaved changes")}</span>
        <% :throttled -> %>
          <.icon name="hero-arrow-path-mini" class="w-4 h-4 text-amber-500 animate-spin" />
          <span class="text-amber-500">
            {dgettext("dashboard_appearance", "Too many changes - saving shortly…")}
          </span>
        <% :error -> %>
          <.icon name="hero-exclamation-triangle-mini" class="w-4 h-4 text-red-500" />
          <span class="text-red-500">
            {dgettext("dashboard_appearance", "Couldn't save changes")}
          </span>
        <% _idle -> %>
      <% end %>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("save", %{"profile_schema" => params}, socket) do
    {:noreply, persist(socket, shape_save_params(socket, params))}
  end

  # The tab-switcher that picks which locale's heading/greeting/instruction are
  # shown/edited — assigns only, never persists on its own.
  def handle_event("switch_translation_locale", %{"option" => locale}, socket) do
    if locale in Locales.supported_codes() do
      {:noreply, assign(socket, :active_translation_locale, locale)}
    else
      {:noreply, socket}
    end
  end

  # Off clears the wording, on seeds it from the defaults currently in force.
  # Both are written straight away rather than staged, because the switch has no
  # save button behind it: whatever it shows has to be what is stored.
  def handle_event("toggle_enabled", _params, socket) do
    turning_on = not enabled?(socket.assigns.form)

    params =
      socket.assigns.profile
      |> text_params(turning_on)
      |> Map.put("booking_text_enabled", turning_on)

    {:noreply, persist(socket, params)}
  end

  # On the default-locale tab, the submitted params are the base fields
  # themselves and pass through unchanged. On any other tab, the submitted
  # `"translation"` values are upserted into the profile's existing
  # `booking_text_translations` rows and that is *all* that is saved — the
  # base field keys are omitted entirely, so `validate_booking_text_present/1`
  # (which reads back the persisted value via `fetch_field!/2`) is unaffected
  # and every other locale's row is left untouched.
  defp shape_save_params(socket, params) do
    default_locale = Locales.default_locale()

    case socket.assigns.active_translation_locale do
      ^default_locale ->
        params

      locale ->
        translation_params = Map.get(params, "translation", %{})

        translations =
          upsert_translation(
            socket.assigns.profile.booking_text_translations,
            locale,
            Map.get(translation_params, "booking_heading", ""),
            Map.get(translation_params, "booking_greeting", ""),
            Map.get(translation_params, "booking_instruction", "")
          )

        %{"booking_text_translations" => Enum.map(translations, &translation_row_param/1)}
    end
  end

  defp current_translation(profile, locale),
    do: Enum.find(profile.booking_text_translations, &(&1.locale == locale))

  # Mirrors `MeetingTypeForm`'s own `upsert_translation/4`: builds the struct
  # directly, id included, since full changeset validation only happens once
  # at persist time (`ProfileBookingTextTranslation.changeset/2`).
  defp upsert_translation(translations, locale, heading, greeting, instruction) do
    heading = blank_to_nil(heading)
    greeting = blank_to_nil(greeting)
    instruction = blank_to_nil(instruction)

    case Enum.find_index(translations, &(&1.locale == locale)) do
      nil ->
        new_row = %ProfileBookingTextTranslation{
          id: UUID.generate(),
          locale: locale,
          booking_heading: heading,
          booking_greeting: greeting,
          booking_instruction: instruction
        }

        translations ++ [new_row]

      index ->
        List.update_at(translations, index, fn row ->
          %{
            row
            | booking_heading: heading,
              booking_greeting: greeting,
              booking_instruction: instruction
          }
        end)
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp translation_row_param(translation) do
    %{
      "id" => translation.id,
      "locale" => translation.locale,
      "booking_heading" => translation.booking_heading || "",
      "booking_greeting" => translation.booking_greeting || "",
      "booking_instruction" => translation.booking_instruction || ""
    }
  end

  # Clearing is what "reset to default" means at the storage layer: with the
  # columns null, every theme falls back to its own translated wording.
  defp text_params(_profile, false), do: Map.new(@text_fields, &{to_string(&1), nil})

  # Seeded from the defaults on the way back on, so the record is valid the
  # instant the switch flips. Anything already stored wins, which only happens
  # for a profile whose columns predate the switch.
  defp text_params(profile, true) do
    Map.new(@text_fields, fn field ->
      {to_string(field), Map.get(profile, field) || default_for(field, profile)}
    end)
  end

  defp default_for(:booking_heading, profile),
    do: BookingText.default_heading(current_theme_key(profile), name(profile))

  defp default_for(:booking_greeting, profile),
    do: BookingText.seed_greeting(name(profile))

  defp default_for(:booking_instruction, _profile), do: BookingText.default_instruction()

  # Clearing on the way in is what makes a newer edit replace a held one: this
  # attempt supersedes it, and only a throttle puts anything back.
  defp persist(socket, params) do
    socket = assign(socket, :pending_params, nil)

    with :ok <- check_rate_limit(socket),
         {:ok, sanitized} <- sanitize(params, socket) do
      save(socket, sanitized)
    else
      {:error, :rate_limited, _message} ->
        hold(socket, params)

      {:error, field_errors} ->
        socket
        |> assign_form(invalid_changeset(socket, params, field_errors))
        |> assign(:save_status, :unsaved)
    end
  end

  defp hold(socket, params) do
    socket
    |> schedule_retry()
    |> assign(pending_params: params, save_status: :throttled)
  end

  # One timer at a time: a host still typing while throttled would otherwise
  # stack one per keystroke, and each would spend a check of the very bucket
  # that is full. The flag clears when the retry arrives, so a retry that is
  # throttled again schedules the next one on its way back through here.
  defp schedule_retry(%{assigns: %{retry_scheduled?: true}} = socket), do: socket

  defp schedule_retry(socket) do
    send_update_after(__MODULE__, [id: socket.assigns.id, retry_save: true], @retry_after_ms)
    assign(socket, :retry_scheduled?, true)
  end

  defp retry(%{assigns: %{pending_params: nil}} = socket),
    do: assign(socket, :retry_scheduled?, false)

  defp retry(%{assigns: %{pending_params: params}} = socket) do
    socket
    |> assign(:retry_scheduled?, false)
    |> persist(params)
  end

  # The three lines are organiser-authored prose bound for a public page, so
  # they go through the shared plain-text sanitiser before the changeset sees
  # them: encoding integrity, null bytes and security logging are not things a
  # changeset can check. The cap stays in the changeset, where it has a
  # translated error.
  defp sanitize(params, socket) do
    InputValidation.validate_booking_text(params,
      metadata: DashboardHelpers.get_security_metadata(socket)
    )
  end

  defp check_rate_limit(socket) do
    case RateLimiter.check_theme_customization_rate_limit(socket.assigns.profile.user_id) do
      :ok -> :ok
      {:error, :rate_limited, message} -> {:error, :rate_limited, message}
    end
  end

  defp invalid_changeset(socket, params, field_errors) do
    changeset = ProfileSchema.booking_text_changeset(socket.assigns.profile, params)

    field_errors
    |> Enum.reduce(changeset, fn {field, message}, acc ->
      Changeset.add_error(acc, field, message)
    end)
    |> Map.put(:action, :insert)
  end

  defp save(socket, params) do
    case Profiles.update_booking_text(socket.assigns.profile, params) do
      {:ok, profile} ->
        send(self(), {:profile_updated, profile})

        socket
        |> assign(:profile, profile)
        # A new token reloads the iframe, which renders the saved wording; the
        # preview reads persisted state, not the form.
        |> assign(:preview_token, System.system_time())
        |> assign(:save_status, :saved)
        |> assign_form(ProfileSchema.booking_text_changeset(profile, %{}))

      {:error, changeset} ->
        reject(socket, changeset)
    end
  end

  # A field emptied on the way to retyping it is work in progress, not a
  # failure: autosave sees the blank as soon as the debounce fires, and
  # colouring it red mid-edit reads as though something broke. Leaving the
  # changeset without an `:action` is what keeps the inline error hidden, and
  # nothing is written either way. Any other failure (a cap, a rejected
  # encoding) is a real problem and stays visible.
  defp reject(socket, changeset) do
    if blank_required_only?(changeset) do
      socket
      |> assign_form(Map.put(changeset, :action, nil))
      |> assign(:save_status, :incomplete)
    else
      socket
      |> assign_form(Map.put(changeset, :action, :insert))
      |> assign(:save_status, :unsaved)
    end
  end

  defp blank_required_only?(%Changeset{errors: []}), do: false

  defp blank_required_only?(%Changeset{errors: errors}) do
    Enum.all?(errors, fn {_field, {_message, opts}} ->
      Keyword.get(opts, :validation) == :required
    end)
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  defp enabled?(form), do: Form.normalize_value("checkbox", form[:booking_text_enabled].value)

  defp name(profile), do: Profiles.display_name(profile)

  defp current_theme_key(profile) do
    case Catalog.id_to_key(profile.booking_theme) do
      {:ok, key} -> key
      {:error, _reason} -> Catalog.default_key()
    end
  end

  # One entry per selectable theme so the organiser sees every sentence a custom
  # heading displaces, not only the one their current theme happens to show.
  # Ordered by id so the list does not reshuffle between renders.
  defp heading_defaults do
    Catalog.active()
    |> Enum.sort_by(fn {_key, facts} -> facts.id end)
    |> Enum.map(fn {key, facts} -> {facts.name, key} end)
  end

  defp preview_url(%{username: username, user_id: user_id}, token)
       when is_binary(username) and is_integer(user_id) do
    PreviewMode.owner_path(username, user_id) <> "&t=#{token}"
  end

  defp preview_url(_profile, _token), do: nil
end
