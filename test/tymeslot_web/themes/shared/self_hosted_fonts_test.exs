defmodule TymeslotWeb.Themes.Shared.SelfHostedFontsTest do
  use TymeslotWeb.ConnCase, async: true

  @moduletag :themes
  @moduletag :security

  @css_dir Path.expand("../../../../assets/css", __DIR__)
  @fonts_css Path.join(@css_dir, "base/fonts.css")
  @themes ~w(quill rhythm)
  @font_dirs ~w(/fonts/schibsted-grotesk/ /fonts/ibm-plex-mono/)

  defp font_urls do
    @fonts_css
    |> File.read!()
    |> then(&Regex.scan(~r/url\(['"]?([^'")]+)['"]?\)/, &1, capture: :all_but_first))
    |> List.flatten()
  end

  test "the dashboard and every theme import the self-hosted font faces" do
    app_css = File.read!(Path.join(@css_dir, "app.css"))
    assert app_css =~ ~s(@import "./base/fonts.css";), "app.css does not import fonts.css"

    for theme <- @themes do
      css = File.read!(Path.join(@css_dir, "scheduling/themes/#{theme}/theme.css"))
      assert css =~ ~s(@import "../../../base/fonts.css";), "#{theme} does not import fonts.css"
    end
  end

  test "font faces point only at this instance" do
    urls = font_urls()

    assert length(urls) == 6
    assert Enum.reject(urls, &String.starts_with?(&1, @font_dirs)) == []
  end

  test "the endpoint serves every font file a font face references", %{conn: conn} do
    urls = font_urls()
    assert urls != []

    for url <- urls do
      response = get(conn, url)

      assert response.status == 200, "#{url} returned #{response.status}"
      assert [content_type | _rest] = get_resp_header(response, "content-type")
      assert content_type =~ "font/woff2"
    end
  end
end
