defmodule TymeslotWeb.E2E.EmbedWidgetTest do
  @moduledoc """
  The inline booking widget end to end (#177): a host page loads `/embed.js`,
  which builds the iframe, signs the embed token and passes the parent origin,
  and the booking page renders in widget mode inside it.

  The host page is one of the app's own pages with the widget's markup put in
  by script, so it shares the test server's origin (`localhost`), which the
  profile allows for embedding. That is the same check a customer's website
  goes through, without serving a second site.
  """
  use TymeslotWeb.BrowserCase, async: false

  alias Ecto.Changeset
  alias Tymeslot.MeetingTypes
  alias Tymeslot.MeetingTypes.Slugs
  alias Tymeslot.Profiles
  alias Tymeslot.Repo

  @moduletag :e2e
  @moduletag :scheduling

  feature "data-meeting opens the widget on that meeting type, with no way back to the list",
          %{session: session} do
    %{profile: profile, types: %{public: public}} = create_embeddable_organizer()

    session
    |> visit_host_page(profile.username, meeting: Slugs.to_slug(public))
    |> focus_widget()
    |> wait_for_live()
    |> assert_has(css("[data-testid='time-slot']", minimum: 1))
    |> assert_has(css("[data-testid='schedule-actions']"))
    |> refute_has(css("[data-testid='back-step']"))
    # The widget's own look: the bar keeps only the logo.
    |> assert_has(css(".public-top-bar--embedded"))
    |> refute_has(css(".public-top-bar-actions"))
  end

  feature "the widget's list shows the types shown in the widget, not the public page's",
          %{session: session} do
    %{profile: profile} = create_embeddable_organizer()

    session
    |> visit_host_page(profile.username)
    |> focus_widget()
    |> wait_for_live()
    |> assert_has(css("[data-testid='duration-option']", minimum: 1))
    |> assert_text("Widget Only Meeting")
    |> refute_has(css("[data-testid='duration-option']", text: "Public Only Meeting"))
    |> refute_has(css("[data-testid='view-full-calendar']"))
  end

  feature "an unknown meeting type shows the notice in the frame instead of the list",
          %{session: session} do
    %{profile: profile} = create_embeddable_organizer()

    session
    |> visit_host_page(profile.username, meeting: "no-such-meeting")
    |> focus_widget()
    |> assert_has(css("h1", text: "This meeting type isn’t available"))
  end

  # ── Setup ──────────────────────────────────────────────────────────────

  # An organiser whose page may be embedded on the test server's origin, with
  # one type on the public page only and one in the widget only.
  defp create_embeddable_organizer do
    user = create_onboarded_user()
    insert(:calendar_integration, user_id: user.id, user: user)

    profile =
      user.id
      |> Profiles.get_profile()
      |> Changeset.change(allowed_embed_domains: ["localhost"])
      |> Repo.update!()

    public =
      create_meeting_type(user, "Public Only Meeting", is_private: false, show_in_embed: false)

    widget =
      create_meeting_type(user, "Widget Only Meeting", is_private: true, show_in_embed: true)

    %{profile: profile, types: %{public: public, widget: widget}}
  end

  defp create_meeting_type(user, name, visibility) do
    {:ok, meeting_type} =
      MeetingTypes.create_meeting_type(%{
        user_id: user.id,
        name: name,
        duration_minutes: 30,
        is_active: true
      })

    meeting_type |> Changeset.change(Map.new(visibility)) |> Repo.update!()
  end

  # ── Host page ──────────────────────────────────────────────────────────

  # Puts the inline snippet Embed & Share generates into an app page and loads
  # the widget script, as a customer's website would.
  defp visit_host_page(session, username, opts \\ []) do
    meeting_attr =
      case opts[:meeting] do
        nil -> ""
        slug -> ~s( data-meeting="#{slug}")
      end

    session
    |> visit("/embed-unavailable")
    |> execute_script("""
    document.body.innerHTML = '<div id="lockmycal-booking" style="width: 1000px" data-username="#{username}"#{meeting_attr}></div>';
    const script = document.createElement("script");
    script.src = "/embed.js";
    document.body.appendChild(script);
    """)
  end

  # Waits for the iframe embed.js builds and switches into it.
  defp focus_widget(session) do
    session
    |> assert_has(css("#lockmycal-booking iframe"))
    |> focus_frame(css("#lockmycal-booking iframe"))
  end
end
