defmodule Tymeslot.Dashboard.Admin.UserColumn do
  @moduledoc """
  Behaviour for an extra column on the admin Users table
  (`TymeslotWeb.Dashboard.Admin.UsersView.users_tab/1`).

  Same rationale as `Tymeslot.Dashboard.ExtensionSchema`: Core defines the
  contract, an external application (e.g. a paid overlay wanting to show
  each user's plan) implements it and registers itself — Core never names
  the external application, imports from it, or checks whether one is
  present.

  ## Usage

  Register one or more modules implementing this behaviour via
  `Application.put_env/3`, typically in `config/runtime.exs`:

      config :tymeslot, :admin_users_extra_columns, [
        MyApp.Dashboard.Admin.SubscriptionColumn
      ]

  Core reads this list at render time and appends one `<th>`/`<td>` pair
  per module, in list order, after the built-in columns. An empty or unset
  list (the default) renders the table exactly as it does today — self-host
  installs with no overlay registered see no difference at all.

      defmodule MyApp.Dashboard.Admin.SubscriptionColumn do
        @behaviour Tymeslot.Dashboard.Admin.UserColumn

        @impl true
        def header, do: "Subscription"

        @impl true
        def render(user) do
          assigns = %{plan: my_app_plan_for(user.id)}

          ~H\"\"\"
          <span>{@plan}</span>
          \"\"\"
        end
      end

  `render/1` runs once per row, so a column that reads its own data per row
  (like `my_app_plan_for/1` above) does one query per user. The table isn't
  paginated, so to avoid that, implement `preload/1` (one batch load for the
  whole table) and `render/3` (which receives the row's entry) instead:

        @impl true
        def preload(users), do: my_app_plans_by_user_id(Enum.map(users, & &1.id))

        @impl true
        def render(user, _viewer, plan) do
          assigns = %{plan: plan || :free}
          ...
        end
  """

  alias Tymeslot.Auth.UserSchema

  @doc "Column header text, already translated if applicable."
  @callback header() :: String.t()

  @doc "Renders one row's cell for this column, given the full user record."
  @callback render(UserSchema.t()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  Same as `render/1`, but also given the admin currently viewing the table.
  Implement this instead of `render/1` when the cell handles its own events
  (e.g. a nested LiveComponent): those events skip `DashboardLive`'s admin
  gate, so the cell must re-check that the viewer is still an admin itself,
  the same way `TymeslotWeb.Dashboard.Admin.HubComponent` does per event.
  """
  @callback render(UserSchema.t(), viewer :: UserSchema.t()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  Loads this column's data for every user in the table at once, keyed by
  user id — so a column backed by its own table does one query per render
  instead of one per row. Implement together with `render/3`, which then
  receives this map's entry for its row (`nil` when the map has none).
  """
  @callback preload([UserSchema.t()]) :: %{optional(pos_integer()) => term()}

  @doc "Same as `render/2`, plus this row's entry from `preload/1`."
  @callback render(UserSchema.t(), viewer :: UserSchema.t(), preloaded :: term()) ::
              Phoenix.LiveView.Rendered.t()

  @optional_callbacks preload: 1, render: 1, render: 2, render: 3

  @doc """
  Runs `preload/1` once for each of `columns` that implements it, returning
  `%{column => %{user_id => data}}` for `render_cell/4`.
  """
  @spec preload_all([module()], [UserSchema.t()]) :: %{module() => map()}
  def preload_all(columns, users) do
    for column <- columns,
        Code.ensure_loaded?(column),
        function_exported?(column, :preload, 1),
        into: %{},
        do: {column, column.preload(users)}
  end

  @doc """
  Renders `column`'s cell for `user`, preferring `render/3` (with `viewer`
  and the row's `preload/1` entry from `preloaded`, the `preload_all/2`
  result), then `render/2` (with `viewer`), then `render/1`.
  """
  @spec render_cell(module(), UserSchema.t(), UserSchema.t(), %{module() => map()}) ::
          Phoenix.LiveView.Rendered.t()
  def render_cell(column, user, viewer, preloaded \\ %{}) do
    Code.ensure_loaded(column)

    cond do
      function_exported?(column, :render, 3) ->
        column.render(user, viewer, preloaded |> Map.get(column, %{}) |> Map.get(user.id))

      function_exported?(column, :render, 2) ->
        column.render(user, viewer)

      true ->
        column.render(user)
    end
  end

  @doc """
  Reads the registered extra-column modules from config. Not validated the
  way `Tymeslot.Dashboard.ExtensionSchema` validates sidebar extensions —
  this list is short, developer-authored, and read on every render, so a
  misbehaving module surfaces immediately as a rendering crash rather than
  silently.
  """
  @spec registered() :: [module()]
  def registered do
    Application.get_env(:tymeslot, :admin_users_extra_columns, [])
  end
end
