defmodule TymeslotWeb.Dashboard.Admin.AuditActions do
  @moduledoc """
  State and events of the admin Audit tab, kept out of
  `TymeslotWeb.Dashboard.Admin.HubComponent`, which only delegates here.

  Paging is numbered: `audit_page` (1-based) and `audit_per_page` (one of
  `Tymeslot.Pagination.OffsetPage.page_sizes/0`). A new filter or page size goes back to page 1.

  The event filter holds either a concrete event type or
  `"category:<key>"` for a whole `Tymeslot.Security.AuditLog.Catalog`
  category. The date range is whole UTC days, both ends inclusive.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Tymeslot.AppSettings
  alias Tymeslot.Auth
  alias Tymeslot.Pagination.OffsetPage
  alias Tymeslot.Security.AuditLog
  alias TymeslotWeb.Dashboard.Admin.HubComponent
  alias TymeslotWeb.Live.Shared.Flash

  @empty_filters %{"event_type" => "", "user" => "", "from" => "", "to" => ""}

  @spec init(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def init(socket) do
    socket
    |> assign(:audit_filters, @empty_filters)
    |> assign(:audit_page, 1)
    |> assign(:audit_per_page, OffsetPage.default_page_size())
  end

  @doc "Loads the current page for the current filters, page and page size."
  @spec load(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load(socket) do
    filters = socket.assigns.audit_filters

    page =
      filters["event_type"]
      |> event_filter()
      |> Map.merge(%{
        user_ids: user_ids(filters["user"]),
        from: day_start(filters["from"], 0),
        to: day_start(filters["to"], 1)
      })
      |> AuditLog.list_events(socket.assigns.audit_page, socket.assigns.audit_per_page)

    socket
    |> assign(:audit_events, page.entries)
    |> assign(:audit_page, page.page)
    |> assign(:audit_per_page, page.per_page)
    |> assign(:audit_total, page.total)
    |> assign(:audit_total_pages, page.total_pages)
    |> assign(:audit_emails, Auth.emails_by_ids(referenced_user_ids(page.entries)))
    |> assign(:audit_event_types, AuditLog.event_types_by_category())
    |> assign(:audit_retention_days, AuditLog.retention_days())
  end

  @spec filter(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def filter(socket, params) do
    socket
    |> assign(
      :audit_filters,
      Map.merge(@empty_filters, Map.take(params, Map.keys(@empty_filters)))
    )
    |> assign(:audit_page, 1)
    |> load()
  end

  @doc "Goes to the given page; `load/1` clamps it to the pages that exist."
  @spec go_to_page(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def go_to_page(socket, page) do
    case OffsetPage.parse_page(page) do
      {:ok, number} -> socket |> assign(:audit_page, number) |> load()
      :error -> socket
    end
  end

  @doc "Switches the page size and goes back to page 1."
  @spec set_per_page(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def set_per_page(socket, per_page) do
    case OffsetPage.parse_per_page(per_page) do
      {:ok, size} -> socket |> assign(:audit_per_page, size) |> assign(:audit_page, 1) |> load()
      :error -> socket
    end
  end

  @doc """
  Switches one audit event category on or off (App Settings → Audit log),
  keeping the admin's other overrides.
  """
  @spec set_event_category(Phoenix.LiveView.Socket.t(), String.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def set_event_category(socket, key, state) when state in ["true", "false"] do
    overrides = Map.put(AppSettings.get(:audit_log_events) || %{}, key, state == "true")

    case AppSettings.update(%{audit_log_events: overrides}) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> Flash.put_flash(:info, dgettext("dashboard_admin", "Audit log events updated."))
         |> HubComponent.load_settings_data()}

      {:error, _reason} ->
        {:noreply,
         Flash.put_flash(socket, :error, dgettext("dashboard_admin", "Could not update setting."))}
    end
  end

  def set_event_category(socket, _key, _state), do: {:noreply, socket}

  defp event_filter("category:" <> key), do: %{category: key}
  defp event_filter(event_type), do: %{event_type: event_type}

  # The start of the given ISO day plus `offset` days, in UTC: the "to" date
  # passes 1 so the whole day is included. A blank or malformed date is no
  # bound.
  defp day_start(iso_date, offset) when is_binary(iso_date) do
    case Date.from_iso8601(iso_date) do
      {:ok, date} -> date |> Date.add(offset) |> DateTime.new!(~T[00:00:00], "Etc/UTC")
      {:error, _reason} -> nil
    end
  end

  defp day_start(_iso_date, _offset), do: nil

  # A user filter matches accounts by email, like the Users tab search; an
  # empty filter means every user. A filter matching no account yields `[]`,
  # which matches no event rather than every event.
  defp user_ids(term) when is_binary(term) do
    case String.trim(term) do
      "" -> nil
      trimmed -> trimmed |> Auth.list_users() |> Enum.map(& &1.id)
    end
  end

  defp user_ids(_term), do: nil

  defp referenced_user_ids(events) do
    events
    |> Enum.flat_map(&[&1.user_id, &1.actor_user_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end
end
