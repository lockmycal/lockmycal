defmodule TymeslotWeb.Dashboard.ProfileSettings.AccountSecurityHelpers do
  @moduledoc """
  Small shared helpers for the email/password settings forms — split out so
  `EmailSettingsFormComponent` and `PasswordSettingsFormComponent` don't each
  reimplement the same social-login check or error shaping.
  """
  use Gettext, backend: TymeslotWeb.Gettext

  @email_provider "email"

  @doc """
  True when the user signs in via an OAuth/social provider rather than email
  and password — those accounts can't change an email or password here since
  neither is managed by us.
  """
  @spec social_user?(Ecto.Schema.t() | nil) :: boolean()
  def social_user?(nil), do: false
  def social_user?(user), do: user.provider not in [nil, @email_provider]

  @doc """
  The domain's field errors (`%{field => message}`, from
  `Tymeslot.Auth.request_email_change/4` or `Tymeslot.Auth.update_user_password/5`)
  as the form components take them: a list of messages per field.
  """
  @spec field_errors(%{optional(atom()) => String.t() | [String.t()]}) ::
          %{optional(atom()) => [String.t()]}
  def field_errors(errors) when is_map(errors),
    do: Map.new(errors, fn {field, message} -> {field, List.wrap(message)} end)

  @doc """
  Formats when the password was last changed, for display under the
  "Change Password" action.
  """
  @spec format_last_password_change(Ecto.Schema.t()) :: String.t()
  def format_last_password_change(user) do
    if user.updated_at do
      Calendar.strftime(user.updated_at, "%B %d, %Y")
    else
      dgettext("dashboard_profile", "Never")
    end
  end
end
