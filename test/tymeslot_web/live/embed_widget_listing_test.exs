defmodule TymeslotWeb.EmbedWidgetListingTest do
  @moduledoc """
  The embedded booking widget lists its own selection of meeting types
  (`show_in_embed`), independently of the public booking page (`is_private`),
  and a widget pinned to a meeting type that does not resolve shows a notice in
  the frame rather than the organiser's other types. The widget's alias
  (`/_<token>`) shows the same selection without naming the username.
  """
  use TymeslotWeb.LiveCase, async: false
  @moduletag :scheduling
  @moduletag :live

  import Mox
  import Tymeslot.Factory

  alias Tymeslot.Infrastructure.AvailabilityCache
  alias Tymeslot.TestMocks

  setup :verify_on_exit!

  setup tags do
    Mox.set_mox_from_context(tags)
    AvailabilityCache.clear_all()
    TestMocks.setup_all_mocks()

    user = insert(:user)

    profile =
      insert(:profile,
        user: user,
        username: "widgethost",
        booking_theme: "1",
        allowed_embed_domains: ["example.com"],
        embed_alias: "_widgetalias"
      )

    # A host the readiness check accepts: a default schedule and a calendar.
    schedule = insert(:availability_schedule, profile: profile, is_default: true)

    insert(:weekly_availability,
      schedule: schedule,
      day_of_week: 1,
      is_available: true,
      start_time: ~T[09:00:00],
      end_time: ~T[17:00:00]
    )

    insert(:calendar_integration, user: user, is_active: true)

    insert(:meeting_type, user: user, name: "Both", is_private: false, show_in_embed: true)

    insert(:meeting_type,
      user: user,
      name: "Public Only",
      is_private: false,
      show_in_embed: false
    )

    insert(:meeting_type, user: user, name: "Widget Only", is_private: true, show_in_embed: true)

    %{profile: profile}
  end

  # A framed request from an allow-listed site: `?embed=1` mints the embed
  # token and the Referer supplies the signed parent origin that
  # `EmbedAuthHook` checks on the connected render.
  defp embedded(conn), do: put_req_header(conn, "referer", "https://example.com/booking")

  @tag :capture_log
  test "the widget overview lists the show_in_embed types, including a private one", %{
    conn: conn,
    profile: profile
  } do
    {:ok, view, _html} = live(embedded(conn), "/#{profile.username}?embed=1")

    assert has_element?(view, "button[phx-value-duration='both']")
    assert has_element?(view, "button[phx-value-duration='widget-only']")
    refute has_element?(view, "button[phx-value-duration='public-only']")
  end

  @tag :capture_log
  test "the public overview is unchanged by show_in_embed", %{conn: conn, profile: profile} do
    {:ok, view, _html} = live(conn, "/#{profile.username}")

    assert has_element?(view, "button[phx-value-duration='both']")
    assert has_element?(view, "button[phx-value-duration='public-only']")
    refute has_element?(view, "button[phx-value-duration='widget-only']")
  end

  @tag :capture_log
  test "an unknown meeting type in the widget redirects to the in-frame notice", %{
    conn: conn,
    profile: profile
  } do
    assert {:error, {:redirect, %{to: to}}} =
             live(embedded(conn), "/#{profile.username}/no-such-type?embed=1")

    assert %URI{path: "/embed-unavailable", query: query} = URI.parse(to)
    assert %{"reason" => "meeting_type"} = URI.decode_query(query)
  end

  @tag :capture_log
  test "an unknown meeting type outside the widget still falls back to the overview", %{
    conn: conn,
    profile: profile
  } do
    assert {:error, {:redirect, %{to: to}}} = live(conn, "/#{profile.username}/no-such-type")

    assert to == "/#{profile.username}"
  end

  describe "through the widget's alias" do
    @tag :capture_log
    test "the overview lists the widget's types, framed or not", %{conn: conn} do
      {:ok, view, html} = live(conn, "/_widgetalias")

      assert has_element?(view, "button[phx-value-duration='both']")
      assert has_element?(view, "button[phx-value-duration='widget-only']")
      refute has_element?(view, "button[phx-value-duration='public-only']")
      refute html =~ "widgethost"
    end

    @tag :capture_log
    test "a type only on the public page is out of reach", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/_widgetalias"}}} =
               live(conn, "/_widgetalias/public-only")
    end

    @tag :capture_log
    test "a private type shown in the widget opens by its slug", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/_widgetalias/widget-only")

      assert has_element?(view, "button[phx-click='next_month']")
    end

    @tag :capture_log
    test "the alias does not lead to the public calendar", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/_widgetalias")
      refute html =~ "/calendar"

      {:ok, _view, calendar_html} = live(conn, "/_widgetalias/calendar")
      assert calendar_html =~ "No such organiser."
    end

    @tag :capture_log
    test "framing follows the organiser's allowed domains", %{conn: conn} do
      conn = get(embedded(conn), "/_widgetalias?embed=1")

      csp = conn |> get_resp_header("content-security-policy") |> List.first()
      assert csp =~ "frame-ancestors 'self' https://example.com"

      {:ok, view, _html} = live(embedded(build_conn()), "/_widgetalias?embed=1")
      assert has_element?(view, "button[phx-value-duration='widget-only']")
    end

    @tag :capture_log
    test "an unknown alias is not found, as an unknown username is", %{conn: conn} do
      assert_raise TymeslotWeb.NotFoundError, fn -> live(conn, "/_nosuchalias") end
    end
  end

  describe "the widget's look" do
    @tag :capture_log
    test "the bar shows only the centred logo, and the overview no calendar link", %{
      conn: conn,
      profile: profile
    } do
      {:ok, view, html} = live(embedded(conn), "/#{profile.username}?embed=1")

      assert has_element?(view, "nav.public-top-bar.public-top-bar--embedded")
      refute has_element?(view, ".language-switcher")
      refute has_element?(view, ".public-top-bar-actions")
      refute html =~ "/#{profile.username}/calendar"
    end

    @tag :capture_log
    test "the standalone page keeps its language switcher and calendar link", %{
      conn: conn,
      profile: profile
    } do
      {:ok, view, html} = live(conn, "/#{profile.username}")

      assert has_element?(view, ".language-switcher")
      refute has_element?(view, ".public-top-bar--embedded")
      assert html =~ "/#{profile.username}/calendar"
    end

    @tag :capture_log
    test "the widget follows the browser's language and falls back to English", %{
      conn: conn,
      profile: profile
    } do
      german =
        conn
        |> embedded()
        |> put_req_header("accept-language", "de-DE,de;q=0.9")
        |> get("/#{profile.username}?embed=1")

      assert german.assigns.locale == "de"

      unknown =
        build_conn()
        |> embedded()
        |> put_req_header("accept-language", "ja")
        |> get("/#{profile.username}?embed=1")

      assert unknown.assigns.locale == "en"
    end

    @tag :capture_log
    test "a chosen background replaces the theme's inside the widget only", %{
      conn: conn,
      profile: profile
    } do
      {:ok, _view, html} =
        live(embedded(conn), "/#{profile.username}?embed=1&background=%23112233")

      assert html =~ "background: #112233 !important"

      {:ok, _view, transparent} =
        live(embedded(build_conn()), "/#{profile.username}?embed=1&background=transparent")

      assert transparent =~ "background: transparent !important"

      {:ok, _view, standalone} = live(build_conn(), "/#{profile.username}?background=%23112233")
      refute standalone =~ "#112233 !important"
    end

    @tag :capture_log
    test "a background that is not a colour or transparent is ignored", %{
      conn: conn,
      profile: profile
    } do
      {:ok, _view, html} =
        live(embedded(conn), "/#{profile.username}?embed=1&background=red;}body{x:y")

      refute html =~ "!important"
    end
  end
end
