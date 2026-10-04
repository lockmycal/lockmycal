defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.HiddenFieldsTest do
  @moduledoc """
  The create-mode form posts its custom questions through hidden inputs, so
  anything missing here is silently lost on create: a question's translations
  and its options' translations must be serialised along with it.
  """
  use ExUnit.Case, async: true

  @moduletag :custom_fields
  @moduletag :live
  @moduletag :meeting_types

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Tymeslot.CustomFields.{FieldDefinition, FieldDefinitionTranslation, FieldOption}
  alias Tymeslot.CustomFields.FieldOptionTranslation
  alias TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.HiddenFields

  defp render_fields(custom_fields) do
    render_component(&HiddenFields.hidden_fields/1,
      selected_icon: "none",
      locations: [],
      reminders: [],
      custom_fields: custom_fields,
      custom_questions_allowed: true,
      translations: [],
      payments_feature_enabled: false,
      payments_charges_enabled: false,
      payment_required: false,
      payment_price: "",
      allow_guests: false,
      allow_attachments: false,
      show_as_free: false
    )
  end

  test "serialises a question's translations" do
    html =
      render_fields([
        %FieldDefinition{
          id: "q1",
          type: "short_text",
          label: "Company",
          translations: [
            %FieldDefinitionTranslation{
              id: "t1",
              locale: "de",
              label: "Firma",
              help_text: "Ihre Firma"
            }
          ]
        }
      ])

    assert html =~ ~s(name="meeting_type[custom_fields][0][translations][0][locale]")
    assert html =~ ~s(value="de")
    assert html =~ ~s(name="meeting_type[custom_fields][0][translations][0][label]")
    assert html =~ ~s(value="Firma")
    assert html =~ ~s(value="Ihre Firma")
  end

  test "serialises an option's translations" do
    html =
      render_fields([
        %FieldDefinition{
          id: "q1",
          type: "single_select",
          label: "Size",
          options: [
            %FieldOption{
              key: "small",
              label: "Small",
              translations: [%FieldOptionTranslation{locale: "de", label: "Klein"}]
            }
          ]
        }
      ])

    assert html =~
             ~s(name="meeting_type[custom_fields][0][options][0][translations][0][locale]")

    assert html =~ ~s(value="Klein")
  end
end
