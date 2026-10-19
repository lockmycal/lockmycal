defmodule TymeslotWeb.E2E.LoginTest do
  use TymeslotWeb.BrowserCase, async: false

  @moduletag :e2e
  @moduletag :auth

  feature "user can log in with valid credentials", %{session: session} do
    user = create_onboarded_user()

    session
    |> visit("/auth/login")
    |> wait_for_live()
    |> fill_in(text_field("email"), with: user.email)
    |> fill_in(css("#password-input"), with: default_password())
    |> click(css("button[type='submit']"))
    |> wait_for_dashboard()
  end

  feature "login with invalid credentials shows error", %{session: session} do
    user = create_onboarded_user()

    session
    |> visit("/auth/login")
    |> wait_for_live()
    |> fill_in(text_field("email"), with: user.email)
    |> fill_in(css("#password-input"), with: "WrongPassword99!")
    |> click(css("button[type='submit']"))
    |> assert_has(css("[role='alert']", text: "Invalid email or password"))
  end

  # The login form leaves validation to the app (`novalidate`): an empty
  # submit reaches the server and comes back with the app's own message,
  # not the browser's bubble.
  feature "an empty login is answered by the app's own message", %{session: session} do
    session
    |> visit("/auth/login")
    |> wait_for_live()
    |> refute_has(css("body", text: "Please enter your email and password."))
    |> click(css("button[type='submit']"))
    # LockMyCal shows the message in its own error flash.
    |> assert_has(css("#app-flash-group-error", text: "Please enter your email and password."))

    assert current_path(session) == "/auth/login"
  end

  feature "login page fits the narrowest supported viewport", %{session: session} do
    session
    |> resize_to_mobile()
    |> visit("/auth/login")
    |> wait_for_live()
    |> assert_has(css("#password-input"))
    |> assert_no_horizontal_overflow("login page at 320px")
  end
end
