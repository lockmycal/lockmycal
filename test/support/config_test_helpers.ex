defmodule Tymeslot.ConfigTestHelpers do
  @moduledoc """
  Helpers for temporarily modifying application configuration in tests.

  This module provides utilities to change application config for the duration
  of a test, with automatic restoration of original values on test exit.

  ## Why Use This?

  Instead of manually saving and restoring config (which is error-prone and verbose):

      test "with feature disabled" do
        previous = Application.get_env(:tymeslot, :feature_flag)
        Application.put_env(:tymeslot, :feature_flag, false)

        on_exit(fn ->
          Application.put_env(:tymeslot, :feature_flag, previous)
        end)

        # test logic
      end

  You can write:

      test "with feature disabled" do
        with_config(:tymeslot, feature_flag: false)
        # test logic - cleanup is automatic
      end

  ## Common Use Cases

  ### Testing with Feature Flags

      test "shows advanced features when enabled" do
        with_config(:tymeslot, advanced_features: true)
        # test with feature enabled
      end

  ### Testing Payment/Stripe Configuration

      test "validates webhook signature in production mode" do
        with_config(:tymeslot, [
          skip_webhook_verification: false,
          stripe_provider: Tymeslot.Payments.Stripe,
          stripe_webhook_secret: "whsec_test_secret"
        ])
        # test with real verification
      end

  ### Testing External Service Configuration

      test "uses custom API endpoint" do
        with_config(:tymeslot, [
          mirotalk_api_url: "https://custom.example.com",
          mirotalk_api_key: "test_key"
        ])
        # test with custom endpoint
      end

  ### In Setup Blocks

      setup do
        setup_config(:tymeslot, test_mode: true)
      end

  ## Important Notes

  - Changes are automatically reverted when the test exits (success or failure)
  - Original config values are preserved even if they were `nil` or not set
  - Works with both atom keys and nested config paths
  - Not safe in async tests (application env is global). Use `async: false`.
  """

  alias ExUnit.Callbacks

  @doc """
  Temporarily sets one or more config values for the current test.

  The config is automatically restored to its original value(s) when the test exits.

  ## Parameters

  - `app` - The application atom (e.g., `:tymeslot`, `:tymeslot_saas`)
  - `config` - Either a keyword list of config changes, or a single `{key, value}` pair

  ## Examples

      # Single config value
      with_config(:tymeslot, :feature_flag, false)

      # Multiple config values
      with_config(:tymeslot, [
        skip_webhook_verification: false,
        stripe_webhook_secret: "whsec_test",
        test_mode: true
      ])

      # Can be called multiple times in a test
      with_config(:tymeslot, logo_links_to_marketing: false)
      with_config(:tymeslot_saas, subscription_required: true)
  """
  @spec with_config(atom(), keyword()) :: :ok
  def with_config(app, config_list) when is_atom(app) and is_list(config_list) do
    keys = Enum.map(config_list, fn {key, _value} -> key end)
    # `on_exit` callbacks run in ExUnit's own OnExitHandler process, not this
    # test process — capture the owner explicitly rather than calling self()
    # again down in the on_exit closure below.
    owner = self()

    # Guard against two test processes mutating the same global config key at
    # the same time (e.g. an async: true test racing an async: false one).
    # `Application.put_env/3` is node-wide, so an overlap here is exactly the
    # class of flake this module warns about in its moduledoc — fail loudly
    # and locally instead of letting an unrelated assertion flake later.
    Enum.each(keys, &acquire_lock(app, &1, owner))

    # Save original values for all keys we're about to change
    original_values =
      Enum.map(config_list, fn {key, _value} ->
        {key, Application.fetch_env(app, key)}
      end)

    # Apply new config values
    Enum.each(config_list, fn {key, value} ->
      Application.put_env(app, key, value)
    end)

    # Register cleanup to restore original values
    Callbacks.on_exit(fn ->
      restore_originals(app, original_values)
      Enum.each(keys, &release_lock(app, &1, owner))
    end)
  end

  defp restore_originals(app, original_values) do
    Enum.each(original_values, fn {key, original} ->
      case original do
        :error ->
          # If the key wasn't set before, delete it
          Application.delete_env(app, key)

        {:ok, value} ->
          # Restore the original value (including explicit nil)
          Application.put_env(app, key, value)
      end
    end)
  end

  @spec with_config(atom(), atom(), any()) :: :ok
  def with_config(app, key, value) when is_atom(app) and is_atom(key) do
    with_config(app, [{key, value}])
  end

  @doc """
  Setup helper for use in setup blocks.

  This is equivalent to `with_config/2` but returns `:ok` for convenient use
  in setup blocks.

  ## Examples

      setup do
        setup_config(:tymeslot, [
          logo_links_to_marketing: false,
          test_mode: true
        ])
      end

      setup do
        setup_config(:tymeslot, :feature_flag, true)
      end
  """
  @spec setup_config(atom(), keyword()) :: :ok
  def setup_config(app, config_list) when is_list(config_list) do
    with_config(app, config_list)
    :ok
  end

  @spec setup_config(atom(), atom(), any()) :: :ok
  def setup_config(app, key, value) when is_atom(key) do
    with_config(app, key, value)
    :ok
  end

  # ETS-backed lock so overlapping `with_config`/`setup_config` calls for the
  # same {app, key} from two different processes fail immediately instead of
  # silently racing. Ref-counted per-owner so the same test process can still
  # call `with_config` multiple times for the same key (documented above), as
  # several tests do.
  @lock_table __MODULE__.Locks

  defp acquire_lock(app, key, owner) do
    case :ets.lookup(@lock_table, {app, key}) do
      [{_entry_key, pid, _count}] when pid != owner ->
        raise """
        with_config/setup_config called for #{inspect(app)}.#{inspect(key)} while \
        another test process (#{inspect(pid)}) still holds it. Application.put_env/3 \
        is node-wide, so this means two tests are mutating the same global config \
        key at the same time — declare `async: false` on the offending test module, \
        or scope the override differently.
        """

      [{_entry_key, pid, count}] ->
        :ets.insert(@lock_table, {{app, key}, pid, count + 1})

      [] ->
        :ets.insert(@lock_table, {{app, key}, owner, 1})
    end
  end

  defp release_lock(app, key, owner) do
    case :ets.lookup(@lock_table, {app, key}) do
      [{_entry_key, ^owner, 1}] ->
        :ets.delete(@lock_table, {app, key})

      [{_entry_key, ^owner, count}] ->
        :ets.insert(@lock_table, {{app, key}, owner, count - 1})

      _no_entry_or_foreign_owner ->
        :ok
    end
  end

  @doc false
  # Called once from `test/test_helper.exs`, in the long-lived process that
  # runs the whole `mix test` invocation. ETS tables are torn down when their
  # owner process exits, so this must NOT be created lazily from inside a
  # test process — that process dies at the end of its own test, taking the
  # table (and every other test's lock) down with it.
  @spec ensure_lock_table() :: :ok
  def ensure_lock_table do
    case :ets.whereis(@lock_table) do
      :undefined -> :ets.new(@lock_table, [:set, :public, :named_table])
      _existing_table -> :ok
    end

    :ok
  end
end
