defmodule Tymeslot.MeetingPayments.ConnectAccountsTest do
  # `start_onboarding/1` reads the global meeting-payments flag and default
  # country, which these tests change.
  use Tymeslot.DataCase, async: false
  use Oban.Testing, repo: Tymeslot.Repo

  @moduletag :database
  @moduletag :payments

  import Mox
  import Tymeslot.ConfigTestHelpers

  alias Tymeslot.MeetingPayments.BookingPaymentQueries
  alias Tymeslot.MeetingPayments.ConnectAccountQueries
  alias Tymeslot.MeetingPayments.ConnectAccounts
  alias Tymeslot.MeetingPayments.StripeAdapterMock

  setup :verify_on_exit!

  describe "country_options/0" do
    test "labels are '<name> (<CODE>)' with the lowercase code as the value" do
      options = ConnectAccounts.country_options()

      assert {"Czechia (CZ)", "cz"} in options
      assert {"Switzerland (CH)", "ch"} in options
    end

    test "sorted by country name" do
      names = Enum.map(ConnectAccounts.country_options(), fn {label, _value} -> label end)

      assert names == Enum.sort(names)
    end
  end

  describe "normalize_country/2" do
    test "downcases a recognised code" do
      assert ConnectAccounts.normalize_country("CZ", "ch") == "cz"
      assert ConnectAccounts.normalize_country("cz", "ch") == "cz"
    end

    test "falls back to the default for an unrecognised or missing code" do
      assert ConnectAccounts.normalize_country("not-a-country", "ch") == "ch"
      assert ConnectAccounts.normalize_country(nil, "ch") == "ch"
      assert ConnectAccounts.normalize_country(123, "ch") == "ch"
    end
  end

  describe "start_onboarding/2" do
    setup do
      with_config(:tymeslot,
        meeting_payments_enabled: true,
        feature_access_checker: Tymeslot.Features.DefaultAccessChecker,
        meeting_payments_default_country: "ch"
      )

      :ok
    end

    test "creates Stripe account, persists row, returns AccountLink URL" do
      user = insert(:user)

      expect(StripeAdapterMock, :create_account, fn params, opts ->
        assert params.type == "standard"
        assert params.country == "ch"
        send(self(), {:idempotency_key, opts[:idempotency_key]})
        {:ok, %{id: "acct_TEST_123", default_currency: "chf"}}
      end)

      expect(StripeAdapterMock, :create_account_link, fn params ->
        assert params.account == "acct_TEST_123"
        assert params.type == "account_onboarding"
        {:ok, %{url: "https://connect.stripe.com/setup/acct_TEST"}}
      end)

      assert {:ok, %{url: url}} = ConnectAccounts.start_onboarding(user)
      assert url =~ "connect.stripe.com"

      account = ConnectAccountQueries.live_for_user(user.id)
      assert account.stripe_account_id == "acct_TEST_123"
      assert account.default_currency == "chf"
      assert account.status == "active"
      assert_received {:idempotency_key, key}
      assert key == "connect_account:#{account.id}"
    end

    test "uses the operator-configured default country" do
      with_config(:tymeslot, meeting_payments_default_country: "de")
      user = insert(:user)

      expect(StripeAdapterMock, :create_account, fn params, _opts ->
        assert params.country == "de"
        {:ok, %{id: "acct_DE", default_currency: "eur"}}
      end)

      expect(StripeAdapterMock, :create_account_link, fn _params ->
        {:ok, %{url: "https://connect.stripe.com/de"}}
      end)

      assert {:ok, _result} = ConnectAccounts.start_onboarding(user)
      assert ConnectAccountQueries.live_for_user(user.id).country == "de"
    end

    test "is refused with the feature-access reason when meeting payments are disabled" do
      with_config(:tymeslot, meeting_payments_enabled: false)
      user = insert(:user)

      # No Stripe expectation: verify_on_exit! fails the test on any call.
      assert {:error, :feature_disabled} = ConnectAccounts.start_onboarding(user)
      refute ConnectAccountQueries.live_for_user(user.id)
    end

    test "resumes onboarding when placeholder exists from a prior crashed attempt" do
      user = insert(:user)
      {:ok, placeholder} = ConnectAccountQueries.insert_placeholder(user.id, "ch")

      expect(StripeAdapterMock, :create_account, fn _params, opts ->
        assert opts[:idempotency_key] == "connect_account:#{placeholder.id}"
        {:ok, %{id: "acct_RESUMED", default_currency: "chf"}}
      end)

      expect(StripeAdapterMock, :create_account_link, fn _params ->
        {:ok, %{url: "https://connect.stripe.com/resume"}}
      end)

      assert {:ok, %{url: _url}} = ConnectAccounts.start_onboarding(user)

      account = ConnectAccountQueries.live_for_user(user.id)
      assert account.stripe_account_id == "acct_RESUMED"
    end

    test "reuses the host's existing Stripe account instead of creating a second one" do
      # A host who left the hosted onboarding part-way and returns days later
      # (past Stripe's 24-hour idempotency-key window) must get a new link for
      # the account they already have, not a second Standard account.
      user = insert(:user)
      existing = insert(:connect_account, user: user, stripe_account_id: "acct_EXISTING")

      # No `create_account` expectation: verify_on_exit! fails on any call.
      expect(StripeAdapterMock, :create_account_link, fn params ->
        assert params.account == "acct_EXISTING"
        {:ok, %{url: "https://connect.stripe.com/continue"}}
      end)

      assert {:ok, %{url: "https://connect.stripe.com/continue", account: account}} =
               ConnectAccounts.start_onboarding(user)

      assert account.id == existing.id
      assert ConnectAccountQueries.live_for_user(user.id).stripe_account_id == "acct_EXISTING"
    end

    test "creates a new account after the host disconnects one that never finished onboarding" do
      # An account Stripe has closed or rejected can never finish onboarding;
      # disconnecting it is the host's way out. Starting again must create a
      # new account, not reuse the old one or replay Stripe's cached answer
      # for it within the idempotency-key window.
      user = insert(:user)
      old = insert(:connect_account, user: user, stripe_account_id: "acct_DEAD")

      assert {:ok, _result} = ConnectAccounts.disconnect(user)

      expect(StripeAdapterMock, :create_account, fn _params, opts ->
        refute opts[:idempotency_key] == "connect_account:#{old.id}"
        {:ok, %{id: "acct_FRESH", default_currency: "chf"}}
      end)

      expect(StripeAdapterMock, :create_account_link, fn params ->
        assert params.account == "acct_FRESH"
        {:ok, %{url: "https://connect.stripe.com/fresh"}}
      end)

      assert {:ok, %{url: "https://connect.stripe.com/fresh", account: account}} =
               ConnectAccounts.start_onboarding(user)

      refute account.id == old.id
      assert ConnectAccountQueries.live_for_user(user.id).stripe_account_id == "acct_FRESH"
    end

    test "classifies Stripe's hold on creating connected accounts" do
      user = insert(:user)

      expect(StripeAdapterMock, :create_account, fn _params, _opts ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :invalid_request_error,
           message:
             "We've temporarily restricted your ability to create this type of connected account."
         }}
      end)

      assert {:error, :account_creation_restricted} = ConnectAccounts.start_onboarding(user)
    end

    test "passes other Stripe request errors through unclassified" do
      user = insert(:user)

      error = %Stripe.Error{
        source: :stripe,
        code: :invalid_request_error,
        message: "Country is not supported."
      }

      expect(StripeAdapterMock, :create_account, fn _params, _opts -> {:error, error} end)

      assert {:error, ^error} = ConnectAccounts.start_onboarding(user)
    end

    test "creates the account in the host's chosen country, prefilled with their email" do
      user = insert(:user)

      expect(StripeAdapterMock, :create_account, fn params, _opts ->
        assert params.country == "cz"
        assert params.email == user.email
        {:ok, %{id: "acct_CZ", default_currency: "czk"}}
      end)

      expect(StripeAdapterMock, :create_account_link, fn _params ->
        {:ok, %{url: "https://connect.stripe.com/cz"}}
      end)

      assert {:ok, _result} = ConnectAccounts.start_onboarding(user, country: "cz")
      assert ConnectAccountQueries.live_for_user(user.id).country == "cz"
    end

    test "deletes the placeholder when Stripe rejects account creation, so a retry gets a fresh idempotency key" do
      # Regression: Stripe caches an idempotency key's response — including
      # errors — for 24h. Reusing the same key on retry would just replay
      # this same rejection even after the underlying problem (e.g. a
      # misconfigured Stripe setting) is fixed.
      user = insert(:user)

      expect(StripeAdapterMock, :create_account, fn _params, opts ->
        send(self(), {:idempotency_key, opts[:idempotency_key]})
        {:error, %{message: "Accounts v1 is not enabled for this platform"}}
      end)

      assert {:error, _reason} = ConnectAccounts.start_onboarding(user, country: "ch")
      assert_received {:idempotency_key, rejected_key}

      refute ConnectAccountQueries.live_for_user(user.id)

      # A subsequent attempt inserts a brand-new placeholder and therefore
      # uses a brand-new idempotency key, not the rejected one.
      expect(StripeAdapterMock, :create_account, fn _params, opts ->
        refute opts[:idempotency_key] == rejected_key
        {:ok, %{id: "acct_RETRY", default_currency: "chf"}}
      end)

      expect(StripeAdapterMock, :create_account_link, fn _params ->
        {:ok, %{url: "https://connect.stripe.com/retry"}}
      end)

      assert {:ok, %{url: _url}} = ConnectAccounts.start_onboarding(user, country: "ch")

      account = ConnectAccountQueries.live_for_user(user.id)
      assert account.stripe_account_id == "acct_RETRY"
    end

    test "deletes the placeholder when Stripe reports the connected account no longer exists, so a retry gets a fresh idempotency key" do
      # Regression: the account was created successfully (possibly on an
      # earlier attempt, replayed here via the idempotency key) but has since
      # been deleted from the Stripe dashboard. Retrying with the same row
      # would keep failing on the now-dangling account id.
      user = insert(:user)

      expect(StripeAdapterMock, :create_account, fn _params, opts ->
        send(self(), {:idempotency_key, opts[:idempotency_key]})
        {:ok, %{id: "acct_DELETED", default_currency: "chf"}}
      end)

      expect(StripeAdapterMock, :create_account_link, fn _params ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :invalid_request_error,
           message: "No such account: 'acct_DELETED'",
           extra: %{
             param: "account",
             http_status: 400,
             raw_error: %{"code" => "resource_missing", "type" => "invalid_request_error"}
           }
         }}
      end)

      assert {:error, _reason} = ConnectAccounts.start_onboarding(user, country: "ch")
      assert_received {:idempotency_key, first_key}

      refute ConnectAccountQueries.live_for_user(user.id)

      expect(StripeAdapterMock, :create_account, fn _params, opts ->
        refute opts[:idempotency_key] == first_key
        {:ok, %{id: "acct_RETRY_AFTER_DELETE", default_currency: "chf"}}
      end)

      expect(StripeAdapterMock, :create_account_link, fn _params ->
        {:ok, %{url: "https://connect.stripe.com/retry-after-delete"}}
      end)

      assert {:ok, %{url: _url}} = ConnectAccounts.start_onboarding(user, country: "ch")

      account = ConnectAccountQueries.live_for_user(user.id)
      assert account.stripe_account_id == "acct_RETRY_AFTER_DELETE"
    end

    test "row stays in recoverable 'creating' state when create_account_link fails" do
      user = insert(:user)

      expect(StripeAdapterMock, :create_account, fn _params, _opts ->
        {:ok, %{id: "acct_FAIL_LINK", default_currency: "chf"}}
      end)

      expect(StripeAdapterMock, :create_account_link, fn _params ->
        {:error, %{message: "Stripe link creation failed"}}
      end)

      assert {:error, _reason} = ConnectAccounts.start_onboarding(user)

      # Row must still exist in "creating" state — not left in "active" with a
      # stripe_account_id set, since the link never succeeded.
      account = ConnectAccountQueries.live_for_user(user.id)
      assert account.status == "creating"
      assert is_nil(account.stripe_account_id)
    end
  end

  describe "disconnect/1" do
    test "soft-deletes the live account" do
      user = insert(:user)
      {:ok, _placeholder} = ConnectAccountQueries.insert_placeholder(user.id, "ch")

      assert {:ok, %{cancelled_count: 0}} = ConnectAccounts.disconnect(user)

      refute ConnectAccountQueries.live_for_user(user.id)
    end

    test "is a noop when no account exists" do
      user = insert(:user)
      assert {:ok, %{cancelled_count: 0}} = ConnectAccounts.disconnect(user)
    end

    test "does not overwrite a payment that was concurrently transitioned to paid" do
      # Regression for the TOCTOU race: list_pending_for_host runs outside the
      # transaction and snapshots the payment as "pending". Before the transaction
      # executes, a concurrent checkout.session.completed webhook flips the same
      # row to "paid". The conditional UPDATE (status = 'pending') must skip that
      # row so the paid status is preserved and cancelled_count stays accurate.
      user = insert(:user)
      {:ok, _account} = ConnectAccountQueries.insert_placeholder(user.id, "ch")

      payment =
        insert(:booking_payment,
          host_user_id: user.id,
          stripe_checkout_session_id: "cs_race_test",
          status: "pending"
        )

      # Simulate the concurrent webhook arriving: flip the row to "paid" directly.
      {:ok, _updated} = BookingPaymentQueries.update(payment, %{status: "paid"})

      # disconnect/1 pre-fetches the payment as "pending" (it was pending when
      # list_pending_for_host ran), but inside the transaction the conditional
      # UPDATE finds status = 'paid' and must not overwrite it.
      stub(StripeAdapterMock, :expire_checkout_session, fn _session_id, _opts ->
        {:error, %{message: "already paid"}}
      end)

      assert {:ok, %{cancelled_count: 0}} = ConnectAccounts.disconnect(user)

      # The payment row must still be "paid" — not "failed".
      reloaded = BookingPaymentQueries.get(payment.id)
      assert reloaded.status == "paid"
    end

    # Disconnecting neither settles nor cancels a refund the host already owes;
    # it only takes away their ability to issue it from Tymeslot. The count is
    # reported so the caller can say so, rather than let the obligation drop
    # off the screen along with the account.
    test "reports the refunds the host is still holding" do
      user = insert(:user)
      {:ok, _account} = ConnectAccountQueries.insert_placeholder(user.id, "ch")

      meeting = insert(:meeting, status: "cancelled", cancelled_at: DateTime.utc_now(:second))
      payment = insert(:paid_booking_payment, host_user_id: user.id, meeting: meeting)

      assert {:ok, %{outstanding_refunds_count: 1}} = ConnectAccounts.disconnect(user)

      # Untouched: still owed, still unrefunded, just no longer refundable here.
      reloaded = BookingPaymentQueries.get(payment.id)
      assert reloaded.status == "paid"
      assert reloaded.refunded_amount_cents == 0
    end

    test "reports no outstanding refunds when the host owes nothing" do
      user = insert(:user)
      {:ok, _account} = ConnectAccountQueries.insert_placeholder(user.id, "ch")

      insert(:paid_booking_payment,
        host_user_id: user.id,
        meeting: insert(:meeting, status: "confirmed")
      )

      assert {:ok, %{outstanding_refunds_count: 0}} = ConnectAccounts.disconnect(user)
    end
  end
end
