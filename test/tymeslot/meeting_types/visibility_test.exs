defmodule Tymeslot.MeetingTypes.VisibilityTest do
  @moduledoc """
  Tests for the two independent listing flags of a meeting type: `is_private`
  (public booking page) and `show_in_embed` (embedded booking widget).
  """
  use Tymeslot.DataCase, async: true

  @moduletag :meeting_types
  @moduletag :database

  alias Tymeslot.MeetingTypes

  describe "public and widget listings" do
    setup do
      user = insert(:user)

      types =
        for {name, is_private, show_in_embed} <- [
              {"Both", false, true},
              {"Public Only", false, false},
              {"Widget Only", true, true},
              {"Link Only", true, false}
            ],
            into: %{} do
          {name,
           insert(:meeting_type,
             user: user,
             name: name,
             is_active: true,
             is_private: is_private,
             show_in_embed: show_in_embed
           )}
        end

      %{user: user, types: types}
    end

    test "the widget lists exactly the show_in_embed types, private or not", %{user: user} do
      names = user.id |> MeetingTypes.get_embed_meeting_types() |> Enum.map(& &1.name)

      assert Enum.sort(names) == ["Both", "Widget Only"]
    end

    test "the public page lists exactly the non-private types, whatever show_in_embed says", %{
      user: user
    } do
      names = user.id |> MeetingTypes.get_public_meeting_types() |> Enum.map(& &1.name)

      assert Enum.sort(names) == ["Both", "Public Only"]
    end

    test "every combination stays reachable by its direct link", %{user: user} do
      for slug <- ["both", "public-only", "widget-only", "link-only"] do
        assert %{} = MeetingTypes.find_by_slug(user.id, slug), "#{slug} should resolve"
      end
    end

    test "the widget leaves out an inactive type", %{user: user} do
      insert(:meeting_type, user: user, name: "Off", is_active: false, show_in_embed: true)

      names = user.id |> MeetingTypes.get_embed_meeting_types() |> Enum.map(& &1.name)

      refute "Off" in names
    end
  end

  test "a new meeting type is listed in the widget by default" do
    assert %{show_in_embed: true} = insert(:meeting_type)
  end

  test "set_show_in_embed/2 and set_private/2 change only their own flag" do
    type = insert(:meeting_type, is_private: false, show_in_embed: true)

    assert {:ok, %{is_private: false, show_in_embed: false} = type} =
             MeetingTypes.set_show_in_embed(type, false)

    assert {:ok, %{is_private: true, show_in_embed: false}} = MeetingTypes.set_private(type, true)
  end
end
