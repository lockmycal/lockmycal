defmodule Tymeslot.Security.SiteBannerScrubberTest do
  use ExUnit.Case, async: true

  @moduletag :security
  @moduletag :unit

  alias Tymeslot.Security.SiteBannerScrubber

  describe "sanitize/1" do
    test "keeps inline formatting, links, and class attributes" do
      html =
        ~s|<strong class="font-bold">Heads up:</strong> <a href="https://example.com" class="underline" target="_blank">read more</a><br />|

      assert SiteBannerScrubber.sanitize(html) == html
    end

    test "strips script and style elements" do
      assert SiteBannerScrubber.sanitize("Hi<script>alert(1)</script>") == "Hialert(1)"
      assert SiteBannerScrubber.sanitize("<style>body{display:none}</style>Hi") =~ "Hi"
      refute SiteBannerScrubber.sanitize("<style>body{display:none}</style>Hi") =~ "<style"
    end

    test "strips event handlers and inline styles but keeps the tag" do
      assert SiteBannerScrubber.sanitize(
               ~s|<span onclick="alert(1)" style="color:red" class="x">Hi</span>|
             ) == ~s|<span class="x">Hi</span>|
    end

    test "drops javascript: links" do
      result = SiteBannerScrubber.sanitize(~s|<a href="javascript:alert(1)">x</a>|)

      refute result =~ "javascript"
    end

    test "drops block-level and embedding tags, keeping their text" do
      result =
        SiteBannerScrubber.sanitize(~s|<h1>Title</h1><img src="https://x/y.png"><div>Body</div>|)

      refute result =~ "<h1"
      refute result =~ "<img"
      refute result =~ "<div"
      assert result =~ "Title"
      assert result =~ "Body"
    end

    test "only allows _blank as a link target" do
      refute SiteBannerScrubber.sanitize(~s|<a href="https://x.test" target="_top">x</a>|) =~
               "target"
    end
  end
end
