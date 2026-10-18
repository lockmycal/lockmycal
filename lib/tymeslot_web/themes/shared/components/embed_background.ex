defmodule TymeslotWeb.Themes.Shared.Components.EmbedBackground do
  @moduledoc """
  Replaces the theme's background inside the embedded booking widget with the
  one the embed code asks for (`?background=`, `data-background`): a colour,
  or `transparent` so the embedding page shows through.

  Rendered by both theme wrappers, so its selectors cover both themes'
  background layers: the document, Quill's `.main-gradient`, Rhythm's
  `.video-background-theme` overlay and the background image/video
  containers, which are hidden, as is the scrim Quill lays over a background
  image (`.main-gradient::after`), which would darken the chosen colour. The value has passed
  `TymeslotWeb.Themes.Core.Context.valid_embed_background?/1` (`transparent`
  or `#rrggbb`), so it is safe to write into the stylesheet.
  """
  use Phoenix.Component

  alias TymeslotWeb.Themes.Core.Context

  attr :value, :string, default: nil

  @spec embed_background(map()) :: Phoenix.LiveView.Rendered.t()
  def embed_background(assigns) do
    assigns = assign(assigns, :valid?, Context.valid_embed_background?(assigns.value))

    ~H"""
    <%!-- `color-scheme: normal` keeps a transparent page transparent: a frame
         whose colour scheme differs from the embedding page's is painted on an
         opaque canvas. --%>
    <style :if={@valid?} type="text/css">
      html, body { background: <%= @value %> !important; color-scheme: normal; }
      .main-gradient, .video-background-theme { background: <%= @value %> !important; }
      .video-background, .video-background-container { display: none !important; }
      .main-gradient::after { display: none !important; }
    </style>
    """
  end
end
