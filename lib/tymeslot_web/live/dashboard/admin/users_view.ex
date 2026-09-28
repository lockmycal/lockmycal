defmodule TymeslotWeb.Dashboard.Admin.UsersView do
  @moduledoc """
  Users tab: install user counts at the top, followed by the list of users
  with promote/demote/disable/enable/delete row actions and the
  confirmation modal that opens when one is triggered.

  A stateless view rendered inside `TymeslotWeb.Dashboard.Admin.HubComponent`
  — every interactive element carries `phx-target={@target}` so its events
  reach the hub's own `handle_event/3` rather than the parent LiveView.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Dashboard.Admin.UserColumn
  alias Tymeslot.Pagination.OffsetPage
  alias Tymeslot.Profiles.ProfileSchema
  alias Tymeslot.Timezones.CountryCodes
  alias TymeslotWeb.Components.Dashboard.Pagination
  alias TymeslotWeb.Components.Dashboard.SearchInput
  alias TymeslotWeb.Dashboard.Admin.{ConfirmRoleChangeModal, ConfirmUserActionModal, Shared}

  attr :users, :list, required: true
  attr :current_user, :map, required: true
  attr :user_count, :integer, required: true
  attr :admin_count, :integer, required: true
  attr :user_countries, :map, required: true, doc: "user_id => ConnectAccountSchema.t()"
  attr :search_term, :string, required: true
  attr :page, :integer, required: true
  attr :per_page, :integer, required: true
  attr :total, :integer, required: true, doc: "users matching the search, across all pages"
  attr :total_pages, :integer, required: true
  attr :pending_action, :any, required: true
  attr :pending_action_submitting, :boolean, required: true
  attr :target, :any, required: true

  @spec users_tab(map()) :: Phoenix.LiveView.Rendered.t()
  def users_tab(assigns) do
    extra_columns = UserColumn.registered()

    assigns =
      assigns
      |> assign(:extra_columns, extra_columns)
      |> assign(:preloaded_columns, UserColumn.preload_all(extra_columns, assigns.users))

    ~H"""
    <.subsection_header
      icon="hero-chart-bar"
      title={dgettext("dashboard_admin", "Overview")}
      class="mb-3"
    />
    <div class="grid gap-6 sm:grid-cols-2 mb-8">
      <.stat_card label={dgettext("dashboard_admin", "Total users")} value={@user_count} />
      <.stat_card label={dgettext("dashboard_admin", "Admins")} value={@admin_count} />
    </div>

    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 mb-3">
      <.subsection_header
        icon="hero-users"
        title={dgettext("dashboard_admin", "All Users")}
        count={@total}
      />

      <SearchInput.search_input
        form_id="admin-users-search-form"
        input_id="admin-users-search-input"
        value={@search_term}
        change_event="search_users"
        target={@target}
        placeholder={dgettext("dashboard_admin", "Search users")}
        input_class="w-full sm:w-64"
      />
    </div>

    <div class="card-glass p-0! overflow-hidden">
      <table class="min-w-full divide-y divide-neutral-100 dark:divide-twilight-indigo-800">
        <thead class="bg-neutral-50/60 dark:bg-twilight-indigo-950/60">
          <tr>
            <Shared.th>{dgettext("dashboard_admin", "Email")}</Shared.th>
            <Shared.th>{dgettext("dashboard_admin", "Display name")}</Shared.th>
            <Shared.th>{dgettext("dashboard_admin", "Booking slug")}</Shared.th>
            <Shared.th>{dgettext("dashboard_admin", "Role")}</Shared.th>
            <Shared.th>{dgettext("dashboard_admin", "Country")}</Shared.th>
            <Shared.th :for={column <- @extra_columns}>{column.header()}</Shared.th>
            <Shared.th class="text-right">{dgettext("dashboard_admin", "Actions")}</Shared.th>
          </tr>
        </thead>
        <tbody class="divide-y divide-neutral-50 dark:divide-twilight-indigo-800">
          <tr
            :for={user <- @users}
            class="hover:bg-neutral-50/40 dark:hover:bg-twilight-indigo-900/40 transition-colors"
          >
            <td class="px-6 py-4 text-sm font-medium text-neutral-900 dark:text-neutral-50">
              {user.email}
              <span
                :if={user.id == @current_user.id}
                class="ml-2 text-xs font-bold text-neutral-500 dark:text-twilight-indigo-300 uppercase tracking-wider"
              >
                {dgettext("dashboard_admin", "(you)")}
              </span>
            </td>
            <td class="px-6 py-4 text-sm text-neutral-900 dark:text-neutral-50">
              <span :if={profile_full_name(user)}>{profile_full_name(user)}</span>
              <span
                :if={!profile_full_name(user)}
                class="text-neutral-400 dark:text-twilight-indigo-400"
              >—</span>
            </td>
            <td class="px-6 py-4 text-sm text-neutral-700 dark:text-neutral-200">
              <span :if={profile_username(user)} class="font-mono">{profile_username(user)}</span>
              <span
                :if={!profile_username(user)}
                class="text-neutral-400 dark:text-twilight-indigo-400"
              >—</span>
            </td>
            <td class="px-6 py-4">
              <span
                :if={user.is_admin}
                class="inline-flex items-center rounded-full bg-primary-100 dark:bg-primary-900 px-3 py-1 text-xs font-black uppercase tracking-wider text-primary-700 dark:text-primary-300"
              >
                {dgettext("dashboard_admin", "Admin")}
              </span>
              <span
                :if={!user.is_admin}
                class="text-sm text-neutral-500 dark:text-twilight-indigo-300"
              >{dgettext(
                "dashboard_admin",
                "User"
              )}</span>
              <span
                :if={user.disabled_at && is_nil(user.deletion_requested_at)}
                class="ml-2 inline-flex items-center rounded-full bg-red-100 dark:bg-red-900 px-3 py-1 text-xs font-black uppercase tracking-wider text-red-700 dark:text-red-300"
              >
                {dgettext("dashboard_admin", "Disabled")}
              </span>
              <span
                :if={user.deletion_requested_at}
                class="ml-2 inline-flex items-center rounded-full bg-red-100 dark:bg-red-900 px-3 py-1 text-xs font-black uppercase tracking-wider text-red-700 dark:text-red-300"
                data-testid="deletion-pending-badge"
              >
                {dgettext("dashboard_admin", "Deletion pending")}
              </span>
            </td>
            <td class="px-6 py-4 text-sm text-neutral-700 dark:text-neutral-200">
              <span
                :if={country_code(@user_countries, user.id)}
                title={country_name(@user_countries, user.id)}
              >
                {country_code(@user_countries, user.id)}
              </span>
              <span
                :if={!country_code(@user_countries, user.id)}
                class="text-neutral-400 dark:text-twilight-indigo-400"
              >—</span>
            </td>
            <td :for={column <- @extra_columns} class="px-6 py-4">
              {UserColumn.render_cell(column, user, @current_user, @preloaded_columns)}
            </td>
            <td class="px-6 py-4 text-right">
              <.user_row_action
                user={user}
                is_self={user.id == @current_user.id}
                is_last_admin={@admin_count <= 1}
                target={@target}
              />
            </td>
          </tr>
        </tbody>
      </table>

      <p
        :if={@users == []}
        class="px-6 py-8 text-center text-sm text-neutral-500 dark:text-twilight-indigo-200"
      >
        {dgettext("dashboard_admin", "No users match your search.")}
      </p>
    </div>

    <Pagination.pagination
      :if={@total > 0}
      id="admin-users-pagination"
      class="mt-4"
      page={@page}
      total_pages={@total_pages}
      total={@total}
      per_page={@per_page}
      per_page_options={OffsetPage.page_sizes()}
      page_event="users_page"
      per_page_event="users_per_page"
      per_page_param="users_paging"
      target={@target}
    />

    <ConfirmRoleChangeModal.confirm_role_change_modal
      :if={@pending_action && @pending_action.kind in [:promote, :demote]}
      action={@pending_action.kind}
      user={@pending_action}
      self?={@pending_action.id == @current_user.id}
      submitting={@pending_action_submitting}
      target={@target}
    />

    <ConfirmUserActionModal.confirm_user_action_modal
      :if={@pending_action && @pending_action.kind in [:delete, :disable, :enable]}
      action={@pending_action.kind}
      user={@pending_action}
      submitting={@pending_action_submitting}
      target={@target}
    />
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="card-glass">
      <p class="text-xs font-black uppercase tracking-wider text-neutral-500 dark:text-twilight-indigo-300 mb-2">
        {@label}
      </p>
      <p class="text-4xl font-black text-neutral-900 dark:text-neutral-50 tracking-tight">{@value}</p>
    </div>
    """
  end

  defp profile_full_name(%{profile: %ProfileSchema{full_name: name}})
       when is_binary(name) and name != "",
       do: name

  defp profile_full_name(_user), do: nil

  defp profile_username(%{profile: %ProfileSchema{username: username}})
       when is_binary(username) and username != "",
       do: username

  defp profile_username(_user), do: nil

  # Country only shows once the host has activated a Connect account (see
  # `Tymeslot.MeetingPayments.get_connect_accounts_for_users/1`) — `nil`
  # covers both "no account yet" and an account with no country recorded.
  defp country_code(user_countries, user_id) do
    case Map.get(user_countries, user_id) do
      %{country: country} when is_binary(country) and country != "" -> String.upcase(country)
      _other -> nil
    end
  end

  defp country_name(user_countries, user_id) do
    case country_code(user_countries, user_id) do
      nil -> nil
      code -> CountryCodes.name_for(code)
    end
  end

  attr :user, :map, required: true
  attr :is_self, :boolean, required: true
  attr :is_last_admin, :boolean, required: true
  attr :target, :any, required: true

  defp user_row_action(assigns) do
    ~H"""
    <div :if={is_nil(@user.deletion_requested_at)} class="inline-flex items-center justify-end gap-2">
      <%!-- Only-admin self row: explain why demote/disable/delete are unavailable. --%>
      <span
        :if={@user.is_admin and @is_self and @is_last_admin}
        class="text-xs text-neutral-500 dark:text-twilight-indigo-200 font-medium max-w-[11rem] text-right"
        data-testid="last-admin-self-note"
      >
        {dgettext(
          "dashboard_admin",
          "You're the only admin. Promote someone else before demoting yourself."
        )}
      </span>

      <%!-- @admin_count is loaded per handle_params; the server guard in AdminRoles/
           AccountStatus is authoritative and will block the last-admin action even
           if a button is momentarily visible due to concurrent changes between
           sessions. --%>
      <button
        :if={@user.is_admin and not (@is_self and @is_last_admin)}
        type="button"
        phx-click="request_demote"
        phx-value-id={@user.id}
        phx-value-email={@user.email}
        phx-target={@target}
        title={dgettext("dashboard_admin", "Demote %{email} from admin", email: @user.email)}
        aria-label={dgettext("dashboard_admin", "Demote %{email} from admin", email: @user.email)}
        class="row-action-button row-action-button--icon-only row-action-button--attention"
      >
        <.icon name="hero-shield-exclamation" class="w-5 h-5" />
      </button>

      <button
        :if={not @user.is_admin}
        type="button"
        phx-click="request_promote"
        phx-value-id={@user.id}
        phx-value-email={@user.email}
        phx-target={@target}
        title={dgettext("dashboard_admin", "Promote %{email} to admin", email: @user.email)}
        aria-label={dgettext("dashboard_admin", "Promote %{email} to admin", email: @user.email)}
        class="row-action-button row-action-button--icon-only row-action-button--neutral"
      >
        <.icon name="hero-shield-check" class="w-5 h-5" />
      </button>

      <button
        :if={is_nil(@user.disabled_at) and not @is_self}
        type="button"
        phx-click="request_disable"
        phx-value-id={@user.id}
        phx-value-email={@user.email}
        phx-target={@target}
        title={dgettext("dashboard_admin", "Disable %{email}", email: @user.email)}
        aria-label={dgettext("dashboard_admin", "Disable %{email}", email: @user.email)}
        class="row-action-button row-action-button--icon-only row-action-button--attention"
      >
        <.icon name="hero-lock-closed" class="w-5 h-5" />
      </button>

      <button
        :if={not is_nil(@user.disabled_at)}
        type="button"
        phx-click="request_enable"
        phx-value-id={@user.id}
        phx-value-email={@user.email}
        phx-target={@target}
        title={dgettext("dashboard_admin", "Enable %{email}", email: @user.email)}
        aria-label={dgettext("dashboard_admin", "Enable %{email}", email: @user.email)}
        class="row-action-button row-action-button--icon-only row-action-button--neutral"
      >
        <.icon name="hero-lock-open" class="w-5 h-5" />
      </button>

      <button
        :if={not @is_self and not (@user.is_admin and @is_last_admin)}
        type="button"
        phx-click="request_delete"
        phx-value-id={@user.id}
        phx-value-email={@user.email}
        phx-target={@target}
        title={dgettext("dashboard_admin", "Delete %{email}", email: @user.email)}
        aria-label={dgettext("dashboard_admin", "Delete %{email}", email: @user.email)}
        class="row-action-button row-action-button--icon-only row-action-button--danger"
      >
        <.icon name="hero-trash" class="w-5 h-5" />
      </button>
    </div>
    """
  end
end
