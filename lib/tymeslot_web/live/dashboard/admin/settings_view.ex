defmodule TymeslotWeb.Dashboard.Admin.SettingsView do
  @moduledoc """
  The settings tabs. Each tab renders the sections
  `TymeslotWeb.AdminLive.Tabs` assigns it, in the order declared there; each
  section is a single grouped card and each row shows the setting name, a
  short description, and a control on the right.

  Boolean settings use the two-tag Enabled/Disabled control with the active
  tag rendered as disabled. The bot-protection provider settings reuse the
  same tag-pill control with a third Off/Google/Cloudflare option instead of
  two. Score, email, text, colour, and locale settings use a small inline
  form so admins save one value at a time.

  Email branding is rendered by its own `email_branding_section/1` rather than
  through the generic loop. Its logo row takes an upload instead of a form
  field, and its accent row needs derived preview data, so routing it through
  the generic components would mean handing that state to every other setting
  as well. Both rows live in `TymeslotWeb.Dashboard.Admin.EmailBrandingRows`
  (split out to stay under the module line-count budget) but share
  `row_header/1` and `text_input_classes/2` with the generic rows here, so
  both look identical. The section's assigns come from what
  `TymeslotWeb.Dashboard.Admin.HubComponent` builds in `load_data/1`.

  A stateless view rendered inside `TymeslotWeb.Dashboard.Admin.HubComponent`
  — every interactive element carries `phx-target={@target}` so its events
  reach the hub's own `handle_event/3` rather than the parent LiveView.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.AppSettings
  alias TymeslotWeb.AdminLive.Components.LocaleSetting
  alias TymeslotWeb.AdminLive.Tabs
  alias TymeslotWeb.Dashboard.Admin.AuditEventRows
  alias TymeslotWeb.Dashboard.Admin.EmailBrandingRows
  alias TymeslotWeb.Dashboard.Admin.Formatters
  alias TymeslotWeb.Dashboard.Admin.SiteBannerRows

  attr :tab, :atom, required: true
  attr :viewer, :map, required: true
  attr :site_banner_locale, :string, required: true
  attr :effective_values, :map, required: true
  attr :email_logo_url, :string, default: nil
  attr :upload, :map, required: true
  attr :logo_errors, :list, default: []
  attr :stock_accent, :string, required: true
  attr :accent_preview, :map, default: nil
  attr :max_logo_bytes, :integer, required: true
  attr :target, :any, required: true

  @spec settings_tab(map()) :: Phoenix.LiveView.Rendered.t()
  def settings_tab(assigns) do
    grouped = Enum.group_by(AppSettings.keys(), &Formatters.section/1)

    assigns =
      assigns
      |> assign(:grouped, grouped)
      |> assign(:extension, Tabs.extension(assigns.tab))

    ~H"""
    <div>
      <%!-- Unlike the hub's own Settings/Users pill bar (a `patch`, since those
           are real routes), this one is a `phx-click` into the hub component's
           own state — there's no URL for "which settings sub-tab", see
           `HubComponent.handle_event("switch_settings_tab", ...)`. --%>
      <div class="mb-8">
        <.option_toggle
          options={Enum.map(Tabs.settings_tabs(), &{to_string(&1), Tabs.name(&1)})}
          active_value={to_string(@tab)}
          click_event="switch_settings_tab"
          target={@target}
          aria_label={dgettext("dashboard_admin", "Settings sections")}
        />
      </div>

      <%!-- A registered extension tab renders its own content; the env-override
           notice below is about app_settings, which it has nothing to do with. --%>
      <div :if={@extension}>{@extension.render(@viewer)}</div>

      <.info_box :if={!@extension} variant={:info}>
        {dgettext(
          "dashboard_admin",
          "Changes here take effect immediately and override the matching environment variables and application configuration (e.g. REGISTRATION_ENABLED, PASSWORD_AUTH_ENABLED) for this install."
        )}
      </.info_box>

      <%!-- Branding and the site banner are rendered by their own components
           rather than the generic loop, so their upload/preview state reaches
           only the section that uses it. --%>
      <div class="space-y-8 mt-6">
        <%= for section <- Tabs.sections(@tab) do %>
          <%= case section do %>
            <% :email_branding -> %>
              <.email_branding_section
                effective_values={@effective_values}
                email_logo_url={@email_logo_url}
                upload={@upload}
                logo_errors={@logo_errors}
                stock_accent={@stock_accent}
                accent_preview={@accent_preview}
                max_logo_bytes={@max_logo_bytes}
                target={@target}
              />
            <% :site_banner -> %>
              <SiteBannerRows.site_banner_section
                effective_values={@effective_values}
                locale={@site_banner_locale}
                target={@target}
              />
            <% :audit_events -> %>
              <AuditEventRows.audit_events_section
                overrides={Map.fetch!(@effective_values, :audit_log_events).value}
                target={@target}
              />
            <% _generic -> %>
              <.settings_section
                section={section}
                keys={visible_keys(section, Map.fetch!(@grouped, section), @effective_values)}
                effective_values={@effective_values}
                target={@target}
              />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :section, :atom, required: true
  attr :keys, :list, required: true
  attr :effective_values, :map, required: true
  attr :target, :any, required: true

  defp settings_section(assigns) do
    ~H"""
    <section>
      <.subsection_header
        icon={section_icon(@section)}
        title={Formatters.section_label(@section)}
        class="mb-3"
      />

      <div class="card-glass p-0! overflow-hidden divide-y divide-neutral-100 dark:divide-twilight-indigo-800">
        <.setting_row
          :for={key <- @keys}
          key={key}
          effective_values={@effective_values}
          target={@target}
        />
      </div>
    </section>
    """
  end

  # Email branding is the one section that does not fit the generic
  # key-to-control mapping: the logo takes an upload rather than a form field,
  # and the accent needs preview data no other row has a use for. It gets its
  # own section so that state stops travelling through components that ignore
  # it. A new branding setting has to be added here explicitly.
  attr :effective_values, :map, required: true
  attr :email_logo_url, :string, default: nil
  attr :upload, :map, required: true
  attr :logo_errors, :list, default: []
  attr :stock_accent, :string, required: true
  attr :accent_preview, :map, default: nil
  attr :max_logo_bytes, :integer, required: true
  attr :target, :any, required: true

  defp email_branding_section(assigns) do
    ~H"""
    <section>
      <h3 class="text-token-sm font-black uppercase tracking-wider text-neutral-500 mb-3 px-1">
        {Formatters.section_label(:email_branding)}
      </h3>

      <div class="card-glass p-0! overflow-hidden divide-y divide-neutral-100 dark:divide-twilight-indigo-800">
        <.setting_row key={:email_brand_name} effective_values={@effective_values} target={@target} />
        <EmailBrandingRows.brand_accent_row
          effective={Map.fetch!(@effective_values, :email_brand_accent)}
          stock_accent={@stock_accent}
          accent_preview={@accent_preview}
          target={@target}
        />
        <EmailBrandingRows.email_logo_row
          logo_url={@email_logo_url}
          upload={@upload}
          errors={@logo_errors}
          max_bytes={@max_logo_bytes}
          target={@target}
        />
      </div>
    </section>
    """
  end

  attr :key, :atom, required: true
  attr :effective_values, :map, required: true
  attr :target, :any, required: true

  # Public: also used by SiteBannerRows for its on/off rows, so they render
  # exactly like every other boolean setting.
  @spec setting_row(map()) :: Phoenix.LiveView.Rendered.t()
  def setting_row(assigns) do
    effective = Map.fetch!(assigns.effective_values, assigns.key)
    kind = Formatters.kind(assigns.key)

    # Two states that used to share one flag, which made every switched-off
    # boolean render its own toggle at 60% opacity - reading as "you cannot
    # click this" on the one control that is the only way back on.
    #
    # `disabled` is genuine inertness: a dependent setting whose parent is off
    # has a control that really is unusable until the parent is switched on.
    # `muted` is merely "this setting is not doing anything at the moment",
    # which is worth saying in the description but must never be said about a
    # live control.
    disabled = parent_disabled?(assigns.key, assigns.effective_values)
    muted = disabled or own_value_off?(kind, effective)

    assigns =
      assigns
      |> assign(:effective, effective)
      |> assign(:kind, kind)
      |> assign(:disabled, disabled)
      |> assign(:muted, muted)

    ~H"""
    <div
      id={"admin-setting-row-#{@key}"}
      class="px-8 py-6 flex items-start justify-between gap-6 flex-wrap sm:flex-nowrap"
    >
      <.row_header key={@key} muted={@muted} />

      <.setting_control
        kind={@kind}
        key={@key}
        effective={@effective}
        disabled={@disabled}
        target={@target}
      />
    </div>
    """
  end

  # The left-hand half of a settings row: name, description, and the
  # recommended-value chip where one applies. Public: also used by
  # EmailBrandingRows's rows, which render their own controls but stay
  # visually identical to the generic ones (split out to stay under the
  # module line-count budget).
  attr :key, :atom, required: true
  attr :muted, :boolean, default: false

  @spec row_header(map()) :: Phoenix.LiveView.Rendered.t()
  def row_header(assigns) do
    ~H"""
    <div class={["flex-1 min-w-0 transition-opacity", @muted && "opacity-60"]}>
      <h4 class="text-token-lg font-black text-neutral-900 dark:text-neutral-50 tracking-tight">
        {Formatters.humanise(@key)}
      </h4>
      <p class="mt-1 text-token-sm text-neutral-600 dark:text-neutral-300 font-medium leading-relaxed">
        {Formatters.describe(@key)}
      </p>
      <.recommended_chip
        :if={Formatters.recommended(@key) != nil}
        value={Formatters.recommended(@key)}
      />
    </div>
    """
  end

  # True when this setting depends on a parent setting that is currently
  # `false`, which makes this row's control genuinely non-interactive right
  # now (see the `disabled={@disabled}` on the score/email inputs below) — a
  # real "cannot be activated (yet)" case, not just "currently off". A
  # boolean setting simply being off is not reason enough to grey out its
  # row: the toggle is still fully clickable, so it shouldn't read as
  # inactive at a glance (only `locked` states, rendered per-tag, do that).
  # The min-score fields are a reCAPTCHA v3-only concept (Turnstile has no
  # score), so they only make sense — and only render — while the matching
  # provider selector is actually set to :google. This is a plain hide, not
  # the grey-out-but-keep-visible `parent_disabled?/2` mechanism below, which
  # only handles boolean-vs-boolean dependencies.
  defp visible_keys(:recaptcha, keys, effective_values) do
    keys
    |> reject_unless(
      :recaptcha_signup_min_score,
      :recaptcha_signup_provider,
      :google,
      effective_values
    )
    |> reject_unless(
      :recaptcha_booking_min_score,
      :recaptcha_booking_provider,
      :google,
      effective_values
    )
  end

  defp visible_keys(_section, keys, _effective_values), do: keys

  defp reject_unless(keys, key, parent_key, required_value, effective_values) do
    if Map.fetch!(effective_values, parent_key).value == required_value do
      keys
    else
      Enum.reject(keys, &(&1 == key))
    end
  end

  defp parent_disabled?(key, effective_values) do
    case Formatters.depends_on(key) do
      nil -> false
      parent -> Map.fetch!(effective_values, parent).value == false
    end
  end

  # True when this is a boolean setting that is currently in its "off" state,
  # so the row's header (label/description) should read as muted — the
  # control itself stays fully interactive; see `disabled` above for that.
  defp own_value_off?(:boolean, %{value: false}), do: true
  defp own_value_off?(_kind, _effective), do: false

  attr :kind, :atom, required: true
  attr :key, :atom, required: true
  attr :effective, :map, required: true
  attr :disabled, :boolean, default: false
  attr :target, :any, required: true

  defp setting_control(%{kind: :boolean} = assigns) do
    ~H"""
    <div
      role="group"
      aria-label={dgettext("dashboard_admin", "Set %{name}", name: Formatters.humanise(@key))}
      class="inline-flex p-1 bg-white dark:bg-twilight-indigo-950 border-2 border-neutral-300 dark:border-twilight-indigo-700 rounded-token-xl shadow-sm gap-1 shrink-0"
    >
      <.setting_tag
        key={@key}
        state="true"
        label={dgettext("dashboard_admin", "Enabled")}
        active={@effective.value == true}
        locked={true in @effective.locked_states}
        lock_reason={Formatters.lock_reason(@key, true)}
        target={@target}
      />
      <.setting_tag
        key={@key}
        state="false"
        label={dgettext("dashboard_admin", "Disabled")}
        active={@effective.value == false}
        locked={false in @effective.locked_states}
        lock_reason={Formatters.lock_reason(@key, false)}
        target={@target}
      />
    </div>
    """
  end

  defp setting_control(%{kind: :provider} = assigns) do
    # "Google" and "Cloudflare" are proper nouns/brand names — left untranslated.
    options = [
      {"off", dgettext("dashboard_admin", "Off")},
      {"google", "Google"},
      {"cloudflare", "Cloudflare"}
    ]

    assigns = assign(assigns, :options, options)

    ~H"""
    <div
      role="group"
      aria-label={dgettext("dashboard_admin", "Set %{name}", name: Formatters.humanise(@key))}
      class="inline-flex p-1 bg-white dark:bg-twilight-indigo-950 border-2 border-neutral-300 dark:border-twilight-indigo-700 rounded-token-xl shadow-sm gap-1 shrink-0"
    >
      <.setting_tag
        :for={{state, label} <- @options}
        key={@key}
        state={state}
        label={label}
        active={@effective.value == String.to_existing_atom(state)}
        locked={String.to_existing_atom(state) in @effective.locked_states}
        lock_reason={Formatters.lock_reason(@key, String.to_existing_atom(state))}
        target={@target}
      />
    </div>
    """
  end

  defp setting_control(%{kind: :score} = assigns) do
    ~H"""
    <form
      id={"admin-setting-form-#{@key}"}
      phx-change="save_setting"
      phx-submit="save_setting"
      phx-target={@target}
      class="flex items-center gap-2 shrink-0"
      aria-label={dgettext("dashboard_admin", "Set %{name}", name: Formatters.humanise(@key))}
    >
      <input type="hidden" name="key" value={Atom.to_string(@key)} />
      <input
        id={"setting-input-#{@key}"}
        type="number"
        name="value"
        min="0"
        max="1"
        step="0.05"
        phx-debounce="blur"
        value={format_score(@effective.value)}
        disabled={@disabled}
        class={text_input_classes("w-24 text-center", @disabled)}
      />
    </form>
    """
  end

  defp setting_control(%{kind: kind} = assigns) when kind in [:size_mb, :days] do
    assigns = assign(assigns, number_bounds(kind))

    ~H"""
    <form
      id={"admin-setting-form-#{@key}"}
      phx-change="save_setting"
      phx-submit="save_setting"
      phx-target={@target}
      class="flex items-center gap-2 shrink-0"
      aria-label={dgettext("dashboard_admin", "Set %{name}", name: Formatters.humanise(@key))}
    >
      <input type="hidden" name="key" value={Atom.to_string(@key)} />
      <input
        id={"setting-input-#{@key}"}
        type="number"
        name="value"
        min="1"
        max={@max}
        step="1"
        phx-debounce="blur"
        value={@effective.value}
        disabled={@disabled}
        class={text_input_classes("w-24 text-center", @disabled)}
      />
      <span class="text-token-xs font-black text-neutral-400 uppercase tracking-wider">
        {@unit}
      </span>
    </form>
    """
  end

  defp setting_control(%{kind: :email} = assigns) do
    ~H"""
    <form
      id={"admin-setting-form-#{@key}"}
      phx-change="save_setting"
      phx-submit="save_setting"
      phx-target={@target}
      class="flex items-center gap-2 shrink-0 max-w-full"
      aria-label={dgettext("dashboard_admin", "Set %{name}", name: Formatters.humanise(@key))}
    >
      <input type="hidden" name="key" value={Atom.to_string(@key)} />
      <input
        id={"setting-input-#{@key}"}
        type="email"
        name="value"
        value={@effective.value || ""}
        placeholder={dgettext("dashboard_admin", "admin@example.com")}
        phx-debounce="blur"
        disabled={@disabled}
        class={text_input_classes("w-64 max-w-full", @disabled)}
      />
    </form>
    """
  end

  defp setting_control(%{kind: :text} = assigns) do
    ~H"""
    <form
      id={"admin-setting-form-#{@key}"}
      phx-change="save_setting"
      phx-submit="save_setting"
      phx-target={@target}
      class="flex items-center gap-2 shrink-0 max-w-full"
      aria-label={dgettext("dashboard_admin", "Set %{name}", name: Formatters.humanise(@key))}
    >
      <input type="hidden" name="key" value={Atom.to_string(@key)} />
      <input
        id={"setting-input-#{@key}"}
        type="text"
        name="value"
        value={@effective.value || ""}
        placeholder={AppSettings.default_for(@key)}
        phx-debounce="blur"
        disabled={@disabled}
        class={text_input_classes("w-64 max-w-full", @disabled)}
      />
    </form>
    """
  end

  defp setting_control(%{kind: :locale} = assigns) do
    ~H"""
    <LocaleSetting.locale_control
      key={@key}
      effective={@effective}
      disabled={@disabled}
      target={@target}
    />
    """
  end

  # Shared classes for the score and email text inputs. Disabled inputs get a
  # muted background and tone-down on text, mirroring the locked boolean-tag
  # styling so disabled controls are visually unambiguous. Public: also used
  # by EmailBrandingRows.brand_accent_row/1, split out to stay under the
  # module line-count budget.
  @spec text_input_classes(String.t(), boolean()) :: [String.t()]
  def text_input_classes(size_classes, disabled?) do
    [
      "px-3 py-1.5 rounded-token-lg border-2 text-token-sm font-bold focus:outline-hidden focus:ring-2 focus:ring-primary-500 focus:border-primary-500",
      size_classes,
      if(disabled?,
        do:
          "bg-neutral-50 dark:bg-twilight-indigo-800 border-neutral-300 dark:border-twilight-indigo-700 text-neutral-300 dark:text-twilight-indigo-500 cursor-not-allowed",
        else:
          "bg-neutral-50/50 dark:bg-twilight-indigo-900/60 border-neutral-300 dark:border-twilight-indigo-700 text-neutral-900 dark:text-neutral-50"
      )
    ]
  end

  attr :value, :boolean, required: true

  defp recommended_chip(assigns) do
    ~H"""
    <div class="mt-3 inline-flex items-center gap-1.5 px-2.5 py-1 rounded-token-lg bg-primary-50 border border-primary-100">
      <.icon name="hero-check-badge-mini" class="w-4 h-4 text-primary-600" />
      <span class="text-token-xs font-bold text-primary-700">
        {dgettext("dashboard_admin", "Recommended:")} {Formatters.recommended_label(@value)}
      </span>
    </div>
    """
  end

  attr :key, :atom, required: true
  attr :state, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true
  attr :locked, :boolean, default: false
  attr :lock_reason, :string, default: nil
  attr :target, :any, required: true

  # NOTE: the param is named `state`, not `value`, because Phoenix LiveView's
  # client-side serialisation reads the button's native `value` IDL property
  # and would overwrite `phx-value-value` with the empty string.
  defp setting_tag(assigns) do
    ~H"""
    <button
      type="button"
      phx-target={@target}
      phx-click="set_setting"
      phx-value-key={@key}
      phx-value-state={@state}
      disabled={@active or @locked}
      aria-pressed={to_string(@active)}
      aria-disabled={@locked}
      title={@lock_reason}
      class={[
        "px-3 py-1.5 rounded-token-lg text-token-xs font-black uppercase tracking-wider transition-all",
        cond do
          @active ->
            "bg-primary-600 text-white cursor-default"

          @locked ->
            "bg-neutral-50 dark:bg-twilight-indigo-800 text-neutral-300 dark:text-twilight-indigo-500 cursor-not-allowed opacity-60"

          true ->
            "text-neutral-500 dark:text-neutral-50 hover:bg-neutral-50 dark:hover:bg-twilight-indigo-800 hover:text-neutral-900 dark:hover:text-neutral-50 cursor-pointer"
        end
      ]}
    >
      {@label}
    </button>
    """
  end

  defp number_bounds(:size_mb), do: %{max: 2000, unit: dgettext("dashboard_admin", "MB")}
  defp number_bounds(:days), do: %{max: 3650, unit: dgettext("dashboard_admin", "days")}

  # Renders a float as a fixed two-decimal string so the input value stays
  # human-readable (0.30 instead of 0.3000000000000001).
  defp format_score(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 2)
  end

  defp format_score(nil), do: ""

  defp section_icon(:authentication), do: "hero-key"
  defp section_icon(:recaptcha), do: "hero-shield-check"
  defp section_icon(:payments), do: "hero-credit-card"
  defp section_icon(:analytics), do: "hero-chart-bar"
  defp section_icon(:uploads), do: "hero-cloud-arrow-up"
  defp section_icon(:audit_log), do: "hero-clipboard-document-list"
  defp section_icon(:admin_alerts), do: "hero-bell-alert"
  defp section_icon(:localisation), do: "hero-language"
end
