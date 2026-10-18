defmodule Tymeslot.Profiles.IcsBranding do
  @moduledoc """
  The "Scheduled with <app>" line at the end of the description of the
  calendar files (`.ics`) sent about an organiser's meetings, with a link to
  `:ics_branding_url` (`https://PHX_HOST`, set in `runtime.exs`; unset, the line is
  never added).

  On for everyone by default. An organiser can switch it off on the
  Appearance page (`ProfileSchema.ics_branding_enabled`), but that only
  counts while their plan allows custom branding (`:custom_branding_allowed`,
  the same gate as their own logo, `Tymeslot.Profiles.BrandLogo`): after a
  downgrade the line comes back, and an upgrade hides it again without a new
  choice.
  """

  alias Tymeslot.Profiles
  alias Tymeslot.Profiles.BrandLogo
  alias Tymeslot.Profiles.ProfileSchema

  @doc "The link the line points to, or `nil` when the line is off for the instance."
  @spec url() :: String.t() | nil
  def url do
    case Application.get_env(:tymeslot, :ics_branding_url) do
      url when is_binary(url) and url != "" -> url
      _unset -> nil
    end
  end

  @doc """
  Whether `user_id` keeps the line in the calendar files about their meetings
  (when the instance has a `url/0` at all). An unknown organiser keeps it, as
  everyone does by default.
  """
  @spec show?(pos_integer() | nil) :: boolean()
  def show?(user_id) when is_integer(user_id), do: not hidden?(Profiles.get_profile(user_id))
  def show?(_user_id), do: true

  @doc "Whether the profile's owner may switch the line off."
  @spec allowed?(ProfileSchema.t() | nil) :: boolean()
  def allowed?(profile), do: BrandLogo.allowed?(profile)

  defp hidden?(%ProfileSchema{ics_branding_enabled: false} = profile), do: allowed?(profile)
  defp hidden?(_profile), do: false
end
