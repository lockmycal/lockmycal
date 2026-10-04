defmodule Tymeslot.MeetingTypes.FormMapperTest do
  use ExUnit.Case, async: true

  @moduletag :meeting_types
  @moduletag :unit

  alias Tymeslot.MeetingTypes.FormMapper

  defp base_params(overrides) do
    Map.merge(
      %{
        "name" => "Quick Chat",
        "duration" => "30",
        "description" => "Hi",
        "is_active" => "true",
        "allow_guests" => "false",
        "requires_approval" => "false",
        "show_as_free" => "false",
        "payment_required" => "false"
      },
      overrides
    )
  end

  defp ui_state do
    %{meeting_mode: "personal", selected_icon: "hero-bolt", selected_video_integration_id: nil}
  end

  describe "build_attrs/2 with the \"show as free\" switch" do
    test "carries it, so the meeting type saves it" do
      assert {:ok, %{show_as_free: true}} =
               FormMapper.build_attrs(base_params(%{"show_as_free" => "true"}), ui_state())

      assert {:ok, %{show_as_free: false}} =
               FormMapper.build_attrs(base_params(%{}), ui_state())
    end
  end

  describe "build_attrs/2 with translations" do
    test "omits translations entirely when the params do not carry the key" do
      assert {:ok, attrs} = FormMapper.build_attrs(base_params(%{}), ui_state())
      refute Map.has_key?(attrs, :translations)
    end

    test "passes translations through unchanged when present" do
      translations = [%{"id" => "t1", "locale" => "de", "name" => "Kurzes Gespräch"}]

      assert {:ok, attrs} =
               FormMapper.build_attrs(base_params(%{"translations" => translations}), ui_state())

      assert attrs.translations == translations
    end

    test "passes an empty translations list through, distinct from an absent key" do
      assert {:ok, attrs} =
               FormMapper.build_attrs(base_params(%{"translations" => []}), ui_state())

      assert attrs.translations == []
    end
  end
end
