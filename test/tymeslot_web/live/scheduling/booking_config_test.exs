defmodule TymeslotWeb.Live.Scheduling.BookingConfigTest do
  use ExUnit.Case, async: true

  @moduletag :scheduling
  @moduletag :unit

  alias Tymeslot.Security.InputProcessor
  alias TymeslotWeb.Live.Scheduling.BookingConfig

  describe "booking_field_spec/0" do
    test "accepts valid booking params" do
      params = %{
        "name" => "Alice",
        "email" => "alice@example.com",
        "phone" => "+1 555 200 3000",
        "message" => "Hello, looking forward to it"
      }

      assert {:ok, sanitized} =
               InputProcessor.validate_form(params, BookingConfig.booking_field_spec())

      assert sanitized["name"] == "Alice"
      assert sanitized["email"] == "alice@example.com"
    end

    test "rejects missing required fields" do
      params = %{"name" => "", "email" => "", "phone" => "", "message" => ""}

      assert {:error, errors} =
               InputProcessor.validate_form(params, BookingConfig.booking_field_spec())

      assert Map.has_key?(errors, :name)
      assert Map.has_key?(errors, :email)
      assert Map.has_key?(errors, :phone)
      assert Map.has_key?(errors, :message)
    end

    test "message field is required" do
      params = %{
        "name" => "Alice",
        "email" => "alice@example.com",
        "phone" => "+1 555 200 3000",
        "message" => ""
      }

      assert {:error, errors} =
               InputProcessor.validate_form(params, BookingConfig.booking_field_spec())

      assert Map.has_key?(errors, :message)
    end

    # Regression: issue #83. The shipped TLD snapshot was missing .homes, so a
    # visitor with that address could not book. The snapshot is synced from IANA
    # now (mix tymeslot.sync_tlds).
    test "accepts an email on a TLD delegated after the list was first written" do
      email = "owner@eastvalleyliving.homes"

      params = %{
        "name" => "Test Attendee",
        "email" => email,
        "phone" => "+1 555 130 1000",
        "message" => "Looking forward to it"
      }

      assert {:ok, sanitized} =
               InputProcessor.validate_form(params, BookingConfig.booking_field_spec())

      assert sanitized["email"] == email
    end
  end
end
