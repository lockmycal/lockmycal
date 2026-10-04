defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.ChoiceToggle do
  @moduledoc """
  A choice from a short, closed set, drawn as the row of pill toggles the
  admin settings use rather than a select, so every option is visible at
  once.

  Each pill wraps a visually hidden native radio (or checkbox, with
  `multiple`): the choice then travels with the form's `phx-change` like any
  other field, and the browser keeps the keyboard behaviour and group
  semantics of the native control.

  With `multiple`, a blank entry is always posted first. Unticking the last
  box would otherwise send no key at all, which a changeset reads as
  "unchanged" rather than "none"; the owning component strips the blank
  again before casting.
  """
  use Phoenix.Component

  alias TymeslotWeb.Components.CoreComponents
  alias TymeslotWeb.Components.CoreComponents.Forms

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :label, :string, required: true

  attr :options, :list,
    required: true,
    doc: "maps with :value, :label and optional :icon and :title"

  attr :multiple, :boolean, default: false, doc: "checkboxes instead of radios; `value` is a list"
  attr :required, :boolean, default: false
  attr :errors, :list, default: []
  attr :inline, :boolean, default: false, doc: "label and description beside the pills"
  slot :description

  # With `inline`, the label and description sit to the left and the pills to
  # the right, for a yes/no setting that reads better next to its explanation.
  # A `<legend>` cannot take part in that flex row, so the group is named via
  # `aria-labelledby` instead.
  @spec choice_toggle(map()) :: Phoenix.LiveView.Rendered.t()
  def choice_toggle(%{inline: true} = assigns) do
    ~H"""
    <fieldset id={@id} class="form-field-wrapper" aria-labelledby={"#{@id}-label"}>
      <div class="flex items-center justify-between gap-4 flex-wrap">
        <div class="min-w-0 flex-1">
          <span id={"#{@id}-label"} class="label block">
            {@label}
            <span :if={@required} class="text-red-500 ml-0.5">*</span>
          </span>
          <p
            :if={@description != []}
            class="text-token-xs text-neutral-500 dark:text-twilight-indigo-200 font-medium normal-case tracking-normal mt-1"
          >
            {render_slot(@description)}
          </p>
        </div>
        <.choice_pills id={@id} name={@name} value={@value} options={@options} multiple={@multiple} />
      </div>
      <Forms.field_error errors={@errors} id={@errors != [] && "#{@id}-error"} />
    </fieldset>
    """
  end

  def choice_toggle(assigns) do
    ~H"""
    <fieldset id={@id} class="form-field-wrapper">
      <legend class="label mb-2 block">
        {@label}
        <span :if={@required} class="text-red-500 ml-0.5">*</span>
      </legend>
      <p
        :if={@description != []}
        class="text-token-xs text-neutral-500 dark:text-twilight-indigo-200 font-medium normal-case tracking-normal -mt-1 mb-2"
      >
        {render_slot(@description)}
      </p>
      <.choice_pills id={@id} name={@name} value={@value} options={@options} multiple={@multiple} />
      <Forms.field_error errors={@errors} id={@errors != [] && "#{@id}-error"} />
    </fieldset>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, required: true
  attr :options, :list, required: true
  attr :multiple, :boolean, required: true

  defp choice_pills(assigns) do
    ~H"""
    <input :if={@multiple} type="hidden" name={@name} value="" />
    <div class="inline-flex flex-wrap items-center max-w-full p-1 bg-white dark:bg-twilight-indigo-900 border-2 border-neutral-300 dark:border-twilight-indigo-700 rounded-token-xl shadow-sm gap-1">
      <label
        :for={option <- @options}
        title={option[:title]}
        data-testid={"#{@id}-option"}
        data-value={option.value}
        class={[
          "inline-flex items-center gap-1.5 px-3 py-1.5 rounded-token-lg text-token-xs font-black uppercase tracking-wider transition-all cursor-pointer",
          "has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-primary-400 has-[:focus-visible]:ring-offset-1",
          if(selected?(option.value, @value, @multiple),
            do: "bg-primary-600 text-white shadow-md shadow-primary-200/40",
            else:
              "text-neutral-500 dark:text-neutral-400 hover:bg-neutral-50 dark:hover:bg-twilight-indigo-800 hover:text-neutral-900 dark:hover:text-neutral-100"
          )
        ]}
      >
        <input
          type={if @multiple, do: "checkbox", else: "radio"}
          name={@name}
          value={option.value}
          checked={selected?(option.value, @value, @multiple)}
          class="sr-only"
        />
        <CoreComponents.icon :if={option[:icon]} name={option.icon} class="w-4 h-4 shrink-0" />
        <span>{option.label}</span>
      </label>
    </div>
    """
  end

  # The changeset holds ids as integers and a kind as a string;
  # the inputs' values are strings either way.
  defp selected?(option_value, values, true = _multiple),
    do: Enum.any?(List.wrap(values), &selected?(option_value, &1, false))

  defp selected?(option_value, value, false = _multiple),
    do: to_string(option_value) == to_string(value)
end
