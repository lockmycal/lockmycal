defmodule Tymeslot.Integrations.Video.ProviderOfferableTest do
  # async: false — mutates the global :zoom_oauth app env and ZOOM_CLIENT_ID.
  use ExUnit.Case, async: false
  @moduletag :integrations

  alias Tymeslot.Integrations.Video.ProviderConfig

  setup do
    original_config = Application.get_env(:tymeslot, :zoom_oauth)
    original_env = System.get_env("ZOOM_CLIENT_ID")

    Application.delete_env(:tymeslot, :zoom_oauth)
    System.delete_env("ZOOM_CLIENT_ID")

    on_exit(fn ->
      if original_config,
        do: Application.put_env(:tymeslot, :zoom_oauth, original_config),
        else: Application.delete_env(:tymeslot, :zoom_oauth)

      if original_env,
        do: System.put_env("ZOOM_CLIENT_ID", original_env),
        else: System.delete_env("ZOOM_CLIENT_ID")
    end)
  end

  describe "offerable?/1" do
    test "hides Zoom when no client ID is configured" do
      refute ProviderConfig.offerable?(:zoom)
    end

    test "hides Zoom when ZOOM_CLIENT_ID is blank" do
      System.put_env("ZOOM_CLIENT_ID", "")

      refute ProviderConfig.offerable?(:zoom)
    end

    test "offers Zoom when ZOOM_CLIENT_ID is set" do
      System.put_env("ZOOM_CLIENT_ID", "zoom-client-id")

      assert ProviderConfig.offerable?(:zoom)
    end

    test "offers Zoom when the client ID comes from app config" do
      Application.put_env(:tymeslot, :zoom_oauth, client_id: "zoom-client-id")

      assert ProviderConfig.offerable?(:zoom)
    end

    test "keeps the Zoom provider itself valid for existing integrations" do
      assert ProviderConfig.valid_provider?(:zoom)
    end

    test "offers every other provider regardless of Zoom credentials" do
      for provider <- ProviderConfig.all_providers() -- [:zoom] do
        assert ProviderConfig.offerable?(provider), "expected #{provider} to be offerable"
      end
    end
  end
end
