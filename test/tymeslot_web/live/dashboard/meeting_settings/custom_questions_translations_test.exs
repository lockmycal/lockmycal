defmodule TymeslotWeb.Dashboard.MeetingSettings.CustomQuestionsTranslationsTest do
  @moduledoc """
  Per-locale translations for a custom question's label/help_text, edited
  through the same tab-switcher mechanism as the meeting type's own
  name/description (see `MeetingSettingsTest`'s "Per-locale translations"
  describe block). Split out of `CustomQuestionsSectionTest` to keep that
  module under the line-count limit.
  """
  use TymeslotWeb.LiveCase, async: false

  @moduletag :custom_fields
  @moduletag :live
  @moduletag :meeting_types

  import Tymeslot.ConfigTestHelpers
  import Tymeslot.DashboardTestHelpers
  import Tymeslot.Factory

  alias Ecto.UUID
  alias Tymeslot.Repo

  setup :setup_dashboard_user

  setup do
    # When SaaS is compiled alongside Core, its FeatureAccessChecker gates
    # custom questions behind a Pro subscription. This test exercises the
    # Core happy path, so pin the checker back to the unrestricted default.
    setup_config(:tymeslot, feature_access_checker: Tymeslot.Features.DefaultAccessChecker)
    :ok
  end

  test "translating a locale tab doesn't touch the base label/help_text", %{
    conn: conn,
    user: user
  } do
    question_id = UUID.generate()

    meeting_type =
      insert(:meeting_type,
        user: user,
        custom_fields: [
          %{
            id: question_id,
            type: "short_text",
            label: "Company name",
            help_text: "Your registered company",
            required: false,
            position: 0
          }
        ]
      )

    {:ok, view, _html} = live(conn, ~p"/dashboard/meeting-settings")

    view
    |> element("[phx-click='edit_type'][phx-value-id='#{meeting_type.id}']")
    |> render_click()

    # The form mounts with a default reminder; remove it so the hidden
    # reminder_config inputs don't break form submission.
    view |> element("button[aria-label='Remove reminder']") |> render_click()

    view
    |> element("button[phx-click='edit_question'][phx-value-id='#{question_id}']")
    |> render_click()

    # Scoped to the question editor modal: the meeting-type form's own locale
    # switcher (for name/description) is also on screen underneath and fires
    # the same event name.
    view
    |> element(
      "[id^='question-editor-wrapper'] button[phx-click='switch_translation_locale'][phx-value-option='de']"
    )
    |> render_click()

    view
    |> form("form[phx-submit='save']", %{
      "definition" => %{
        "translation" => %{"label" => "Firmenname", "help_text" => "Ihre Firma"}
      }
    })
    |> render_submit()

    # Save round-trips through `send_update` (QuestionEditorComponent ->
    # MeetingTypeForm -> Autosave), which is only guaranteed to have run by
    # the time the *next* call into the view returns — a bare `Repo.reload!`
    # right after `render_submit/1` would race it.
    render(view)

    reloaded = Repo.reload!(meeting_type)
    [field] = reloaded.custom_fields

    assert field.label == "Company name"
    assert field.help_text == "Your registered company"
    assert [translation] = field.translations
    assert translation.locale == "de"
    assert translation.label == "Firmenname"
    assert translation.help_text == "Ihre Firma"
  end

  describe "option labels" do
    setup %{user: user} do
      question_id = UUID.generate()

      meeting_type =
        insert(:meeting_type,
          user: user,
          custom_fields: [
            %{
              id: question_id,
              type: "single_select",
              label: "Size",
              required: false,
              position: 0,
              options: [
                %{key: "small", label: "Small"},
                %{key: "large", label: "Large"}
              ]
            }
          ]
        )

      {:ok, question_id: question_id, meeting_type: meeting_type}
    end

    defp open_editor(conn, meeting_type, question_id) do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meeting-settings")

      view
      |> element("[phx-click='edit_type'][phx-value-id='#{meeting_type.id}']")
      |> render_click()

      view |> element("button[aria-label='Remove reminder']") |> render_click()

      view
      |> element("button[phx-click='edit_question'][phx-value-id='#{question_id}']")
      |> render_click()

      view
    end

    defp switch_locale(view, locale) do
      view
      |> element(
        "[id^='question-editor-wrapper'] button[phx-click='switch_translation_locale'][phx-value-option='#{locale}']"
      )
      |> render_click()
    end

    test "translating an option label leaves the base labels and keys alone", %{
      conn: conn,
      meeting_type: meeting_type,
      question_id: question_id
    } do
      view = open_editor(conn, meeting_type, question_id)
      switch_locale(view, "de")

      view
      |> form("form[phx-submit='save']", %{
        "definition" => %{"translation" => %{"options" => %{"0" => "Klein"}}}
      })
      |> render_submit()

      render(view)

      [field] = Repo.reload!(meeting_type).custom_fields
      assert [small, large] = field.options
      assert {small.key, small.label} == {"small", "Small"}
      assert {large.key, large.label} == {"large", "Large"}
      assert [%{locale: "de", label: "Klein"}] = small.translations
      assert large.translations == []
    end

    test "editing base labels afterwards keeps existing option translations", %{
      conn: conn,
      meeting_type: meeting_type,
      question_id: question_id
    } do
      view = open_editor(conn, meeting_type, question_id)
      switch_locale(view, "de")

      view
      |> form("form[phx-submit='save']", %{
        "definition" => %{"translation" => %{"options" => %{"0" => "Klein"}}}
      })
      |> render_change()

      switch_locale(view, "en")

      view
      |> form("form[phx-submit='save']", %{
        "definition" => %{"options" => %{"0" => %{"label" => "Tiny"}}}
      })
      |> render_submit()

      render(view)

      [field] = Repo.reload!(meeting_type).custom_fields
      [small, _large] = field.options
      assert small.label == "Tiny"
      assert [%{locale: "de", label: "Klein"}] = small.translations
    end
  end
end
