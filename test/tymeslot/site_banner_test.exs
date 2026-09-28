defmodule Tymeslot.SiteBannerTest do
  use Tymeslot.DataCase, async: false

  @moduletag :ui
  @moduletag :integration

  import Tymeslot.AppSettingsEnvHelpers

  alias Ecto.Changeset
  alias Tymeslot.AppSettings
  alias Tymeslot.SiteBanner

  setup :restore_app_settings_env

  describe "for_surface/2" do
    test "is nil everywhere on an untouched install" do
      for surface <- [:app, :auth, :public],
          do: assert(SiteBanner.for_surface(surface, "en") == nil)
    end

    test "each switch gates only its own surface" do
      {:ok, _settings} =
        AppSettings.update(%{site_banner_message: "Hello", site_banner_auth_enabled: true})

      assert %{html: "Hello"} = SiteBanner.for_surface(:auth, "en")
      assert SiteBanner.for_surface(:app, "en") == nil
      assert SiteBanner.for_surface(:public, "en") == nil
    end

    test "is nil when a surface is on but no message is set" do
      {:ok, _settings} = AppSettings.update(%{site_banner_public_enabled: true})

      assert SiteBanner.for_surface(:public, "en") == nil
    end

    test "falls back to the default colour" do
      {:ok, _settings} =
        AppSettings.update(%{site_banner_message: "Hello", site_banner_app_enabled: true})

      assert %{colour: colour} = SiteBanner.for_surface(:app, "en")
      assert colour == SiteBanner.default_colour()
    end
  end

  describe "translations" do
    setup do
      {:ok, _settings} =
        AppSettings.update(%{
          site_banner_message: "Maintenance on Saturday",
          site_banner_auth_enabled: true,
          site_banner_translations: [%{"locale" => "cs", "message" => "Údržba v sobotu"}]
        })

      :ok
    end

    test "a viewer in a translated locale gets the translation" do
      assert %{html: "Údržba v sobotu"} = SiteBanner.for_surface(:auth, "cs")
    end

    test "a locale without a translation falls back to the base message" do
      assert %{html: "Maintenance on Saturday"} = SiteBanner.for_surface(:auth, "de")
      assert %{html: "Maintenance on Saturday"} = SiteBanner.for_surface(:auth, nil)
    end

    test "each language's banner has its own dismissal id" do
      refute SiteBanner.for_surface(:auth, "cs").id == SiteBanner.for_surface(:auth, "de").id
    end

    test "a translation alone does not switch the banner on" do
      {:ok, _settings} = AppSettings.update(%{site_banner_message: nil})

      assert SiteBanner.for_surface(:auth, "cs") == nil
    end
  end

  describe "build/2" do
    test "is nil for a blank or markup-only message" do
      assert SiteBanner.build(nil, nil) == nil
      assert SiteBanner.build("   ", nil) == nil
      assert SiteBanner.build("<script></script>", nil) == nil
    end

    test "sanitises the message again on render" do
      assert %{html: "<span>Hi</span>"} = SiteBanner.build(~s|<span onclick="x()">Hi</span>|, nil)
    end

    test "the id changes when the message or colour changes, and only then" do
      a = SiteBanner.build("Hello", "#112233")

      assert SiteBanner.build("Hello", "#112233").id == a.id
      refute SiteBanner.build("Hello!", "#112233").id == a.id
      refute SiteBanner.build("Hello", "#445566").id == a.id
    end

    test "picks the more legible text colour for the background" do
      assert %{text_colour: "#ffffff"} = SiteBanner.build("Hi", "#111111")
      assert %{text_colour: "#171717"} = SiteBanner.build("Hi", "#fef3c7")
    end
  end

  describe "AppSettings validation" do
    test "the message is sanitised before it is stored" do
      {:ok, settings} =
        AppSettings.update(%{site_banner_message: ~s|<b class="x">Hi</b><script>x()</script>|})

      assert settings.site_banner_message == ~s|<b class="x">Hi</b>x()|
    end

    test "a message that is only stripped markup clears the override" do
      {:ok, settings} = AppSettings.update(%{site_banner_message: "<script></script>"})

      assert settings.site_banner_message == nil
    end

    test "an over-long message is rejected" do
      assert {:error, %Changeset{}} =
               AppSettings.update(%{site_banner_message: String.duplicate("a", 1001)})
    end

    test "translation messages are sanitised, and a blank one is stored as nil" do
      {:ok, settings} =
        AppSettings.update(%{
          site_banner_translations: [
            %{"locale" => "cs", "message" => ~s|<i>Ahoj</i><script>x()</script>|},
            %{"locale" => "de", "message" => "   "}
          ]
        })

      assert [%{locale: "cs", message: "<i>Ahoj</i>x()"}, %{locale: "de", message: nil}] =
               settings.site_banner_translations
    end

    test "translations reject an unsupported or duplicate locale" do
      assert {:error, %Changeset{}} =
               AppSettings.update(%{
                 site_banner_translations: [%{"locale" => "zz", "message" => "x"}]
               })

      assert {:error, %Changeset{}} =
               AppSettings.update(%{
                 site_banner_translations: [
                   %{"locale" => "cs", "message" => "a"},
                   %{"locale" => "cs", "message" => "b"}
                 ]
               })
    end

    test "clearing the translations override leaves an empty list" do
      {:ok, _settings} =
        AppSettings.update(%{site_banner_translations: [%{"locale" => "cs", "message" => "x"}]})

      {:ok, settings} = AppSettings.reset(:site_banner_translations)

      assert settings.site_banner_translations == []
      assert AppSettings.get(:site_banner_translations) == []
    end

    test "the colour is normalised, and a non-colour is rejected" do
      {:ok, settings} = AppSettings.update(%{site_banner_colour: "#AABBCC"})
      assert settings.site_banner_colour == "#aabbcc"

      assert {:error, %Changeset{}} = AppSettings.update(%{site_banner_colour: "red"})
    end
  end
end
