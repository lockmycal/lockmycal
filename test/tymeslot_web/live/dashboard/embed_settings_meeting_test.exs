defmodule TymeslotWeb.Live.Dashboard.EmbedSettingsMeetingTest do
  @moduledoc """
  The Embed & Share page's meeting type picker: pinning every snippet and the
  live preview to one meeting type (`data-meeting`), or leaving them on the
  overview.
  """
  use TymeslotWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tymeslot.AuthTestHelpers, only: [log_in_user: 2]
  import Tymeslot.Factory

  alias Ecto.Changeset
  alias Tymeslot.Repo

  @moduletag :dashboard
  @moduletag :live

  describe "meeting type picker" do
    setup do
      user = insert(:user, onboarding_completed_at: DateTime.utc_now())
      profile = insert(:profile, user: user, username: "customuser")
      conn = build_conn() |> init_test_session(%{}) |> fetch_session() |> log_in_user(user)

      {:ok, conn: conn, profile: profile}
    end

    test "the meeting type picker offers the active types and pins every snippet to one", %{
      conn: conn,
      profile: profile
    } do
      insert(:meeting_type, user: profile.user, name: "Intro Call", is_private: true)
      insert(:meeting_type, user: profile.user, name: "Old Call", is_active: false)

      {:ok, view, _html} = live(conn, "/dashboard/embed")

      assert has_element?(view, "select#embed-meeting option[value='intro-call']")
      refute has_element?(view, "select#embed-meeting option[value='old-call']")

      view
      |> form("form[phx-change='update_customisation']", %{
        "customise" => %{"meeting" => "intro-call"}
      })
      |> render_change()

      html = render(view)
      assert html =~ "data-meeting=&quot;intro-call&quot;"
      assert html =~ "meeting: &#39;intro-call&#39;"
      assert html =~ "/customuser/intro-call"
      assert has_element?(view, "#live-preview-container[data-meeting='intro-call']")
    end

    test "rejects a meeting type the organiser has no link for", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard/embed")

      view
      |> element("form[phx-change='update_customisation']")
      |> render_change(%{"customise" => %{"meeting" => "someone-elses-type"}})

      html = render(view)
      refute html =~ "someone-elses-type"
      refute html =~ "data-meeting=&quot;"
    end
  end

  describe "widget background" do
    setup do
      user = insert(:user, onboarding_completed_at: DateTime.utc_now())
      insert(:profile, user: user, username: "bguser")
      conn = build_conn() |> init_test_session(%{}) |> fetch_session() |> log_in_user(user)

      {:ok, conn: conn}
    end

    test "the theme's background by default: no background in any snippet", %{conn: conn} do
      {:ok, view, html} = live(conn, "/dashboard/embed")

      refute html =~ "data-background=&quot;"
      refute html =~ "background: &#39;"
      refute has_element?(view, "input#embed-background-color")
    end

    test "a custom colour goes into the snippets and the preview", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard/embed")

      view
      |> element("form[phx-change='update_customisation']")
      |> render_change(%{"customise" => %{"background_mode" => "color"}})

      assert has_element?(view, "input#embed-background-color")

      view
      |> element("form[phx-change='update_customisation']")
      |> render_change(%{
        "customise" => %{"background_mode" => "color", "background_color" => "#1A2B3C"}
      })

      html = render(view)
      assert html =~ "data-background=&quot;#1a2b3c&quot;"
      assert html =~ "background: &#39;#1a2b3c&#39;"
      assert has_element?(view, "#live-preview-container[data-background='#1a2b3c']")
    end

    test "transparent, and a tampered colour is refused", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard/embed")

      view
      |> element("form[phx-change='update_customisation']")
      |> render_change(%{"customise" => %{"background_mode" => "transparent"}})

      assert render(view) =~ "data-background=&quot;transparent&quot;"

      view
      |> element("form[phx-change='update_customisation']")
      |> render_change(%{
        "customise" => %{"background_mode" => "color", "background_color" => "red;}"}
      })

      refute render(view) =~ "red;}"
      assert render(view) =~ "data-background=&quot;#ffffff&quot;"
    end
  end

  describe "saved choices" do
    setup do
      user = insert(:user, onboarding_completed_at: DateTime.utc_now())
      profile = insert(:profile, user: user, username: "saveduser")
      conn = build_conn() |> init_test_session(%{}) |> fetch_session() |> log_in_user(user)

      {:ok, conn: conn, profile: profile}
    end

    test "the Customise choices are saved and come back after a reload", %{
      conn: conn,
      profile: profile
    } do
      {:ok, view, _html} = live(conn, "/dashboard/embed")

      view
      |> element("form[phx-change='update_customisation']")
      |> render_change(%{
        "customise" => %{
          "layout" => "default",
          "locale" => "de",
          "background_mode" => "color",
          "background_color" => "#112233",
          "max_width" => "900"
        }
      })

      assert %{
               "embed_layout" => "default",
               "embed_locale" => "de",
               "embed_background_mode" => "color",
               "embed_background_color" => "#112233",
               "max_width" => "900"
             } = Repo.reload!(profile).embed_settings

      {:ok, reloaded, html} = live(conn, "/dashboard/embed")

      assert has_element?(reloaded, "select#embed-layout option[value='default'][selected]")
      assert has_element?(reloaded, "select#embed-language option[value='de'][selected]")
      assert html =~ "data-background=&quot;#112233&quot;"
      assert html =~ "maxWidth: 900"
    end

    test "the picked style is saved and the preview opens on it after a reload", %{
      conn: conn,
      profile: profile
    } do
      {:ok, view, _html} = live(conn, "/dashboard/embed")

      view |> element(".embed-option-card[phx-value-type='popup']") |> render_click()

      assert %{"selected_embed_type" => "popup"} = Repo.reload!(profile).embed_settings

      {:ok, reloaded, _html} = live(conn, "/dashboard/embed")

      assert has_element?(
               reloaded,
               ".embed-option-card[phx-value-type='popup'][data-selected='true']"
             )

      assert has_element?(reloaded, "#live-preview-container[data-embed-type='popup']")
    end

    test "an unusable stored choice falls back to the default", %{conn: conn, profile: profile} do
      Repo.update!(
        Changeset.change(profile,
          embed_settings: %{
            "embed_layout" => "mosaic",
            "embed_background_color" => "red;}",
            "selected_embed_type" => "banner"
          }
        )
      )

      {:ok, view, html} = live(conn, "/dashboard/embed")

      assert html =~ "data-layout=&quot;column&quot;"

      assert has_element?(
               view,
               ".embed-option-card[phx-value-type='inline'][data-selected='true']"
             )

      refute html =~ "red;}"
    end
  end
end
