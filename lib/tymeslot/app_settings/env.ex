defmodule Tymeslot.AppSettings.Env do
  @moduledoc """
  Projection layer between admin-editable settings and the Application env.

  Owns the purely mechanical side of `Tymeslot.AppSettings`: the built-in
  defaults, the map from each setting key to its location in the Application
  env (`config_path/1`), the read/write/delete of those locations, and the
  per-BEAM baseline snapshot used to restore the original config value when an
  override is cleared.

  This module knows nothing about policy — no lockout guard, no auth or
  payment checks. It is the single place that touches `Application.*_env` and
  `:persistent_term` for settings, so the context can stay focused on
  orchestration and rules.

  ## Baseline snapshot

  The baseline is the config-layer value in effect before any DB override.
  It is captured once per BEAM lifetime in `:persistent_term` (purpose-built
  for read-heavy, write-rare configuration data) so a cleared override can
  restore the original config value.
  """

  alias Tymeslot.AppSettings.AppSettingsSchema
  alias Tymeslot.Infrastructure.Config

  # Sentinel marking "no baseline captured yet" — distinct from a captured
  # `:error` (the key had no config value to snapshot).
  @baseline_sentinel :__app_settings_baseline_not_captured__

  @doc """
  Built-in default for a setting, used when neither the DB nor the
  application config provides a value.
  """
  @spec default_for(atom()) :: term()
  def default_for(:registration_enabled), do: true
  def default_for(:password_auth_enabled), do: true
  def default_for(:google_auth_enabled), do: false
  def default_for(:github_auth_enabled), do: false
  def default_for(:microsoft_auth_enabled), do: false
  def default_for(:oauth_auth_enabled), do: false
  def default_for(:recaptcha_signup_provider), do: :off
  def default_for(:recaptcha_booking_provider), do: :off
  def default_for(:recaptcha_signup_min_score), do: 0.3
  def default_for(:recaptcha_booking_min_score), do: 0.3
  def default_for(:admin_alerts_enabled), do: false
  def default_for(:admin_alert_email), do: nil
  def default_for(:meeting_payments_enabled), do: false
  def default_for(:booking_analytics_enabled), do: false
  # Matches TymeslotWeb.Helpers.UploadConstraints' pre-existing hardcoded
  # image/video limits — the built-in default when neither a DB override nor
  # a config value is set.
  def default_for(:max_image_upload_size_mb), do: 20
  def default_for(:max_video_upload_size_mb), do: 100

  # Booker attachments: every supported type but SVG, and limits that keep
  # the organiser's email (which carries the files) deliverable.
  def default_for(:booking_attachment_types),
    do: AppSettingsSchema.default_booking_attachment_types()

  def default_for(:max_booking_attachment_size_mb), do: 10
  def default_for(:max_booking_attachments), do: 3

  # Security audit log: IP addresses and user agents are personal data, so
  # events are kept for a limited time (GDPR storage limitation).
  def default_for(:audit_log_retention_days), do: 90
  # No overrides: every event category uses its own default
  # (`Tymeslot.Security.AuditLog.Catalog`).
  def default_for(:audit_log_events), do: %{}

  # Email branding. A nil accent and logo mean "use what ships"; the brand
  # name has a real default because it is substituted into user-facing copy
  # and every caller would otherwise repeat the same fallback string. Reads
  # through Config.app_name/0 (APP_NAME env var) rather than hardcoding
  # "Tymeslot" so a self-hosted, rebranded instance defaults consistently.
  def default_for(:email_brand_accent), do: nil
  def default_for(:email_brand_name), do: Config.app_name()
  def default_for(:email_logo_path), do: nil

  # Per-surface locale fallbacks. Nil means "no override": `Tymeslot.Locales`
  # then falls back to the instance-wide `:locales` default, which is where the
  # value came from before these settings existed.
  def default_for(:admin_default_locale), do: nil
  def default_for(:booking_default_locale), do: nil

  # Site banner: off on every surface until an admin opts in. A nil colour
  # means "use the stock brand accent", resolved by `Tymeslot.SiteBanner`.
  def default_for(:site_banner_app_enabled), do: false
  def default_for(:site_banner_auth_enabled), do: false
  def default_for(:site_banner_public_enabled), do: false
  def default_for(:site_banner_message), do: nil
  def default_for(:site_banner_colour), do: nil
  def default_for(:site_banner_translations), do: []

  @doc """
  Reads the effective config-layer value for `key`, handling both top-level
  and nested keys and falling back to the built-in default.
  """
  @spec read(atom()) :: term()
  def read(key) do
    case config_path(key) do
      [top] ->
        Application.get_env(:tymeslot, top, default_for(key))

      [parent, child] ->
        :tymeslot
        |> Application.get_env(parent, [])
        |> Keyword.get(child, default_for(key))
    end
  end

  @doc """
  Returns the captured baseline for `key` as `{:ok, value}` (a config value was
  snapshotted), `:error` (no config value existed at snapshot time), or
  `:not_captured` (no snapshot has been taken yet).
  """
  @spec baseline_value(atom()) :: {:ok, term()} | :error | :not_captured
  def baseline_value(key) do
    case :persistent_term.get(baseline_term(key), @baseline_sentinel) do
      @baseline_sentinel -> :not_captured
      captured -> captured
    end
  end

  @doc """
  Snapshots the current config-layer value for every editable key. The
  baseline is only captured once per BEAM lifetime; subsequent calls are
  no-ops for already-captured keys.
  """
  @spec capture_baselines() :: :ok
  def capture_baselines do
    Enum.each(keys(), &capture_baseline/1)
  end

  @doc """
  Applies the DB overrides in `settings` over the baseline: a non-nil value is
  written to the Application env, a nil clears the override and restores the
  snapshotted baseline. Used at boot by `AppSettings.load!/0`.
  """
  @spec apply_overrides(map()) :: :ok
  def apply_overrides(settings) do
    Enum.each(keys(), fn key -> apply_override(key, Map.get(settings, key)) end)
  end

  @doc """
  Applies all setting overrides from `settings` to the Application env in a
  way that avoids the TOCTOU window for nested keys. Keys that share a parent
  keyword list (e.g. :social_auth, :recaptcha) are merged together before
  being written, so each parent key receives exactly one `Application.put_env`
  call rather than a sequence of read-modify-write operations that concurrent
  updates could interleave.
  """
  @spec flush_overrides(map()) :: :ok
  def flush_overrides(settings) do
    {top_level, nested_by_parent} = partition_keys_by_layout()

    Enum.each(top_level, &apply_override(&1, Map.get(settings, &1)))

    Enum.each(nested_by_parent, fn {parent, keys} ->
      flush_nested_parent(parent, keys, settings)
    end)
  end

  defp keys, do: AppSettingsSchema.editable_fields()

  defp capture_baseline(key) do
    term = baseline_term(key)

    case :persistent_term.get(term, @baseline_sentinel) do
      @baseline_sentinel -> :persistent_term.put(term, fetch_config(key))
      _existing -> :ok
    end
  end

  defp apply_override(key, nil), do: restore_baseline(key)
  defp apply_override(key, value), do: write(key, value)

  defp restore_baseline(key) do
    case baseline_value(key) do
      {:ok, value} -> write(key, value)
      :error -> delete(key)
      :not_captured -> :ok
    end
  end

  defp partition_keys_by_layout do
    Enum.reduce(keys(), {[], %{}}, fn key, {top_acc, nested_acc} ->
      case config_path(key) do
        [_top] -> {[key | top_acc], nested_acc}
        [parent, _child] -> {top_acc, Map.update(nested_acc, parent, [key], &[key | &1])}
      end
    end)
  end

  defp flush_nested_parent(parent, keys, settings) do
    current = Application.get_env(:tymeslot, parent, [])
    merged = Enum.reduce(keys, current, &merge_nested_child(&2, &1, settings))
    Application.put_env(:tymeslot, parent, merged)
  end

  defp merge_nested_child(kw, key, settings) do
    [_parent, child] = config_path(key)

    case Map.get(settings, key) do
      nil -> restore_nested_child_baseline(kw, key, child)
      value -> Keyword.put(kw, child, value)
    end
  end

  defp restore_nested_child_baseline(kw, key, child) do
    case baseline_value(key) do
      {:ok, value} -> Keyword.put(kw, child, value)
      :error -> Keyword.delete(kw, child)
      :not_captured -> kw
    end
  end

  # Projection from setting key to its location in the Application env.
  # Single-atom paths live at the top level; two-atom paths live nested
  # under a parent keyword list (e.g. `:social_auth` / `:recaptcha`).
  defp config_path(:google_auth_enabled), do: [:social_auth, :google_enabled]
  defp config_path(:github_auth_enabled), do: [:social_auth, :github_enabled]
  defp config_path(:microsoft_auth_enabled), do: [:social_auth, :microsoft_enabled]
  defp config_path(:oauth_auth_enabled), do: [:social_auth, :oauth_enabled]
  defp config_path(:recaptcha_signup_provider), do: [:recaptcha, :signup_provider]
  defp config_path(:recaptcha_booking_provider), do: [:recaptcha, :booking_provider]
  defp config_path(:recaptcha_signup_min_score), do: [:recaptcha, :signup_min_score]
  defp config_path(:recaptcha_booking_min_score), do: [:recaptcha, :booking_min_score]
  defp config_path(:max_image_upload_size_mb), do: [:uploads, :max_image_size_mb]
  defp config_path(:max_video_upload_size_mb), do: [:uploads, :max_video_size_mb]
  defp config_path(:booking_attachment_types), do: [:uploads, :booking_attachment_types]

  defp config_path(:max_booking_attachment_size_mb),
    do: [:uploads, :max_booking_attachment_size_mb]

  defp config_path(:max_booking_attachments), do: [:uploads, :max_booking_attachments]
  defp config_path(key), do: [key]

  defp fetch_config(key) do
    case config_path(key) do
      [top] ->
        Application.fetch_env(:tymeslot, top)

      [parent, child] ->
        case Application.fetch_env(:tymeslot, parent) do
          {:ok, kw} when is_list(kw) -> Keyword.fetch(kw, child)
          _other -> :error
        end
    end
  end

  defp write(key, value) do
    case config_path(key) do
      [top] ->
        Application.put_env(:tymeslot, top, value)

      [parent, child] ->
        kw = Application.get_env(:tymeslot, parent, [])
        Application.put_env(:tymeslot, parent, Keyword.put(kw, child, value))
    end
  end

  defp delete(key) do
    case config_path(key) do
      [top] ->
        Application.delete_env(:tymeslot, top)

      [parent, child] ->
        kw = Application.get_env(:tymeslot, parent, [])
        Application.put_env(:tymeslot, parent, Keyword.delete(kw, child))
    end
  end

  defp baseline_term(key), do: {__MODULE__, :baseline, key}
end
