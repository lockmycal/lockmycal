defmodule Tymeslot.Profiles.EmbedAliasTest do
  @moduledoc """
  The booking widget's alias (`Tymeslot.Profiles.EmbedAlias`): how a booking
  path segment resolves to a profile, generating, replacing and removing an
  alias, and the `:embed_alias_allowed` gate on the user-facing writes.
  """

  # async: false — mutates the global :feature_access_checker application env,
  # same reasoning as test/tymeslot/profiles/username_gating_test.exs.
  use Tymeslot.DataCase, async: false

  @moduletag :profiles
  @moduletag :database

  alias Ecto.Changeset
  alias Tymeslot.MeetingTypes
  alias Tymeslot.Profiles

  setup do
    previous_checker = Application.get_env(:tymeslot, :feature_access_checker)

    on_exit(fn ->
      Application.put_env(:tymeslot, :feature_access_checker, previous_checker)
    end)

    %{profile: insert(:profile, username: "aliashost")}
  end

  describe "resolving a booking path segment" do
    test "a username resolves as before", %{profile: profile} do
      assert %{id: id} = Profiles.get_profile_by_handle("aliashost")
      assert id == profile.id
    end

    test "an alias resolves to its profile, and is told apart by its prefix", %{profile: profile} do
      {:ok, %{embed_alias: embed_alias}} = Profiles.generate_embed_alias(profile)

      assert Profiles.embed_alias?(embed_alias)
      refute Profiles.embed_alias?("aliashost")
      assert %{id: id} = Profiles.get_profile_by_handle(embed_alias)
      assert id == profile.id
    end

    test "an unknown alias resolves to nothing" do
      assert Profiles.get_profile_by_handle("_nosuchalias") == nil
    end
  end

  describe "generating and removing" do
    test "an alias is the prefix and a random token", %{profile: profile} do
      assert {:ok, %{embed_alias: "_" <> token}} = Profiles.generate_embed_alias(profile)
      assert token =~ ~r/^[a-z2-7]{16}$/
    end

    test "a new alias replaces the old one, which stops resolving", %{profile: profile} do
      {:ok, first} = Profiles.generate_embed_alias(profile)
      {:ok, second} = Profiles.generate_embed_alias(first)

      refute second.embed_alias == first.embed_alias
      assert Profiles.get_profile_by_handle(first.embed_alias) == nil
      assert %{id: id} = Profiles.get_profile_by_handle(second.embed_alias)
      assert id == profile.id
    end

    test "clearing removes the alias", %{profile: profile} do
      {:ok, with_alias} = Profiles.generate_embed_alias(profile)

      assert {:ok, %{embed_alias: nil}} = Profiles.clear_embed_alias(with_alias)
      assert Profiles.get_profile_by_handle(with_alias.embed_alias) == nil
    end
  end

  describe "the :embed_alias_allowed gate" do
    setup do
      Application.put_env(
        :tymeslot,
        :feature_access_checker,
        Tymeslot.Profiles.EmbedAliasTest.DenyAccessChecker
      )

      :ok
    end

    test "generating and clearing are refused and change nothing", %{profile: profile} do
      assert {:error, :insufficient_plan} = Profiles.generate_embed_alias(profile)
      assert Repo.reload!(profile).embed_alias == nil

      {:ok, with_alias} = Repo.update(Changeset.change(profile, embed_alias: "_kept"))
      assert {:error, :insufficient_plan} = Profiles.clear_embed_alias(with_alias)
      assert Repo.reload!(profile).embed_alias == "_kept"
    end

    test "the system reset ignores the gate", %{profile: profile} do
      {:ok, with_alias} = Repo.update(Changeset.change(profile, embed_alias: "_gone"))

      assert {:ok, %{embed_alias: nil}} = Profiles.reset_embed_alias(with_alias)
    end
  end

  test "a meeting type is reachable through the alias when private or shown in the widget" do
    assert MeetingTypes.reachable_via_alias?(%{is_private: true, show_in_embed: false})
    assert MeetingTypes.reachable_via_alias?(%{is_private: false, show_in_embed: true})
    refute MeetingTypes.reachable_via_alias?(%{is_private: false, show_in_embed: false})
  end
end

defmodule Tymeslot.Profiles.EmbedAliasTest.DenyAccessChecker do
  @moduledoc false

  @spec check_access(any(), atom()) :: :ok | {:error, :insufficient_plan}
  def check_access(_user_id, :embed_alias_allowed), do: {:error, :insufficient_plan}
  def check_access(_user_id, _feature), do: :ok
end
