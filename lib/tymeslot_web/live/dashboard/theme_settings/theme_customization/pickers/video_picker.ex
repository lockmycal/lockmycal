defmodule TymeslotWeb.Dashboard.ThemeSettings.ThemeCustomization.Pickers.VideoPicker do
  @moduledoc """
  Function component for selecting or uploading video backgrounds in theme customization.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Media.UploadConstraints
  alias TymeslotWeb.Dashboard.ThemeSettings.AssetUploads
  alias TymeslotWeb.Themes.Shared.Customization.Helpers, as: CustomizationHelpers

  @doc """
  Renders the video picker.
  Expects assigns: option, customization, presets (the group's videos as `{id, preset}`, in order), uploads, myself
  """
  @spec video_picker(map()) :: Phoenix.LiveView.Rendered.t()
  def video_picker(assigns) do
    ~H"""
    <div class="space-y-10">
      <div>
        <p class="text-token-sm font-black text-neutral-600 dark:text-neutral-300 uppercase tracking-widest mb-6">
          {dgettext("dashboard_appearance", "Choose from our collection")}
        </p>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          <%= for {video_id, video} <- @presets do %>
            <button
              type="button"
              class={[
                "group/video relative flex flex-col rounded-token-2xl overflow-hidden border-4 transition-all duration-500",
                if(@customization.settings["background_value"] == video_id,
                  do: "border-primary-400 shadow-2xl shadow-primary-500/20 scale-[1.02]",
                  else:
                    "border-white hover:border-primary-200 hover:shadow-xl hover:shadow-neutral-200/50"
                )
              ]}
              phx-click="theme:set_option"
              phx-value-option={@option}
              phx-value-field="video"
              phx-value-choice={video_id}
              phx-target={@myself}
            >
              <div
                id={"video-hover-#{video_id}"}
                phx-hook="VideoHoverPreview"
                class="aspect-video bg-neutral-900 relative overflow-hidden video-hover-container"
              >
                <img
                  src={"/videos/thumbnails/#{video.thumbnail}"}
                  alt={video.name}
                  class="video-thumbnail w-full h-full object-cover absolute inset-0 z-10 transition-transform duration-700 group-hover/video:scale-110"
                  data-img-fallback
                  data-fallback-selector="[data-fallback-thumbnail]"
                />
                <video
                  src={"/videos/backgrounds/#{video.file}"}
                  class="video-preview w-full h-full object-cover absolute inset-0 opacity-0"
                  muted
                  loop
                  playsinline
                  preload="metadata"
                ></video>
                <div
                  data-fallback-thumbnail
                  class="absolute inset-0 bg-linear-to-br from-neutral-800 to-neutral-900 items-center justify-center hidden z-10"
                >
                  <.icon
                    name="hero-play-circle"
                    class="w-12 h-12 text-neutral-600 dark:text-neutral-300"
                  />
                </div>
                <div class="absolute inset-0 bg-black/0 group-hover/video:bg-black/20 transition-all duration-300 flex items-center justify-center z-20 pointer-events-none">
                  <div class="opacity-0 group-hover/video:opacity-100 scale-150 group-hover/video:scale-100 transition-all duration-500">
                    <div class="w-12 h-12 rounded-token-full bg-white/20 backdrop-blur-md flex items-center justify-center border border-white/30 shadow-2xl">
                      <.icon name="hero-play-solid" class="w-6 h-6 text-white fill-current" />
                    </div>
                  </div>
                </div>
                <%= if @customization.settings["background_value"] == video_id do %>
                  <div class="absolute top-3 right-3 w-8 h-8 bg-primary-500 text-white rounded-token-full flex items-center justify-center shadow-lg z-30">
                    <.icon name="hero-check" class="w-5 h-5" />
                  </div>
                <% end %>
              </div>
              <div class={[
                "p-5 text-left transition-colors",
                if(@customization.settings["background_value"] == video_id,
                  do: "bg-primary-50 dark:bg-primary-900/30",
                  else: "bg-white"
                )
              ]}>
                <p class="text-token-base font-black text-neutral-900 dark:text-neutral-50 tracking-tight">
                  {video.name}
                </p>
                <p class="text-xs text-neutral-500 font-bold uppercase tracking-widest mt-1">
                  {video.description}
                </p>
              </div>
            </button>
          <% end %>
        </div>
      </div>

      <div class="relative py-4">
        <div class="absolute inset-0 flex items-center" aria-hidden="true">
          <div class="w-full border-t-2 border-neutral-300 dark:border-twilight-indigo-800"></div>
        </div>
        <div class="relative flex justify-center text-token-sm font-black uppercase tracking-[0.2em]">
          <span class="px-6 bg-white dark:bg-twilight-indigo-950 text-neutral-400 dark:text-twilight-indigo-300">
            {dgettext("dashboard_appearance", "Or upload your own")}
          </span>
        </div>
      </div>

      <div class="bg-neutral-50 p-8 rounded-token-4xl border-2 border-neutral-100 border-dashed dark:bg-twilight-indigo-900/60 dark:border-twilight-indigo-800">
        <form
          id="theme-background-video-form"
          phx-submit="upload_asset"
          phx-change="upload_asset"
          phx-target={@myself}
          data-auto-upload="true"
          class="flex flex-col items-center gap-6"
        >
          <input type="hidden" name="asset_field" value="background_video_path" />
          <div class="w-full max-w-md">
            <%= if @uploads && @uploads[:background_video_path] do %>
              <div class="relative group/upload">
                <.live_file_input
                  upload={@uploads.background_video_path}
                  class="absolute inset-0 w-full h-full opacity-0 cursor-pointer z-20"
                />
                <div class={[button_classes(:secondary), "w-full"]}>
                  <.icon name="hero-arrow-up-tray" class="w-5 h-5 shrink-0 text-primary-600" />
                  <span>{dgettext("dashboard_appearance", "Select Video")}</span>
                </div>
              </div>
            <% else %>
              <div
                class={[button_classes(:secondary), "w-full opacity-50"]}
                aria-disabled="true"
              >
                {dgettext("dashboard_appearance", "Upload not available")}
              </div>
            <% end %>

            <%= if @uploads && @uploads[:background_video_path] do %>
              <%= for err <- upload_errors(@uploads.background_video_path) do %>
                <div class="mt-4 p-3 bg-red-50 border border-red-100 rounded-token-xl text-red-600 text-xs font-bold flex items-center gap-2">
                  <.icon name="hero-exclamation-circle" class="w-4 h-4" />
                  {AssetUploads.error_message(:video, err)}
                </div>
              <% end %>

              <%= for entry <- @uploads.background_video_path.entries do %>
                <div class="mt-6 p-4 bg-white dark:bg-twilight-indigo-950 rounded-token-2xl border-2 border-neutral-100 dark:border-twilight-indigo-800 shadow-sm">
                  <div class="flex items-center justify-between mb-2">
                    <span class="text-neutral-700 dark:text-neutral-200 font-black text-xs uppercase tracking-wider truncate mr-4">
                      {entry.client_name}
                    </span>
                    <span class="text-primary-600 font-black text-xs">{entry.progress}%</span>
                  </div>
                  <div class="bg-neutral-100 rounded-token-full h-2 overflow-hidden shadow-inner dark:bg-twilight-indigo-800">
                    <div
                      class="bg-linear-to-r from-primary-500 to-secondary-500 h-full transition-all duration-300"
                      style={"width: #{entry.progress}%"}
                    >
                    </div>
                  </div>

                  <%= for err <- upload_errors(@uploads.background_video_path, entry) do %>
                    <div class="mt-2 p-3 bg-red-50 border border-red-100 rounded-token-xl text-red-600 text-xs font-bold flex items-center gap-2">
                      <.icon name="hero-exclamation-circle" class="w-4 h-4" />
                      {AssetUploads.error_message(:video, err)}
                    </div>
                  <% end %>
                </div>
              <% end %>
            <% end %>
            <button type="submit" id="theme-video-submit-btn" class="hidden">
              {dgettext("dashboard_appearance", "Upload Video")}
            </button>
          </div>

          <p class="text-token-2xs font-black text-neutral-400 dark:text-twilight-indigo-300 uppercase tracking-[0.2em]">
            {dgettext("dashboard_appearance", "MP4 or WebM. Max %{size} MB.",
              size: UploadConstraints.max_file_size_mb(:video)
            )}
          </p>
        </form>

        <%= if @customization.settings["background_video_path"] && @customization.settings["background_value"] == "custom" do %>
          <div class="mt-8 p-4 bg-amber-50 border border-amber-100 rounded-token-2xl flex items-center gap-3">
            <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-amber-600 shrink-0" />
            <p class="text-token-sm font-bold text-amber-800 dark:text-amber-200">
              {dgettext(
                "dashboard_appearance",
                "You have a custom video. Selecting a preset will remove it."
              )}
            </p>
          </div>

          <div class="mt-4 aspect-video rounded-token-2xl overflow-hidden border-2 border-neutral-300 dark:border-twilight-indigo-800 shadow-sm bg-neutral-900">
            <video
              src={"/uploads/#{CustomizationHelpers.sanitize_path(@customization.settings["background_video_path"])}"}
              class="w-full h-full object-cover"
              controls
              playsinline
              preload="metadata"
            ></video>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
