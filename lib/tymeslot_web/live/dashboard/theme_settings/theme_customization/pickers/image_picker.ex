defmodule TymeslotWeb.Dashboard.ThemeSettings.ThemeCustomization.Pickers.ImagePicker do
  @moduledoc """
  Function component for selecting or uploading image backgrounds in theme customization.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Helpers.UploadConstraints
  alias TymeslotWeb.Themes.Shared.Customization.Helpers, as: CustomizationHelpers

  @doc """
  Renders the image picker.
  Expects assigns: customization, presets, uploads, myself
  """
  @spec image_picker(map()) :: Phoenix.LiveView.Rendered.t()
  def image_picker(assigns) do
    ~H"""
    <div class="space-y-10">
      <div>
        <p class="text-token-sm font-black text-neutral-600 dark:text-neutral-300 uppercase tracking-widest mb-6">
          {dgettext("dashboard_appearance", "Choose from our collection")}
        </p>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          <%= for {image_id, image} <- @presets.images do %>
            <button
              type="button"
              class={[
                "group/image relative flex flex-col rounded-token-2xl overflow-hidden border-4 transition-all duration-500",
                if(@customization.background_value == image_id,
                  do: "border-primary-400 scale-[1.02]",
                  else: "border-white dark:border-transparent hover:border-primary-200"
                )
              ]}
              phx-click="theme:select_background"
              phx-value-type="image"
              phx-value-id={image_id}
              phx-target={@myself}
            >
              <div class="aspect-video relative overflow-hidden">
                <img
                  src={"/images/ui/backgrounds/#{image.file}"}
                  alt={image.name}
                  class="w-full h-full object-cover transition-transform duration-700 group-hover/image:scale-110"
                  data-img-fallback
                />
                <div class="absolute inset-0 bg-linear-to-br from-neutral-100 to-neutral-200 items-center justify-center hidden">
                  <.icon name="hero-photo" class="w-12 h-12 text-neutral-300" />
                </div>
                <%= if @customization.background_value == image_id do %>
                  <div class="absolute top-3 right-3 w-8 h-8 bg-primary-500 text-white rounded-token-full flex items-center justify-center shadow-lg z-10">
                    <.icon name="hero-check" class="w-5 h-5" />
                  </div>
                <% end %>
              </div>
              <div class={[
                "p-5 text-left transition-colors",
                if(@customization.background_value == image_id,
                  do: "bg-primary-50 dark:bg-primary-950/40",
                  else: "bg-white dark:bg-twilight-indigo-950"
                )
              ]}>
                <p class="text-token-base font-black text-neutral-900 dark:text-neutral-50 tracking-tight">
                  {image.name}
                </p>
                <p class="text-token-xs text-neutral-500 font-bold uppercase tracking-widest mt-1">
                  {image.description}
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
          id="theme-background-image-form"
          phx-submit="save_background_image"
          phx-change="validate_image"
          phx-target={@myself}
          data-auto-upload="true"
          class="flex flex-col items-center gap-6"
        >
          <div class="w-full max-w-md">
            <%= if @uploads && @uploads[:background_image] do %>
              <div class="relative group/upload">
                <.live_file_input
                  upload={@uploads.background_image}
                  class="absolute inset-0 w-full h-full opacity-0 cursor-pointer z-20"
                />
                <div class={[button_classes(:secondary), "w-full"]}>
                  <.icon name="hero-arrow-up-tray" class="w-5 h-5 shrink-0 text-primary-600" />
                  <span>{dgettext("dashboard_appearance", "Select Image")}</span>
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

            <%= if @uploads && @uploads[:background_image] do %>
              <%= for err <- upload_errors(@uploads.background_image) do %>
                <div class="mt-4 p-3 bg-red-50 border border-red-100 rounded-token-xl text-red-600 text-xs font-bold flex items-center gap-2 dark:bg-red-950/40">
                  <.icon name="hero-exclamation-circle" class="w-4 h-4" />
                  {Phoenix.Naming.humanize(err)}
                </div>
              <% end %>

              <%= for entry <- @uploads.background_image.entries do %>
                <div class="mt-6 p-4 bg-white dark:bg-twilight-indigo-950 rounded-token-2xl border-2 border-neutral-300 dark:border-twilight-indigo-800 shadow-sm">
                  <div class="flex items-center justify-between mb-2">
                    <span class="text-neutral-700 dark:text-neutral-200 font-black text-token-xs uppercase tracking-wider truncate mr-4">
                      {entry.client_name}
                    </span>
                    <span class="text-primary-600 font-black text-token-xs">{entry.progress}%</span>
                  </div>
                  <div class="bg-neutral-100 rounded-token-full h-2 overflow-hidden shadow-inner dark:bg-twilight-indigo-800">
                    <div
                      class="bg-linear-to-r from-primary-500 to-secondary-500 h-full transition-all duration-300"
                      style={"width: #{entry.progress}%"}
                    >
                    </div>
                  </div>

                  <%= for err <- upload_errors(@uploads.background_image, entry) do %>
                    <div class="mt-2 p-3 bg-red-50 border border-red-100 rounded-token-xl text-red-600 text-xs font-bold flex items-center gap-2 dark:bg-red-950/40">
                      <.icon name="hero-exclamation-circle" class="w-4 h-4" />
                      {Phoenix.Naming.humanize(err)}
                    </div>
                  <% end %>
                </div>
              <% end %>
            <% end %>
            <button type="submit" id="theme-image-submit-btn" class="hidden">
              {dgettext("dashboard_appearance", "Upload Image")}
            </button>
          </div>

          <p class="text-token-2xs font-black text-neutral-400 uppercase tracking-[0.2em]">
            {dgettext("dashboard_appearance", "JPG, PNG or WebP. Max %{mb}MB.", mb: max_image_mb())}
          </p>
        </form>

        <%= if @customization.background_image_path && @customization.background_value == "custom" do %>
          <div class="mt-8 p-4 bg-amber-50 border border-amber-100 rounded-token-2xl flex items-center gap-3 dark:bg-amber-950/40">
            <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-amber-600 shrink-0" />
            <p class="text-token-sm font-bold text-amber-800 dark:text-amber-200">
              {dgettext(
                "dashboard_appearance",
                "You have a custom image. Selecting a preset will remove it."
              )}
            </p>
          </div>

          <div class="mt-4 aspect-video rounded-token-2xl overflow-hidden border-2 border-neutral-300 dark:border-twilight-indigo-800 shadow-sm">
            <img
              src={"/uploads/#{CustomizationHelpers.sanitize_path(@customization.background_image_path)}"}
              alt={dgettext("dashboard_appearance", "Your current custom background image")}
              class="w-full h-full object-cover"
            />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp max_image_mb, do: div(UploadConstraints.max_file_size(:image), 1_000_000)
end
