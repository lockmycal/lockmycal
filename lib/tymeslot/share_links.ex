defmodule Tymeslot.ShareLinks do
  @moduledoc """
  Emailing a host's public links — booking page, public calendar and the
  direct links of individual meeting types — to people of the host's choice.

  The dashboard only ever sends link *keys* (`"booking_page"`, `"calendar"`,
  `"meeting_type:<id>"`); URLs are always rebuilt here from the host's own
  profile and meeting types, both when the send is requested and again when the
  email job runs. A crafted request therefore cannot make a mail from this
  instance's domain carry an arbitrary link, and a meeting type deleted or
  deactivated in between simply drops out of the email.

  Recipients are arbitrary addresses, so every send is capped
  (`@max_recipients`) and rate limited per host and per recipient
  (`@rate_limit` within `@rate_window_ms`) to keep the feature from being used
  as a spam relay.
  """

  alias Tymeslot.Emails.EmailScheduler
  alias Tymeslot.MeetingTypes
  alias Tymeslot.Profiles
  alias Tymeslot.Scheduling.LinkAccessPolicy
  alias Tymeslot.Security.FieldValidators.EmailValidator
  alias Tymeslot.Security.RateLimiter
  alias Tymeslot.Utils.UrlBuilder

  @max_recipients 10
  @max_message_length 1000
  @rate_limit 30
  @rate_window_ms :timer.hours(1)

  @type link_kind :: :booking_page | :calendar | :meeting_type
  @type link :: %{key: String.t(), kind: link_kind(), name: String.t() | nil, url: String.t()}

  @type send_error ::
          :not_allowed
          | :no_recipients
          | :too_many_recipients
          | {:invalid_recipients, [String.t()]}
          | :no_links
          | :message_too_long
          | :rate_limited

  @doc "Maximum number of recipients accepted by one `send_links/4` call."
  @spec max_recipients() :: pos_integer()
  def max_recipients, do: @max_recipients

  @doc "Maximum length of the optional personal message."
  @spec max_message_length() :: pos_integer()
  def max_message_length, do: @max_message_length

  @doc """
  The links a host can share, in display order: the booking page, the public
  calendar, then every active meeting type in `meeting_types` (private ones
  included — a direct link is exactly how those are meant to be reached).
  Empty when the host has no username. The public calendar is left out when
  the host switched it off (`Profiles.public_calendar_enabled?/1`).
  """
  @spec available_links(map() | nil, [map()]) :: [link()]
  def available_links(%{username: username} = profile, meeting_types)
      when is_binary(username) and username != "" do
    booking_page = %{
      key: "booking_page",
      kind: :booking_page,
      name: nil,
      url: UrlBuilder.booking_url(username)
    }

    calendar =
      if Profiles.public_calendar_enabled?(profile) do
        [
          %{
            key: "calendar",
            kind: :calendar,
            name: nil,
            url: UrlBuilder.public_calendar_url(username)
          }
        ]
      else
        []
      end

    types =
      for %{is_active: true} = meeting_type <- meeting_types do
        %{
          key: meeting_type_key(meeting_type),
          kind: :meeting_type,
          name: meeting_type.name,
          url: UrlBuilder.meeting_type_url(username, MeetingTypes.effective_slug(meeting_type))
        }
      end

    [booking_page | calendar] ++ types
  end

  def available_links(_profile, _meeting_types), do: []

  @doc """
  The host's shareable links, loading their meeting types. Uses the
  non-seeding listing, so neither the dashboard nor the email job ever
  (re)creates default meeting types as a side effect.
  """
  @spec links_for(map() | nil) :: [link()]
  def links_for(%{user_id: user_id} = profile) when is_integer(user_id) do
    available_links(profile, MeetingTypes.list_all_meeting_types(user_id))
  end

  def links_for(_profile), do: []

  @doc "The link key of a meeting type, as used in the share form and job args."
  @spec meeting_type_key(map()) :: String.t()
  def meeting_type_key(%{id: id}), do: "meeting_type:#{id}"

  @doc """
  Keeps only the `links` whose key is in `keys`, preserving `links`' order.
  Unknown keys are ignored.
  """
  @spec select_links([link()], [String.t()]) :: [link()]
  def select_links(links, keys) when is_list(keys) do
    wanted = MapSet.new(keys)
    Enum.filter(links, &MapSet.member?(wanted, &1.key))
  end

  @doc """
  Validates a share request and enqueues one email job per recipient.

  `params` carries `"recipients"` (a comma/semicolon/whitespace separated
  string), `"links"` (a list of link keys) and an optional `"message"`.
  `integration_status` is the dashboard's, so the same readiness gate applies
  as for copying the link (`LinkAccessPolicy.can_link?/2`).

  Returns `{:ok, recipient_count}`.
  """
  @spec send_links(map(), map() | nil, map(), map()) ::
          {:ok, pos_integer()} | {:error, send_error()}
  def send_links(user, profile, integration_status, params) when is_map(params) do
    message = params |> Map.get("message", "") |> to_string() |> String.trim()

    with :ok <- check_allowed(profile, integration_status),
         {:ok, recipients} <- parse_recipients(Map.get(params, "recipients", "")),
         {:ok, links} <- resolve_links(profile, Map.get(params, "links", [])),
         :ok <- validate_message(message),
         :ok <- check_rate_limit(user.id, recipients) do
      keys = Enum.map(links, & &1.key)

      Enum.each(recipients, fn recipient ->
        EmailScheduler.schedule_share_links_email(user.id, recipient, keys, message)
      end)

      {:ok, length(recipients)}
    end
  end

  @doc """
  Splits a free-text recipient list into unique, validated, lower-cased
  addresses.
  """
  @spec parse_recipients(String.t() | nil) ::
          {:ok, [String.t()]}
          | {:error, :no_recipients | :too_many_recipients | {:invalid_recipients, [String.t()]}}
  def parse_recipients(input) when is_binary(input) do
    recipients =
      input
      |> String.split(~r/[\s,;]+/, trim: true)
      |> Enum.map(&String.downcase/1)
      |> Enum.uniq()

    invalid = Enum.reject(recipients, &(EmailValidator.validate(&1) == :ok))

    cond do
      recipients == [] -> {:error, :no_recipients}
      invalid != [] -> {:error, {:invalid_recipients, invalid}}
      length(recipients) > @max_recipients -> {:error, :too_many_recipients}
      true -> {:ok, recipients}
    end
  end

  def parse_recipients(_input), do: {:error, :no_recipients}

  defp check_allowed(profile, integration_status) do
    if LinkAccessPolicy.can_link?(profile, integration_status),
      do: :ok,
      else: {:error, :not_allowed}
  end

  defp resolve_links(profile, keys) when is_list(keys) do
    case profile |> links_for() |> select_links(keys) do
      [] -> {:error, :no_links}
      links -> {:ok, links}
    end
  end

  defp resolve_links(_profile, _keys), do: {:error, :no_links}

  defp validate_message(message) do
    if String.length(message) > @max_message_length,
      do: {:error, :message_too_long},
      else: :ok
  end

  # One hit per recipient, so the budget caps emails sent, not form submits.
  defp check_rate_limit(user_id, recipients) do
    Enum.reduce_while(recipients, :ok, fn _recipient, :ok ->
      case RateLimiter.check_rate_limit("share_links:#{user_id}", @rate_limit, @rate_window_ms) do
        :ok -> {:cont, :ok}
        {:error, :rate_limited} -> {:halt, {:error, :rate_limited}}
      end
    end)
  end
end
