defmodule TymeslotWeb.Live.Dashboard.EmbedSettingsAliasTest do
  @moduledoc """
  The Embed & Share page's "Hidden widget address" card: creating, replacing
  and removing the booking widget's alias, the embed snippets switching to it,
  and the card locked when the plan does not include it.
  """

  # async: false — the locked case swaps the global :feature_assigns and
  # :feature_access_checker application env.
  use TymeslotWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Tymeslot.AuthTestHelpers, only: [log_in_user: 2]
  import Tymeslot.Factory

  alias Ecto.Changeset
  alias Tymeslot.Repo
  alias Tymeslot.Utils.UrlBuilder

  @moduletag :dashboard
  @moduletag :live

  setup do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now())
    profile = insert(:profile, user: user, username: "aliasowner")
    conn = build_conn() |> init_test_session(%{}) |> fetch_session() |> log_in_user(user)

    {:ok, conn: conn, profile: profile, user: user}
  end

  test "creating an address switches every snippet to it, the direct link too", %{
    conn: conn,
    profile: profile
  } do
    {:ok, view, _html} = live(conn, "/dashboard/embed")

    view |> element("button[phx-click='generate_embed_alias']") |> render_click()

    embed_alias = Repo.reload!(profile).embed_alias
    assert "_" <> _token = embed_alias
    assert has_element?(view, "#embed-alias-value", embed_alias)

    html = render(view)
    assert html =~ "data-username=&quot;#{embed_alias}&quot;"
    assert html =~ "open(&#39;#{embed_alias}&#39;"
    # The direct link: the booking URL under the alias, not the username.
    assert html =~ UrlBuilder.booking_url(embed_alias)
    refute html =~ UrlBuilder.booking_url("aliasowner")
  end

  test "a new address replaces the old one after confirmation", %{
    conn: conn,
    profile: profile
  } do
    profile = Repo.update!(Changeset.change(profile, embed_alias: "_oldaddress"))
    {:ok, view, _html} = live(conn, "/dashboard/embed")

    view
    |> element("button[phx-click='ask_embed_alias_change'][phx-value-change='regenerate']")
    |> render_click()

    assert has_element?(view, "#embed-alias-change-modal")
    assert Repo.reload!(profile).embed_alias == "_oldaddress"

    view
    |> element("#embed-alias-change-modal button", "Generate a new address")
    |> render_click()

    new_alias = Repo.reload!(profile).embed_alias
    assert "_" <> _token = new_alias
    refute new_alias == "_oldaddress"
  end

  test "removing the address puts the snippets back on the username", %{
    conn: conn,
    profile: profile
  } do
    profile = Repo.update!(Changeset.change(profile, embed_alias: "_goneaddress"))
    {:ok, view, _html} = live(conn, "/dashboard/embed")

    view
    |> element("button[phx-click='ask_embed_alias_change'][phx-value-change='remove']")
    |> render_click()

    view |> element("#embed-alias-change-modal button", "Remove") |> render_click()

    assert Repo.reload!(profile).embed_alias == nil
    assert render(view) =~ "data-username=&quot;aliasowner&quot;"
  end

  test "with an address, the meeting type picker offers only types the address reaches", %{
    conn: conn,
    profile: profile,
    user: user
  } do
    Repo.update!(Changeset.change(profile, embed_alias: "_pickeraddress"))
    insert(:meeting_type, user: user, name: "Public Only", show_in_embed: false)
    insert(:meeting_type, user: user, name: "In Widget", show_in_embed: true)

    {:ok, view, _html} = live(conn, "/dashboard/embed")

    assert has_element?(view, "select#embed-meeting option[value='in-widget']")
    refute has_element?(view, "select#embed-meeting option[value='public-only']")
  end

  describe "when the plan does not include it" do
    setup do
      previous_assigns = Application.get_env(:tymeslot, :feature_assigns)
      previous_checker = Application.get_env(:tymeslot, :feature_access_checker)

      on_exit(fn ->
        Application.put_env(:tymeslot, :feature_assigns, previous_assigns)
        Application.put_env(:tymeslot, :feature_access_checker, previous_checker)
      end)

      Application.put_env(
        :tymeslot,
        :feature_access_checker,
        TymeslotWeb.Live.Dashboard.EmbedSettingsAliasTest.DenyAccessChecker
      )

      %{previous_assigns: previous_assigns}
    end

    test "the card is locked with the Pro notice", %{
      conn: conn,
      previous_assigns: previous_assigns
    } do
      Application.put_env(
        :tymeslot,
        :feature_assigns,
        Keyword.put(previous_assigns, :embed_alias_allowed, false)
      )

      {:ok, view, _html} = live(conn, "/dashboard/embed")

      assert has_element?(view, "[data-testid='embed-alias-pro-note']")
      refute has_element?(view, "button[phx-click='generate_embed_alias']")
    end

    test "the server refuses the change even when the button is still on screen", %{
      conn: conn,
      profile: profile
    } do
      # A page rendered before the downgrade still shows the button.
      {:ok, view, _html} = live(conn, "/dashboard/embed")

      view |> element("button[phx-click='generate_embed_alias']") |> render_click()

      assert Repo.reload!(profile).embed_alias == nil
      assert render(view) =~ "only available on the Pro plan"
    end
  end
end

defmodule TymeslotWeb.Live.Dashboard.EmbedSettingsAliasTest.DenyAccessChecker do
  @moduledoc false

  @spec check_access(any(), atom()) :: :ok | {:error, :insufficient_plan}
  def check_access(_user_id, :embed_alias_allowed), do: {:error, :insufficient_plan}
  def check_access(_user_id, _feature), do: :ok
end
