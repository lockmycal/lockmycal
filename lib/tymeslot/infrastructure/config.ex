defmodule Tymeslot.Infrastructure.Config do
  @moduledoc """
  Configuration module for the Tymeslot application.
  Provides centralized access to configuration values to reduce duplication
  and ensure consistency across the codebase.
  """

  # Database Modules

  @doc """
  Gets the user queries module configured for the application.
  """
  @spec user_queries_module() :: module()
  def user_queries_module do
    get_module(:user_queries_module, Tymeslot.Auth.UserQueries)
  end

  # Authentication Modules

  # Service Modules

  @doc """
  Gets the email service module configured for the application.
  """
  @spec email_service_module() :: module()
  def email_service_module do
    get_module(:email_service_module, Tymeslot.Emails.EmailService)
  end

  @doc """
  Gets the HTTP client module configured for the application.

  Read at runtime so tests can inject a mock via `with_config/3` or
  `Application.put_env/3`.
  """
  @spec http_client_module() :: module()
  def http_client_module do
    get_module(:http_client_module, Tymeslot.Infrastructure.HTTPClient)
  end

  @doc """
  Gets the Google Calendar API module configured for the application.
  """
  @spec google_calendar_api_module() :: module()
  def google_calendar_api_module do
    get_module(:google_calendar_api_module, Tymeslot.Integrations.Calendar.Google.CalendarAPI)
  end

  @doc """
  Gets the Outlook Calendar API module configured for the application.
  """
  @spec outlook_calendar_api_module() :: module()
  def outlook_calendar_api_module do
    get_module(:outlook_calendar_api_module, Tymeslot.Integrations.Calendar.Outlook.CalendarAPI)
  end

  # Configuration Modules

  @doc """
  Gets the app configuration module configured for the application.
  """
  @spec app_config_module() :: module()
  def app_config_module do
    module = get_module(:app_config_module, Tymeslot.Infrastructure.AppConfig)

    if Code.ensure_loaded?(module) do
      module
    else
      Tymeslot.Infrastructure.AppConfig
    end
  end

  # Configuration Values

  @doc """
  Gets the success redirect path after authentication.
  """
  @spec success_redirect_path() :: String.t()
  def success_redirect_path do
    get_auth_config(:success_redirect_path, "/dashboard")
  end

  # Provider settings (single source of truth)
  @doc """
  Returns the calendar providers configuration map.
  This should be used as the source of truth for which calendar providers are enabled.
  """
  @spec calendar_provider_settings() :: map()
  def calendar_provider_settings do
    Application.get_env(:tymeslot, :calendar_providers, %{})
  end

  @doc """
  Returns the video providers configuration map.
  This should be used as the source of truth for which video providers are enabled.
  """
  @spec video_provider_settings() :: map()
  def video_provider_settings do
    Application.get_env(:tymeslot, :video_providers, %{})
  end

  @doc """
  Checks if new user registration is enabled.
  """
  @spec registration_enabled?() :: boolean()
  def registration_enabled? do
    app_config_module().registration_enabled?()
  end

  @doc """
  Checks if password-based authentication is enabled.
  When disabled, only OAuth login flows are available.
  """
  @spec password_auth_enabled?() :: boolean()
  def password_auth_enabled? do
    app_config_module().password_auth_enabled?()
  end

  @doc """
  Checks if legal agreements should be enforced.
  """
  @spec enforce_legal_agreements?() :: boolean()
  def enforce_legal_agreements? do
    app_config_module().enforce_legal_agreements?()
  end

  @doc """
  Checks if the logo should link to the marketing site.
  """
  @spec logo_links_to_marketing?() :: boolean()
  def logo_links_to_marketing? do
    app_config_module().logo_links_to_marketing?()
  end

  @doc """
  Gets the site home path.
  """
  @spec site_home_path() :: String.t()
  def site_home_path do
    app_config_module().site_home_path()
  end

  @doc """
  Gets the display name of the application, used anywhere the product name is
  shown to users (page metadata, emails, admin UI). Defaults to "Tymeslot";
  self-hosters can override it with the `APP_NAME` environment variable.
  """
  @spec app_name() :: String.t()
  def app_name do
    app_config_module().app_name()
  end

  @doc """
  Gets the URL of this instance's public source code repository.

  The AGPL (section 13) requires offering the source of the running version
  to everyone who uses it over the network, so the dashboard links here. An
  operator running a modified version points `SOURCE_CODE_URL` at their own
  repository. Read at runtime so it can be set on a prebuilt image.
  """
  @spec source_code_url() :: String.t()
  def source_code_url do
    :tymeslot
    |> Application.get_env(:source_code_url, "https://github.com/lockmycal/lockmycal")
    |> String.trim_trailing("/")
  end

  @doc """
  Gets the URL of the issue tracker next to `source_code_url/0`.
  """
  @spec issues_url() :: String.t()
  def issues_url, do: source_code_url() <> "/issues"

  @doc """
  Gets the URL of the public website the top bars link to, from `WEB_HOST`.

  Nil when it is not set, so the link is left out rather than pointing at a
  placeholder. Read at runtime so it can be set on a prebuilt image.
  """
  @spec website_url() :: String.t() | nil
  def website_url do
    case Application.get_env(:tymeslot, :web_host) do
      url when is_binary(url) and url != "" -> String.trim_trailing(url, "/")
      _unset -> nil
    end
  end

  @doc """
  Gets the URL of the bug-report forum category on the public website, linked
  from the dashboard and public page footers. Nil while `WEB_HOST` is not set.
  """
  @spec bug_report_url() :: String.t() | nil
  def bug_report_url do
    if website_url = website_url(), do: website_url <> "/forum/bugs"
  end

  # Private Helpers

  defp get_module(key, default) do
    Application.get_env(:tymeslot, key, default)
  end

  defp get_auth_config(key, default) do
    case Application.get_env(:tymeslot, :auth) do
      nil -> default
      config when is_list(config) -> Keyword.get(config, key, default)
      _non_list -> default
    end
  end
end
