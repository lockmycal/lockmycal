defmodule Tymeslot.Security.SiteBannerScrubber do
  @moduledoc """
  HTML allow-list for the admin-authored site banner message
  (`Tymeslot.SiteBanner`).

  The banner is a single line of inline content, so only inline tags are
  allowed — no headings, lists, tables, or images that would break the bar's
  layout. Unlike `HtmlSanitizeEx.basic_html/1`, every allowed tag also keeps
  its `class` attribute, so an admin can style the message with the app's
  existing utility classes. Inline `style`, event handlers, and non-http(s)/
  mailto link schemes are still stripped, so the message can never carry
  script.

  Deliberately not `Tymeslot.Security.UniversalSanitizer`: its strict mode
  also percent-decodes and strips SQL/path-like patterns, which would corrupt
  link hrefs and ordinary text such as "--".
  """

  use HtmlSanitizeEx

  allow_tag_with_uri_attributes("a", ["href"], ["http", "https", "mailto"])
  allow_tag_with_these_attributes("a", ["title", "class"])
  allow_tag_with_this_attribute_values("a", "target", ["_blank"])

  allow_tag_with_these_attributes("b", ["class"])
  allow_tag_with_these_attributes("strong", ["class"])
  allow_tag_with_these_attributes("i", ["class"])
  allow_tag_with_these_attributes("em", ["class"])
  allow_tag_with_these_attributes("u", ["class"])
  allow_tag_with_these_attributes("span", ["class"])
  allow_tag_with_these_attributes("br", ["class"])
  allow_tag_with_these_attributes("code", ["class"])
  allow_tag_with_these_attributes("small", ["class"])
end
