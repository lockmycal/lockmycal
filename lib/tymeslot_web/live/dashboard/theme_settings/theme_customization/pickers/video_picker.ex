defmodule TymeslotWeb.Dashboard.ThemeSettings.ThemeCustomization.Pickers.VideoPicker do
  @moduledoc """
  Function component for selecting or uploading video backgrounds in theme customization.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Helpers.UploadConstraints
  alias TymeslotWeb.Themes.Shared.Customization.Helpers, as: CustomizationHelpers

  @doc """
  Renders the video picker.
  Expects assigns: customization, presets, uploads, myself
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
          <%= for {video_id, video} <- @presets.videos do %>
            <button
              type="button"
              class={[
                "group/video relative flex flex-col rounded-token-2xl overflow-hidden border-4 transition-all duration-500",
                if(@customization.background_value == video_id,
                  do: "border-primary-400 scale-[1.02]",
                  else: "border-white dark:border-transparent hover:border-primary-200"
                )
              ]}
              phx-click="theme:select_background"
              phx-value-type="video"
              phx-value-id={video_id}
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
                  <svg
                    class="w-12 h-12 text-neutral-600 dark:text-neutral-300"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"
                    />
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                </div>
                <div class="absolute inset-0 bg-black/0 group-hover/video:bg-black/20 transition-all duration-300 flex items-center justify-center z-20 pointer-events-none">
                  <div class="opacity-0 group-hover/video:opacity-100 scale-150 group-hover/video:scale-100 transition-all duration-500">
                    <div class="w-12 h-12 rounded-full bg-white/20 backdrop-blur-md flex items-center justify-center border border-white/30 shadow-2xl">
                      <svg class="w-6 h-6 text-white fill-current" viewBox="0 0 24 24">
                        <path d="M8 5v14l11-7z" />
                      </svg>
                    </div>
                  </div>
                </div>
                <%= if @customization.background_value == video_id do %>
                  <div class="absolute top-3 right-3 w-8 h-8 bg-primary-500 text-white rounded-full flex items-center justify-center shadow-lg z-30">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="3"
                        d="M5 13l4 4L19 7"
                      />
                    </svg>
                  </div>
                <% end %>
              </div>
              <div class={[
                "p-5 text-left transition-colors",
                if(@customization.background_value == video_id,
                  do: "bg-primary-50 dark:bg-primary-950/40",
                  else: "bg-white dark:bg-twilight-indigo-950"
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

      <div class="bg-neutral-50 dark:bg-twilight-indigo-900/60 p-8 rounded-[2rem] border-2 border-neutral-300 dark:border-twilight-indigo-700 border-dashed">
        <form
          id="theme-background-video-form"
          phx-submit="save_background_video"
          phx-change="validate_video"
          phx-target={@myself}
          data-auto-upload="true"
          class="flex flex-col items-center gap-6"
        >
          <div class="w-full max-w-md">
            <%= if @uploads && @uploads[:background_video] do %>
              <div class="relative group/upload">
                <.live_file_input
                  upload={@uploads.background_video}
                  class="absolute inset-0 w-full h-full opacity-0 cursor-pointer z-20"
                />
                <div class="btn btn-secondary w-full py-4 flex items-center justify-center gap-3">
                  <svg
                    class="w-5 h-5 text-primary-600"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2.5"
                      d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"
                    />
                  </svg>
                  <span>{dgettext("dashboard_appearance", "Select Video")}</span>
                </div>
              </div>
            <% else %>
              <div class="btn btn-secondary w-full opacity-50 cursor-not-allowed py-4">
                {dgettext("dashboard_appearance", "Upload not available")}
              </div>
            <% end %>

            <%= if @uploads && @uploads[:background_video] do %>
              <%= for err <- upload_errors(@uploads.background_video) do %>
                <div class="mt-4 p-3 bg-red-50 border border-red-100 rounded-token-xl text-red-600 text-xs font-bold flex items-center gap-2">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2.5"
                      d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  {Phoenix.Naming.humanize(err)}
                </div>
              <% end %>

              <%= for entry <- @uploads.background_video.entries do %>
                <div class="mt-6 p-4 bg-white dark:bg-twilight-indigo-950 rounded-token-2xl border-2 border-neutral-300 dark:border-twilight-indigo-700 shadow-sm">
                  <div class="flex items-center justify-between mb-2">
                    <span class="text-neutral-700 dark:text-neutral-200 font-black text-xs uppercase tracking-wider truncate mr-4">
                      {entry.client_name}
                    </span>
                    <span class="text-primary-600 font-black text-xs">{entry.progress}%</span>
                  </div>
                  <div class="bg-neutral-100 dark:bg-twilight-indigo-800 rounded-full h-2 overflow-hidden shadow-inner">
                    <div
                      class="bg-linear-to-r from-primary-500 to-secondary-500 h-full transition-all duration-300"
                      style={"width: #{entry.progress}%"}
                    >
                    </div>
                  </div>

                  <%= for err <- upload_errors(@uploads.background_video, entry) do %>
                    <div class="mt-2 p-3 bg-red-50 border border-red-100 rounded-token-xl text-red-600 text-xs font-bold flex items-center gap-2">
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2.5"
                          d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                        />
                      </svg>
                      {Phoenix.Naming.humanize(err)}
                    </div>
                  <% end %>
                </div>
              <% end %>
            <% end %>
            <button type="submit" id="theme-video-submit-btn" class="hidden">
              {dgettext("dashboard_appearance", "Upload Video")}
            </button>
          </div>

          <p class="text-token-2xs font-black text-neutral-400 uppercase tracking-[0.2em]">
            {dgettext("dashboard_appearance", "MP4, WebM or MOV. Max %{mb}MB.", mb: max_video_mb())}
          </p>
        </form>

        <%= if @customization.background_video_path && @customization.background_value == "custom" do %>
          <div class="mt-8 p-4 bg-amber-50 border border-amber-100 rounded-token-2xl flex items-center gap-3">
            <svg
              class="w-5 h-5 text-amber-600 shrink-0"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2.5"
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"
              />
            </svg>
            <p class="text-token-sm font-bold text-amber-800">
              {dgettext(
                "dashboard_appearance",
                "You have a custom video. Selecting a preset will remove it."
              )}
            </p>
          </div>

          <div class="mt-4 aspect-video rounded-token-2xl overflow-hidden border-2 border-neutral-300 dark:border-twilight-indigo-700 shadow-sm bg-neutral-900">
            <video
              src={"/uploads/#{CustomizationHelpers.sanitize_path(@customization.background_video_path)}"}
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

  defp max_video_mb, do: div(UploadConstraints.max_file_size(:video), 1_000_000)
end
