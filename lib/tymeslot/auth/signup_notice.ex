defmodule Tymeslot.Auth.SignupNotice do
  @moduledoc """
  Behaviour for an extra informational notice on the signup form
  (`TymeslotWeb.Registration.SignupComponent`), rendered below the password
  fields. Purely informational — it must not add form fields or block
  registration.

  Same rationale as `Tymeslot.Dashboard.OverviewWidget`: Core defines the
  contract, an external application implements it and registers itself.

  ## Usage

      config :tymeslot, :signup_extra_notices, [MyApp.Auth.PlanNotice]

  An empty or unset list (the default) leaves the form exactly as it is.
  `render/0` returns the notice markup, or `nil` to show nothing.
  """

  @doc "The notice's identifier; used as its DOM id suffix, so keep it unique."
  @callback id() :: atom()

  @doc "Renders the notice, or `nil` to skip it."
  @callback render() :: Phoenix.LiveView.Rendered.t() | nil

  @doc "Reads the registered notice modules from config."
  @spec registered() :: [module()]
  def registered do
    Application.get_env(:tymeslot, :signup_extra_notices, [])
  end
end
