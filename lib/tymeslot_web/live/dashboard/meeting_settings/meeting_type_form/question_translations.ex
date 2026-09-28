defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.QuestionTranslations do
  @moduledoc """
  Params/changeset plumbing for the per-locale translation tabs of
  `QuestionEditorComponent`: folds the inputs of the active non-default locale
  into the definition params (its `label`/`help_text`/`body` and each select
  option's label) and reads a locale's current values back out.
  """

  alias Ecto.Changeset
  alias Ecto.UUID
  alias Tymeslot.Locales

  # Upserts `params["translation"]` into `:translations` when a non-default
  # locale tab is active. A no-op on the default-locale tab, which never
  # carries a "translation" key (those inputs aren't rendered there).
  @spec merge(map(), Changeset.t(), String.t()) :: map()
  def merge(params, changeset, locale) do
    if locale == Locales.default_locale() do
      params
    else
      existing =
        changeset
        |> Changeset.get_field(:translations, [])
        |> Enum.map(&translation_to_param/1)

      translation_params = Map.get(params, "translation", %{})

      params
      |> Map.put("translations", upsert_translation(existing, locale, translation_params))
      |> with_option_translations(changeset, locale)
    end
  end

  # The option inputs are only rendered on the default-locale tab, so on a
  # translation tab the options are rebuilt from the changeset with this
  # locale's label written into each. Only sent for a select question that has
  # option translation inputs on screen.
  defp with_option_translations(params, changeset, locale) do
    case get_in(params, ["translation", "options"]) do
      texts when is_map(texts) ->
        options =
          (Changeset.get_field(changeset, :options) || [])
          |> Enum.with_index()
          |> Enum.map(fn {option, index} ->
            option_param(option, locale, Map.get(texts, Integer.to_string(index)))
          end)

        Map.put(params, "options", options)

      _none ->
        params
    end
  end

  # A blank label drops the locale's row, so the option falls back to its base label.
  defp option_param(option, locale, text) do
    others =
      for t <- option.translations || [], t.locale != locale, do: option_translation_param(t)

    rows =
      if is_binary(text) and String.trim(text) != "",
        do: others ++ [%{"locale" => locale, "label" => text}],
        else: others

    %{"key" => option.key, "label" => option.label, "translations" => rows}
  end

  defp option_translation_param(t), do: %{"locale" => t.locale, "label" => t.label || ""}

  @spec option_label(struct(), String.t()) :: String.t()
  def option_label(option, locale) do
    case Enum.find(option.translations || [], &(&1.locale == locale)) do
      nil -> ""
      translation -> translation.label || ""
    end
  end

  defp upsert_translation(translations, locale, params) do
    case Enum.find_index(translations, &(&1["locale"] == locale)) do
      nil ->
        new_row = %{"id" => UUID.generate(), "locale" => locale}
        translations ++ [merge_translation_fields(new_row, params)]

      index ->
        List.update_at(translations, index, &merge_translation_fields(&1, params))
    end
  end

  # Only fields present in `params` are written, so e.g. "body" (rendered
  # only for the "note" type) never resets to blank when absent.
  defp merge_translation_fields(row, params) do
    Enum.reduce(~w(label help_text body), row, fn field, acc ->
      case Map.fetch(params, field) do
        {:ok, value} -> Map.put(acc, field, value)
        :error -> acc
      end
    end)
  end

  defp translation_to_param(translation) do
    %{
      "id" => translation.id,
      "locale" => translation.locale,
      "label" => translation.label || "",
      "help_text" => translation.help_text || "",
      "body" => translation.body || ""
    }
  end

  @spec current(Changeset.t(), String.t()) :: struct() | nil
  def current(changeset, locale) do
    changeset
    |> Changeset.get_field(:translations, [])
    |> Enum.find(&(&1.locale == locale))
  end
end
