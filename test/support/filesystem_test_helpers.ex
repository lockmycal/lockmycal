defmodule Tymeslot.FilesystemTestHelpers do
  @moduledoc """
  Helpers for tests that simulate a filesystem permission failure via
  `File.chmod!/2` on a directory (setting it read-only, e.g. `0o444`, so a
  nested `mkdir`/`File.mkdir_p` underneath it fails with `:eacces`).

  Root bypasses Unix DAC permission checks entirely, so a "read-only"
  directory chmod'd this way is still fully writable when the test suite
  runs as root — e.g. via an explicit `docker exec --user root` override, or
  outside Docker entirely as the root OS user. Tests relying on this
  technique (`Tymeslot.ThemeCustomizationsStorageTest`,
  `Tymeslot.Infrastructure.Logging.FileSinkTest`) would spuriously fail
  there even though the production code path they exercise is correct and
  passes in CI (and in the Docker dev container's own default non-root
  user).
  """

  @doc """
  Returns `true` when the current OS user is root (uid 0), where standard
  Unix file permission bits stop being enforced.
  """
  @spec running_as_root?() :: boolean()
  def running_as_root? do
    case :os.type() do
      {:unix, _flavor} ->
        match?({"0\n", 0}, System.cmd("id", ["-u"], env: []))

      _non_unix ->
        false
    end
  end
end
