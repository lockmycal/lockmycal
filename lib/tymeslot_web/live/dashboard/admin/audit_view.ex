defmodule TymeslotWeb.Dashboard.Admin.AuditView do
  @moduledoc """
  Audit tab: the audit log of security and payment events
  (`Tymeslot.Security.AuditLog`), newest
  first, filterable by event type or category, user and date range, in
  numbered pages of 20, 50 or 100 rows.

  A stateless view rendered inside `TymeslotWeb.Dashboard.Admin.HubComponent`
  — every interactive element carries `phx-target={@target}` so its events
  reach the hub's own `handle_event/3`.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Pagination.OffsetPage
  alias TymeslotWeb.AdminLive.Tabs
  alias TymeslotWeb.Components.Dashboard.Pagination
  alias TymeslotWeb.Dashboard.Admin.AuditEventRows
  alias TymeslotWeb.Dashboard.Admin.Shared

  attr :events, :list, required: true
  attr :emails, :map, required: true, doc: "user_id => email, for users that still exist"
  attr :event_types, :list, required: true, doc: "[{category_key, [event_type]}]"

  attr :filters, :map,
    required: true,
    doc: ~s(%{"event_type" => _, "user" => _, "from" => _, "to" => _})

  attr :page, :integer, required: true
  attr :per_page, :integer, required: true
  attr :total, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :retention_days, :integer, required: true
  attr :target, :any, required: true

  @spec audit_tab(map()) :: Phoenix.LiveView.Rendered.t()
  def audit_tab(assigns) do
    ~H"""
    <.subsection_header
      icon="hero-clipboard-document-list"
      title={dgettext("dashboard_admin", "Events")}
      class="mb-3"
    />

    <.form
      for={%{}}
      as={:audit}
      id="admin-audit-filter-form"
      phx-change="filter_audit"
      phx-submit="filter_audit"
      phx-target={@target}
      class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-3 mb-3"
    >
      <.input
        type="select"
        id="admin-audit-event-type"
        name="audit[event_type]"
        label={dgettext("dashboard_admin", "Event")}
        value={@filters["event_type"]}
        prompt={dgettext("dashboard_admin", "All event types")}
        options={event_type_options(@event_types)}
      />
      <.input
        type="text"
        id="admin-audit-user"
        name="audit[user]"
        label={dgettext("dashboard_admin", "User")}
        value={@filters["user"]}
        placeholder={dgettext("dashboard_admin", "Filter by user email")}
        phx-debounce="300"
        icon="hero-magnifying-glass"
      />
      <.input
        type="date"
        id="admin-audit-from"
        name="audit[from]"
        label={dgettext("dashboard_admin", "From")}
        value={@filters["from"]}
        max={blank_to_nil(@filters["to"])}
      />
      <.input
        type="date"
        id="admin-audit-to"
        name="audit[to]"
        label={dgettext("dashboard_admin", "To")}
        value={@filters["to"]}
        min={blank_to_nil(@filters["from"])}
      />
    </.form>

    <p class="mb-3 text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
      {dgettext(
        "dashboard_admin",
        "Times are in UTC. Events are deleted after %{days} days (%{setting}).",
        days: @retention_days,
        setting: retention_setting_path()
      )}
    </p>

    <div class="card-glass p-0! overflow-x-auto">
      <table class="min-w-full divide-y divide-neutral-100 dark:divide-twilight-indigo-800">
        <thead class="bg-neutral-50/60 dark:bg-twilight-indigo-950/60">
          <tr>
            <Shared.th>{dgettext("dashboard_admin", "Time")}</Shared.th>
            <Shared.th>{dgettext("dashboard_admin", "Event")}</Shared.th>
            <Shared.th>{dgettext("dashboard_admin", "User")}</Shared.th>
            <Shared.th>{dgettext("dashboard_admin", "By")}</Shared.th>
            <Shared.th>{dgettext("dashboard_admin", "IP address")}</Shared.th>
            <Shared.th>{dgettext("dashboard_admin", "Details")}</Shared.th>
          </tr>
        </thead>
        <tbody class="divide-y divide-neutral-50 dark:divide-twilight-indigo-800">
          <tr :for={event <- @events} data-testid="audit-event-row">
            <td class="px-6 py-3 text-sm text-neutral-700 dark:text-neutral-200 whitespace-nowrap font-mono">
              {format_time(event.inserted_at)}
            </td>
            <td class="px-6 py-3 text-sm font-medium text-neutral-900 dark:text-neutral-50 font-mono">
              {event.event_type}
            </td>
            <td class="px-6 py-3 text-sm text-neutral-700 dark:text-neutral-200">
              {user_label(event.user_id, event.email || event.email_masked, @emails)}
            </td>
            <td class="px-6 py-3 text-sm text-neutral-700 dark:text-neutral-200">
              {actor_label(event, @emails)}
            </td>
            <td class="px-6 py-3 text-sm text-neutral-700 dark:text-neutral-200 font-mono">
              {event.ip_address || "—"}
            </td>
            <td class="px-6 py-3 text-xs text-neutral-500 dark:text-twilight-indigo-200 max-w-md break-words">
              {details(event)}
            </td>
          </tr>
        </tbody>
      </table>

      <p
        :if={@events == []}
        class="px-6 py-8 text-center text-sm text-neutral-500 dark:text-twilight-indigo-200"
      >
        {dgettext("dashboard_admin", "No events match these filters.")}
      </p>
    </div>

    <Pagination.pagination
      :if={@total > 0}
      id="admin-audit-pagination"
      class="mt-4"
      page={@page}
      total_pages={@total_pages}
      total={@total}
      per_page={@per_page}
      per_page_options={OffsetPage.page_sizes()}
      page_event="audit_page"
      per_page_event="audit_per_page"
      per_page_param="audit_paging"
      target={@target}
    />
    """
  end

  # One group per category, led by an option selecting the whole category
  # (`AuditActions` reads the `category:` prefix), so pattern-matched
  # categories are filterable even before any of their events was logged.
  defp event_type_options(groups) do
    Enum.map(groups, fn {key, types} ->
      label = AuditEventRows.category_label(key)

      whole =
        {dgettext("dashboard_admin", "All: %{category}", category: label), "category:" <> key}

      {label, [whole | types]}
    end)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # Built from the same labels the sidebar and the settings tabs render, so
  # the hint always names what the admin actually sees.
  defp retention_setting_path do
    Enum.join(
      [
        dgettext("dashboard_common", "App Settings"),
        Tabs.name(:audit_log)
      ],
      " → "
    )
  end

  defp format_time(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M:%S")

  defp user_label(nil, nil, _emails), do: "—"
  # `stored_email` is the address recorded with the event, masked on rows
  # recorded before the audit log kept it in full.
  defp user_label(nil, stored_email, _emails), do: stored_email

  defp user_label(user_id, stored_email, emails) do
    case Map.fetch(emails, user_id) do
      {:ok, email} ->
        email

      :error ->
        dgettext("dashboard_admin", "#%{id} (deleted)%{email}",
          id: user_id,
          email: if(stored_email, do: " " <> stored_email, else: "")
        )
    end
  end

  defp actor_label(%{actor_user_id: nil, metadata: %{"actor" => "cli"}}, _emails),
    do: dgettext("dashboard_admin", "Command line")

  defp actor_label(%{actor_user_id: nil}, _emails), do: "—"

  defp actor_label(%{actor_user_id: id, user_id: id}, _emails),
    do: dgettext("dashboard_admin", "The user")

  defp actor_label(%{actor_user_id: id}, emails), do: user_label(id, nil, emails)

  defp details(event) do
    [provider: event.provider, session: event.session_id]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Kernel.++(Enum.sort(event.metadata || %{}))
    |> Enum.reject(fn {key, _value} -> key == "actor" end)
    |> Enum.map_join(", ", fn {key, value} -> "#{key}: #{format_value(value)}" end)
  end

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_list(value), do: Enum.map_join(value, " ", &format_value/1)
  defp format_value(value), do: inspect(value)
end
