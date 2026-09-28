[1.18.1.1]
* Merge upstream v1.18.0 and v1.18.1 (meeting locations — in person, phone, video or custom, several per meeting type, with the booker picking one and the video service; a large sign-in/sign-up security hardening; calendar sync and Teams/Outlook fixes; integration health alerts for admins; resumable Stripe Connect onboarding) — from this version on, upstream releases are merged into the fork instead of rebasing it
* Disabled accounts stay locked out under upstream's reworked sign-in: Google/GitHub/OIDC sign-in refuses them, and password sign-in only says the account is disabled after the correct password was given
* Bookings: when the chosen meeting location asks the booker for a phone number, that number is stored with the booking; otherwise the booking form's own Phone field is used as before
* Stripe Connect onboarding keeps the host's own country choice and email prefill on top of upstream's resume of an unfinished account; Mayotte is now in the country picker
* Fix the Rhythm theme's booking form showing raw keys ("phone", "enter_phone", "company", "enter_company", "meeting_information") instead of labels in English
* Fix an English validation message ("Confirmation timestamp is invalid") showing the unrelated text "Confirmation sent to"
* Fix updates and deletions of a meeting on the calendar connection's default calendar being sent without that calendar (Outlook happened to cope; a CalDAV server could miss the event)
* Organizers still get the "video room could not be created" email under upstream's new announcement logic, now at most once per failed room
* Add a daily cap on meeting time per weekday (Availability → each day's "No time limit" select, whole hours from 1 to 12, e.g. Monday max 2 h, Tuesday max 4 h): once a day's bookings would exceed it, longer slots stop being offered and such a booking or reschedule is refused; counts every live booking of the host that day (new column `weekly_availability.max_booked_minutes`)
* Add an optional per-user limit on calendars for a feature checker to impose (new optional `limit/2` callback on `Features.CheckerBehaviour`, `Features.limit/2`): it caps both how many connections a user may own (paused ones included — every connect path, i.e. forms, feed subscriptions, Exchange, Google/Outlook OAuth and onboarding, refuses a new one at the limit) and how many may be active (switching a paused one back on is refused until another is paused; `Calendar.deactivate_over_limit/1` pauses the surplus, keeping the primary and the oldest). The Calendars page shows "Active calendars: X of Y", disables "Connect a calendar" and the switches of paused calendars at the limit — nothing changes without a checker that sets a limit, so self-hosted installs stay unlimited
* Let an extension add its own tab to the admin settings (`config :tymeslot, :admin_settings_extra_tabs`, `Dashboard.Admin.SettingsTab` behaviour), rendered after the built-in tabs
* Remove the drop shadow from every button across the app — dashboard, sign-in pages, the Quill and Rhythm booking pages (action buttons, time slots, language switcher) and the segmented toggles, tabs and pickers
* Let an extra column on the admin Users table load its data for the whole table at once (optional `preload/1` + `render/3` on `Dashboard.Admin.UserColumn`), instead of one query per user row
* Fix an email sign-up that failed while creating the profile leaving an account that could never be completed (its address was then refused as already registered) and crashing the dashboard settings; the user and profile are now created together, and accounts already missing a profile get one on their next dashboard visit
* The admin audit log shows full email addresses — including sign-in attempts on unknown accounts and deleted accounts — instead of masked ones like `j***@example.com` (new column `audit_events.email`); the text log stays masked, and events recorded before this change keep their masked address
* The admin audit log is paged by number: "21–40 of 574", First / Previous / page numbers / Next / Last, and a Rows per page select (20, 50 or 100, default 20) instead of the Newer / Older buttons
* Administration → Users and Contacts are paged the same way (20, 50 or 100 rows, default 20) instead of listing everything at once; the list's count shows all matches, not just the current page
* Send links by email from the dashboard: the host picks recipients (typed, or picked from Contacts), which links to include — booking page, public calendar and/or individual active meeting types — and an optional personal message; the app mails them in the host's language with Reply-To set to the host. Available from a new envelope button in the sidebar (the Booking button there is now icon-only: open, copy, email), a "Share your booking page" card on Overview, and each meeting type's card and edit panel (pre-selecting that type); at most 10 recipients per send and 30 emails an hour per host
* Fix the contact picker's results list (quick-add meeting dialogs, Send links by email) staying white with unreadable text in dark mode
* Let each host switch their public calendar off (Calendars page → Public calendar → Visibility, on by default): `/:username/calendar` then only says the calendar is not public, the booking page's "View full calendar" link disappears and the calendar is no longer offered in Send links by email (new column `profiles.public_calendar_enabled`); the Calendars page now gathers all public calendar settings in one "Public calendar" block — Visibility first, then Colour settings (formerly the separate "Public calendar" colours block), Visible hours and Historical events
* Fix the meeting type Location section and its edit dialog in dark mode (the selected choice was unreadable); a location row's Edit/Delete are now icon buttons, and a phone location's "Ask the booker for their number" is an Enabled/Disabled toggle beside its text instead of a checkbox
* The meeting type "Change booking link" dialog explains that the part before the slug is the username, shared by all meeting types, and links to Profile settings to change it
* The meeting type's "Confirm each booking myself" approval setting is an Enabled/Disabled toggle beside its description instead of a checkbox, and the Approval section is readable in dark mode
* Add sign-in with a Microsoft account (personal, work or school), switched on by `ENABLE_MICROSOFT_AUTH=true` or Administration → Settings → "Microsoft login". It reuses the Outlook/Teams app registration (`OUTLOOK_CLIENT_ID`/`OUTLOOK_CLIENT_SECRET`), whose redirect URIs must also include `/auth/microsoft/callback`. Microsoft's email address is never trusted: it only prefills the sign-up form, and a new user confirms the address by email (new columns `users.microsoft_user_id`, `app_settings.microsoft_auth_enabled`)
* `.env.example` documents the variables `docker-compose.dev.yml` and the Dockerfiles need (container prefix, stack name, host name, image tag, image versions, port prefix) in a "LOCAL DEVELOPMENT" section at the top, and names the product LockMyCal in its texts
* COPYRIGHT names LockMyCal as a modified version of Tymeslot, keeping the upstream copyright notice; LockMyCal-branded `*.lockmycal.md` versions of README, README-Docker, SECURITY, CONTRIBUTING (DCO only, no CLA), CODE_OF_CONDUCT and docs/ADMIN replace the upstream files in the public GitHub copy
* The dashboard sidebar links to the source code of the running version (AGPL-3.0 §13), and admin alert emails point self-hosters to that repository's issue tracker instead of upstream Tymeslot's; both default to github.com/lockmycal/lockmycal and follow the new `SOURCE_CODE_URL` variable
* The public GitHub copy checks the DCO sign-off of pull requests with its own `dco.yml` workflow, and leaves out upstream's image publishing and nightly scheduled workflows
* The README screenshots (dashboard, availability, embed) show LockMyCal

[1.17.0.1]
* Request narrower Google Calendar OAuth scopes (`calendar.events` + `calendar.calendarlist.readonly`) instead of the full `calendar` scope — an existing Google integration still holding only the old broad scope keeps syncing but shows a reconnect (scope upgrade) prompt in Calendar settings
* The event detail modal's video picker now offers every connected video integration again (upstream's shared picker), so a video room can be added to or changed on an existing event; picking a provider creates the room
* SMTP over implicit TLS (port 465) now uses upstream's implementation (TLS options sent as both `tls_options` and `sockopts`), including the new `SMTP_TLS_MIDDLEBOX_COMPAT` option
* Fix uncoloured text and borders in the new Jitsi, kMeet and Nextcloud Talk connection forms, and use the configured app name instead of "Tymeslot" in their messages, the Talk conversation description and the new video-providers announcement
* Hide the "Or continue with" divider on the login and signup pages when no OAuth/social login provider is enabled, instead of showing it with nothing below it
* Fix the "Connect a calendar" button disappearing from Calendar settings when every connected calendar is paused — it now shows in the "Paused Calendars" header instead
* Fix dim, hard-to-read text in the "What's new" announcement window in dark mode
* Security: disabling a user account now also signs them out of every existing session and blocks Google/GitHub/OIDC sign-in — previously only password login was refused
* Pass the admin viewing the admin Users table to extra columns (optional `UserColumn.render/2`), so a column with its own interactive controls (e.g. a SaaS overlay's grant-plan toggle) can re-check that the viewer is still an admin on every action
* Add an admin-configurable site banner (Settings → General → Site banner): a dismissible bar at the top of the page with a short message (links and basic formatting allowed, translatable into every supported language), a background colour, and separate switches for the app, the sign-in pages and public booking pages — never shown inside an embedded booking page
* Add account deletion: a user can permanently delete their own account and all its data (including meeting history) from Profile settings → Danger zone, confirmed with their password (or their email for OAuth-only accounts); an admin's Delete in the Users table now does the same. The account is blocked and signed out at once, upcoming meetings are cancelled with attendees notified and paid bookings refunded, Google/Zoom access is revoked, and the data is deleted in the background (new column `users.deletion_requested_at`)
* Add a security audit log: sign-ins, sessions, lockouts, password changes, account deletions admin actions (disabling/enabling accounts, promoting/demoting admins) and payments (booking and subscription payments paid, failed or expired, refunds and chargebacks) are stored in the database and browsable under Administration → Audit log, filterable by event type or whole category, user and date range. App Settings → Audit log sets how long events are kept (default 90 days, env `AUDIT_LOG_RETENTION_DAYS`) and switches each category of events on or off; noisy categories (form validation, bot honeypots, sanitised input) are off by default
* Account deletion now also deletes the provider-side video rooms that outlive their meeting (Nextcloud Talk: calendar-grid event rooms and ended meetings' rooms) before the data is purged, and the dialog tells users with an Outlook or Teams integration that Microsoft consent has to be removed at myapps.microsoft.com
* Translate the answer choices of single/multi-select custom questions per locale (the choice's key stays the same), and fix custom question translations being dropped when a new meeting type is created
* Fix the public booking page freezing while a slow calendar server answers: the times of the selected day now load in the background like the month view, so clicks (e.g. choosing a meeting type) respond at once instead of waiting up to tens of seconds; the dev log also shows host, status and duration of slow HTTP requests
* Show events that the calendar marks as free (e.g. unanswered invitations) on the public calendar as a dashed "Not blocking" chip with its own legend entry — the time stays bookable and only the time range is shown, never a title
* Add Login / Get Started buttons (or a Dashboard link for a signed-in user) to the top bar of all public booking pages (booking flow, cancel/reschedule, poll voting) and the public calendar; the Get Started button is hidden when registration is disabled, and none are shown inside an embedded booking page
* Pre-fill the booking form with the signed-in visitor's own name and email when they book a meeting (a reschedule still uses the original booking's details; an anonymous visitor gets an empty form)
* Add optional phone and company fields to the onboarding profile step and to Profile settings (Contact details), and make the full name required in both; a signed-in visitor's phone and company now also pre-fill the booking form (new columns `profiles.phone`, `profiles.company`); on screens 1024px and wider the onboarding profile step lays its fields out in two columns so it fits a Full HD viewport without scrolling
* Fix the onboarding wizard for users in dark mode: the panel stayed white while the form fields and labels switched to dark-mode colours, leaving pale, unreadable text — the whole wizard now follows the appearance preference, and the greyed-out (locked) booking-link field, which was unreadable in dark mode everywhere, is legible again
* With the appearance set to "System", the page now follows later light/dark changes of the OS or browser instead of only the value at load
* Fix the dashboard tour's last step: the Skip, Back and Finish buttons no longer overflow the tooltip (the tooltip is wider and the buttons wrap on narrow viewports)
* Fix the dev-only onboarding preview (`/dev/onboarding`): finishing it or hitting an invalid step redirected to a non-existent `/debug/onboarding` and ended in a 404 error
* Fix the dashboard tour in dark mode: the step title, description and counter were dark-on-dark and invisible; the tooltip now has a dark surface with light text
* Fix the Profile settings page putting focus on "Confirm New Password" when it loads and pulling it back there after each autosave, and stop phone, company and display name saving after every typed word — they now save when you leave the field

[1.16.1.1]
* Fix an event spanning midnight only appearing in the dashboard calendar's agenda view under the day it starts — it now correctly appears under every day it covers, matching the day/week grid views

[1.15.4.1]
* Add per-locale translations for a meeting type's name/description, the profile's custom booking-page welcome text, and each custom question's label/help text/body — a booker sees the organizer's own wording in their own language when a translation exists, falling back to the original text otherwise, edited via a language tab-switcher in the dashboard; also translates the ~44 built-in validation messages shown on custom-question answers (e.g. "Text is required"), which were previously always in English regardless of the booker's locale
* Add an optional custom background image for the login page — drop a file at `priv/static/images/ui/backgrounds/login/LoginBackgroung.webp` to replace the default gradient, no admin UI or restart required
* Add an `:oban_additional_cron` extension point so a SaaS overlay can schedule its own periodic jobs without overwriting Core's crontab, plus an unconditional meeting-type slug reset and a non-seeding meeting-type listing for system-triggered cleanup (e.g. resetting a custom link when a paid plan lapses)

[1.11.2]
* Add Cloudflare Turnstile as a second bot-protection provider alongside Google reCAPTCHA v3, selected via a three-way Off/Google/Cloudflare admin switch per form (signup and booking independently) instead of the previous on/off toggle
* Fix SMTP email delivery over implicit TLS (port 465) — certificate verification options were built under the wrong Swoosh/gen_smtp config key and were silently ignored, causing every send to fail with `{:options, :incompatible, [verify: :verify_peer, cacerts: :undefined]}`
* Fix a newly registered user's onboarding pages always rendering light regardless of dark-mode preference, and complete dark-mode styling on the onboarding checklist widget, the dashboard overview's empty "Your day" state, and the Day/3-day/Week/Agenda calendar views

[1.11.1+1]
* [BREAKING] Rename outgoing webhook headers and User-Agent from Tymeslot to LockMyCal branding (`X-Tymeslot-Token` → `X-Lockmycal-Token`, `X-Tymeslot-Timestamp` → `X-Lockmycal-Timestamp`, `Tymeslot-Webhooks/1.0` → `Lockmycal-Webhooks/1.0`) — any existing webhook receiver checking the old header names must be updated
* Add a public-calendar setting to limit visible busy hours to a daily window (e.g. 07:00–18:00) and a toggle to hide historical events
* Sort the public calendar's daily "Busy" chips by time and show the hidden meetings' times on hover over "+x more"
* Add "Create new booking" and "Close" actions to the paid-booking confirmation page
* Fix unstyled action buttons (e.g. "Schedule Another Meeting", "Add to calendar") in the Rhythm booking theme
* Add a remediation link and a human-readable explanation to the restricted Stripe Connect status banner, translated into all locales
* Give the admin Users table icon-only row actions, real delete/disable/enable actions (disabling now blocks login), and a Country column sourced from the user's Stripe Connect account
* Add search to the admin Users table and an extension point for SaaS to register extra columns
* Respect the contacts_allowed assign on the profile settings "Collect contacts?" toggle, showing a locked notice instead of a working toggle when a SaaS overlay denies it, and reject the toggle server-side too if a stale render or a hand-crafted event tries to flip it while the plan denies it
* Share a LIKE-escaping helper across Users/Contacts/calendar-event search instead of three copy-pasted versions
* Fix a fail-open bug in the Integrations hub's Payments-tab plan gating: a checker crash or unrecognised error would have shown a misleading Pro badge instead of hiding the tab
* Fix colors broken since the rebrand rebase on Availability, Polls, Calendar Grid and the onboarding checklist
* Redesign the Availability page to match the rest of the dashboard, dropping its per-schedule colour-framed panel
* Raise the contrast of card borders and the day-of-week toggle's inactive state
* Switch the app's gray colour scale from zinc-* to neutral-*
* Install playwright-core globally in the dev image for ad hoc headless-browser checks
* Raise dev Postgres max_connections so `mix test` no longer fails alongside a running dev server
* Send reschedule emails and webhooks when an attendee moves a booking
* Correct translations across all five locale catalogues
* Reorganise the meeting type editor into tabs
* Redesign the Meeting Types add/edit form layout and unify its toggles onto the shared Enabled/Disabled control
* Stop the calendar-integration page description sitting beside its heading and drop the duplicate "Connect a calendar" button
* Keep the public calendar colour toggle pinned to the end of its row instead of wrapping under the description
* Hide events from a hidden calendar (whole integration or one calendar inside it) in the dashboard agenda and "Up next" strip, and update it immediately when toggled instead of after up to a minute
* Fix the Rhythm booking theme's week view sometimes hiding "tomorrow" as a bookable day
* Small rebase-followup cleanups (app-name string, German translation, README cleanup)
* Fix the calendar month view's all-day/multi-day bars rendering wider than their day column and bleeding into the next day
* Run the Docker dev container as a non-root user matching CI, instead of root silently skipping two filesystem-permission tests; pin the production image's app user to a stable UID/GID
* Complete German, French, Italian and Ukrainian translations for the admin Users delete/enable/disable actions
* Enforce Analytics Pro-gating with a real backend check instead of relying only on a UI assign
* Fix dashboard-created meeting update/delete attendee notifications never being scheduled, since the dispatcher only accepted integer event ids and meetings use UUID ids
* Notify the organizer by email (and raise an admin alert) when video room creation terminally fails, instead of only logging it
* Raise an admin alert when a Google/Outlook calendar webhook channel goes silent, instead of only logging it
* Fix organizer booking-lifecycle emails (confirmation, cancellation, reminder, reschedule, external-calendar-change) always sending in the app's default language instead of the organizer's own account locale
* Fix dozens of dashboard elements (admin settings/users, modal close button, sidebar nav, timezone picker, meeting/calendar/profile setting descriptions) staying light-background or unreadably dark in dark mode, and standardise the "explanatory text" colour used under a setting's heading
* Translate the shared Enabled/Disabled toggle's labels, previously hardcoded in English, into all five locales
* Add Umami analytics provider configuration via `UMAMI_WEBSITE_ID`/`UMAMI_SCRIPT_URL` env vars
* Fix the analytics CSP origin dropping non-default ports, silently blocking a self-hosted analytics instance not on port 80/443
* Add a light/dark/system appearance preference, with a topbar quick toggle and a fuller control on Profile Settings
* Extend dark-mode class coverage to the remaining dashboard pages (calendar grid, availability, automation, payments, polls, integrations, embed settings, theme customization, admin)
* Fix the dashboard agenda list rendering a midnight-crossing event twice (duplicate DOM id)
* Fix untranslated and stale/fuzzy strings in the "Video Setup Failed" organizer email


[1.11.1]
* Let video integrations reach a server on a private network


[1.11.0]
* Keep the poll attendee stable when voters register together
* Connect Nextcloud calendars on subdirectory installs
* caldav: Stop Nextcloud discovery silently querying the DAV service root
* Let admins set an email logo, brand name and accent colour
* Add meeting polls for group scheduling


[1.10.1]
* Reject login redirect targets containing tab or newline characters


[1.10.0]
* Stop retrying webhook deliveries the endpoint will always reject
* Keep signup usable when the verification email is rate limited
* Stop one visitor's rate limit from blocking everyone behind a proxy
* Set availability per meeting type with named schedules


[1.9.0+5]
* core: Fix custom background image/video upload in theme customization occasionally crashing the dashboard mid-upload
* core: Make the maximum upload size for theme background images/videos admin-configurable, autosaving on blur like the reCAPTCHA score fields (no Save button)
* core: Show the real reason a theme background upload failed instead of a generic "Upload failed" message
* core: Fix valid JPEG photos being rejected as "invalid image format" when their EXIF/XMP/ICC metadata pushed the dimension marker past what was being sniffed
* core: Lower the avatar upload limit to a fixed 300KB and fix the avatar file picker not clearing after a successful upload
* core: Preview the currently-set custom background image/video in the theme customization picker

[1.9.0+4]
* core: Require the calendar selected on the Meetings page's own quick-add dialog to belong to the organiser, not just on the calendar grid's version of it
* core: Restore the ad-hoc booking API's implicit reminder default instead of silently dropping it when the field is omitted
* core: Capture the attendee as a contact on a paid booking too, not just a free one
* core: Stop a stray quick-add form event delivered after the dialog has already closed from crashing the Meetings page
* core: Match a booker's email case-insensitively when looking up or deduplicating a contact
* core: Escape special characters typed into contact search instead of treating them as wildcards
* core: Always show the Contacts link in the dashboard sidebar, regardless of the auto-capture setting
* core: Stop a slow calendar write from freezing the whole Meetings page while it's in flight
* core: Reject an invalid reminder value converted from the calendar picker instead of saving it as-is
* core: Make contact search use a database index instead of scanning every contact on each keystroke
* core: Fix the calendar/Meetings "quick add" dialog rejecting its own default one-hour slot for about an hour before midnight

[1.9.0+3]
* core: Add a "pick from contacts" shortcut to the calendar's Quick add meeting dialog, and add the same dialog (with a matching "Add meeting" button) to the Meetings page, including full Event-mode support (connected calendar/video picker, recurrence, reminders, attendees) for parity with the calendar
* core: Support setting reminders on a meeting, not just a bare calendar event — synced to the connected calendar and folded into Tymeslot's own reminder email
* core: Add a Contacts page that automatically collects a booker's name, email, phone, and company from new public bookings, with a per-user "Collect contacts?" opt-in and edit/view-meetings/delete actions
* core: Clean up the meeting type add/edit form layout: drop the empty "Add Meeting Type" card, reorder the booking link/Meeting details/Done sections to read naturally, and restyle the Copy/Change link buttons
* core: Show meetings awaiting approval on the public calendar as a distinct "Pending approval" block, without ever exposing a title or attendee
* core: Open the meetings menu on the Awaiting Approval tab when the organiser has a meeting waiting on them
* core: Replace the calendar-sync-banner "Dismiss" button with an icon
* core: Redesign the event detail modal: collapsible description, calendar/video pickers narrowed to the event's current selection, reminders/recurrence/attendee-add made read-only, and a proper Cancel button next to Delete
* core: Stop a disabled toggle switch from still looking clickable on hover
* core: Fix the Calendar Settings toggle buttons (first day of week, time format, default view) rendering as oversized buttons instead of a compact toggle
* core: Let a dialog taller than the screen scroll internally instead of being cut off
* core: Recolour the "Quick add" event/meeting toggle to the current brand palette
* core: Put Cancel before Delete in the delete-event confirmation dialog
* core: Send a queued CalDAV retry to the meeting's own sub-calendar instead of always the connection's first one
* core: Flag a meeting whose calendar event repeatedly failed to sync, with a dismissable dashboard banner
* core: Highlight a meeting awaiting approval in the calendar grid instead of drawing it like a confirmed one
* core: Stop a synced CalDAV booking from rendering twice on the calendar grid
* core: Remove a cancelled meeting's cached calendar event immediately instead of waiting for the next sync
* core: Send calendar update/delete requests to the meeting's own sub-calendar instead of the connection's default one
* core: Cancel a meeting's pending calendar create/update job before deleting its event, closing a race that could write the event back after cancellation
* core: Give flash notifications a distinct colour and icon per kind (green check for success/info, amber triangle for warning, red X for error), instead of success confirmations showing the same orange as a warning

[1.9.0+2]
* core: Match the calendar's up-next-meeting banner colours to the dashboard's brand gradient and move it below the Calendar heading

[1.18.1]
* calendar: Stop a large CalDAV change from exhausting memory during sync
* calendar: Stop a large CalDAV calendar's first sync running out of memory
* Follow the browser's language instead of pinning the first one seen
* calendar: Delete a video room when its event is deleted elsewhere
* video: Stop leaving a stray video room behind on each link retry
* Stop offering subscribed calendars as a place to write
* ui: Let a dialog taller than the window scroll
* Send a quick-add guest one invitation, not two


[1.18.0]
* auth: Point social sign-in back to an account's own sign-in method
* themes: Show a keyboard focus ring on Rhythm location choices
* video: Send the notice when a reschedule repeats an earlier one
* emails: Show the number to call for phone meetings in emails
* booking: Include the join link when a booking is moved before its room exists
* video: Stop quick back-and-forth Teams reschedules losing the join link
* video: Keep a booking's calendar event when disconnecting Teams
* calendar: Delete or move a dashboard event's separate Teams meeting with it
* booking: Keep bookings working after their video integration is removed
* auth: Reject an SSO userinfo reply that is not a JSON object
* video: Stop Teams bookings confirming without their join link
* booking: Drop the Teams link when a booking moves off Teams
* calendar: Stop a Teams event on the grid appearing twice in Outlook
* video: Keep Teams bookings on their own links, times and event
* Improve the Ukrainian translations of the booking and sign-in pages
* booking: Show the correct month form in booking dates
* i18n: Say a reminder's lead time in the reader's language
* auth: Create a social account for a typed email only once it is confirmed
* emails: Point social accounts at their provider in the sign-up attempt email
* auth: Count an IPv6 client's whole /64 as one source for sign-in limits
* auth: Stop the social sign-up form revealing which addresses are registered
* auth: Stop sign-in revealing unverified accounts, and let owners reclaim them
* auth: Make every sign-up outcome spend the same verification allowance
* auth: Keep signed-in users off the login and sign-up screens after a patch
* emails: Give stacked blocks room to breathe
* calendar: Stop the grid showing a Meet join line the calendar lacks
* calendar: Clean up calendar event video rooms and inline Meet links
* calendar: Stop a booking's calendar event getting a second video room
* calendar: Stop moved events showing twice and misreporting failed moves
* auth: Ask for sign-in when the verify-email page has no account to resend for
* auth: Tighten social sign-in after review
* auth: Stop the sign-up form revealing which addresses are registered
* calendar: Stop Outlook sync crashing when Graph rejects a request
* calendar: Renew Outlook push subscriptions in place
* automation: Stop rescued jobs re-sending webhooks and chat posts
* emails: Stop a recovered background job re-sending its emails
* auth: Verify existing social accounts the provider vouches for
* auth: Stop the verification resend revealing or spamming addresses
* auth: Answer every password reset request the same way
* auth: Keep a password change from missing an email change made after the page loaded
* auth: Stop failed sign-ins from one address locking the owner out
* auth: Keep session tokens out of pages and end the old session on re-login
* auth: Disconnect open sessions when an account is deleted
* auth: Make the first-user admin bootstrap a one-way latch
* auth: Refuse admin role changes from anyone but a current admin
* auth: Resolve the LiveView client address the same way as HTTP requests
* auth: Require a verified email before social sign-in opens a session
* auth: Revoke pending reset and email change links when credentials change
* webhooks: Send meeting.rescheduled when a moved booking is re-approved
* polls: Stop a poll being confirmed onto time off
* video: Flag custom meeting links whose placeholder is invalid
* calendar: Add the video link to approved bookings' calendar entries (#133)
* auth: Stop OAuth sign-in from matching accounts by email
* webhooks: Refuse Telegram webhooks when the secret is empty
* payments: Stop resumed Stripe onboarding creating a second account
* booking: Stop guests answering invitations to past or cancelled meetings
* slack: Translate Slack connection messages
* calendar: Show Outlook Calendar as connected straight away
* auth: Show the right sign-up error in every language
* auth: Stop the sign-in form revealing which emails have accounts
* i18n: Say "Absagen" on the German cancel button (#131)
* i18n: Write the host's calendar entry in the host's language
* notifications: Send correct change emails for all-day and first edits
* calendar: Keep guest lists and replies intact when editing events
* caldav: Stop queued occurrence edits rewriting the whole series
* calendar: Keep attendee names when editing synced events
* calendar: End a recurring series on the date the organiser picked
* integrations: Say what is actually wrong with a rejected server URL
* availability: Stop offering a day that an override opened without hours
* calendar: Stop notifying the organiser about their own event edit
* calendar: Let an event colour reach a CalDAV server that has not synced yet
* emails: Keep the meeting join link out of the debug log
* calendar: Propose a usable range when quick add opens late or on a DST night
* timezones: Add French overseas territories and accent-insensitive search
* automation: Document the webhook delivery ID header
* calendar: Alert admins when calendar integration health degrades
* Let bookers choose where the meeting is held


[1.17.0]
* booking: Ask for a policy acknowledgement again when rescheduling
* booking: Stop offering times the host has already booked
* Stop "Schedule Another Meeting" moving a just-rescheduled booking
* Deliver email to SMTP relays that negotiate TLS 1.3
* scheduling: Keep a reschedule on the meeting type it booked
* scheduling: Carry a booking's answers into its reschedule
* Save the booker as an attendee on CalDAV calendars
* Create the video room when a calendar event's provider is chosen
* Stop CalDAV colour and offline changes being rejected
* Save edits to synced CalDAV events instead of reverting them
* Remove the dead join links left on a cancelled booking
* Apply booking changes made while a video account needed reconnecting
* Wait for the meeting's own video provider, not the slowest one
* Accept a MiroTalk server on a Docker service name
* Let an edited video server address be added again
* Accept http to servers on internal names once private addresses are allowed
* Stop slow video providers leaving duplicate meetings behind
* Attach the video link to calendar events using a templated custom link
* mailer: Let SMTP reach relays behind a middlebox that blocks TLS 1.3
* Offer in-person and online icons in the meeting type picker
* Connect Nextcloud Talk as a video provider
* Add Jitsi Meet as a video provider
* Add kMeet as a video provider


[1.16.1]
* themes: Drop the stray emoji from Quill's submit button (#125)
* Say the limit and the wait in hours or days when they run that long
* Remind a booking's guests again after it moves to a new time
* Show flash messages raised after the page has loaded
* Name the limit and wait time when signup, verification or booking is refused
* Stop a CalDAV series changing when one occurrence is edited
* Email every attendee when an event changes, not nobody
* Invite a booking's guests even when the participants were emailed
* Tell the host when a lapsed reschedule request cancels a booking
* Cancel the calendar entry when a rescheduled request is released
* Present a rescheduled booking awaiting approval as a reschedule
* Tell guests when a booking is rescheduled or cancelled
* Keep a re-sent booking invitation ahead of the entry it replaces
* Advance the ICS sequence when Tymeslot reschedules a booking
* Keep each day of a multi-day all-day event in sync
* dashboard: Open quick add at a valid slot late in the evening
* Start the booking instruction on its own line in Quill
* Keep every agenda day of an event that spans midnight in sync
* Write to the host in their own language in every booking email
* Remind guests about the meeting they were invited to


[1.16.0]
* [BREAKING] Move Zoom meetings when a booking is rescheduled by default: Add meeting:update:meeting to your Zoom app's scopes before upgrading. If your app cannot have it, set ZOOM_UPDATE_SCOPE_ENABLED=false, or users will be asked to reconnect Zoom for a permission the app cannot grant.
* Keep a paid meeting type's price when Stripe is unavailable
* Write grid events to the calendar they were placed on
* Keep every occurrence of a recurring CalDAV event
* Allow reconnecting a video integration with unreadable credentials
* Keep the whole event when an offline CalDAV change replays
* Delete calendar events on servers whose address carries a path
* Stop an all-day toggle moving a recurring event's end date
* End an Outlook recurring event on the date it was set to end
* Stop lazy-loaded hooks sharing one object across elements
* Show provider-specific server URL help for CalDAV connections
* Accept a server URL typed without https://
* Keep a new calendar event's identity from the create
* Bound time off dates and close days its windows fully cover
* Store integration server URLs exactly as typed
* Stop charging refused integration saves to the connection-test limit
* Let a calendar that recovers on its own take bookings again
* Check the host's calendar when a booking is rescheduled
* Keep outstanding refunds visible after Stripe is disconnected
* Show a booking page with no calendar as a notice, not a crash
* Keep attendee replies when a Google event is edited from the grid
* Ask Nextcloud users for an app password when connecting a calendar
* Stop MiroTalk claiming every meeting link on a "talk." host
* Keep a calendar event's attendees when it is edited from the grid
* End a recurrence UNTIL in the event's own timezone
* Report a Telegram disconnect on a deleted integration cleanly
* Identify a self-hosted integration by its full server address
* Flag a username taken in another case while it is typed
* Refuse a custom video link whose placeholder has an extra brace
* Rescue background jobs abandoned by a stopped node
* Classify a refused CalDAV password as a permanent failure
* Warn when a meeting type's target calendar goes read-only
* Only open the remove-integration dialog for the owner's integration
* Stop the provider picker subtitle inheriting the modal heading styles
* Refit a series' UNTIL when an event toggles all-day
* Notify attendees of calendar grid video changes
* Report a calendar-grid delete that succeeded as done
* Align the calendar webhook endpoints on failures and limits
* Drop cached availability when an event is created on the grid
* Fall back to the video room URL when a join link cannot be minted
* Remove a queued event delete from the calendar grid at once
* Keep reminders saved before the one-year limit editable
* Stop offering to delete one occurrence of a recurring event
* Report the refund correctly in the cancellation email
* Show the host when a cancelled booking still owes a refund
* Free the booking slot as soon as a calendar event is deleted
* Stop queueing calendar deletes and creates that can never sync
* Create the video room when picking a provider in the event editor
* Stop moving a calendar event from deleting it
* Say an edit will sync when the calendar could not be reached
* Keep attendees, reminders and repeats when editing calendar events
* Explain why a username can't be used before asking to confirm the change
* Reserve two offensive phrases that were never blocked as usernames
* Stop showing another account's booking count when removing a video integration
* Keep Telegram integrations when they are disconnected
* Keep setup checklist ticks made in another browser tab
* Reject malformed meeting ID placeholders in custom video links
* Offer the rest of the day when rescheduling at a booking limit
* Show password and email change errors next to the right field
* Save a real timezone when onboarding detects an unknown one
* Show the right outcome after paying for a booking
* Stop re-inviting an attendee whose address differs only in case
* Highlight the calendar an event is actually on when editing it
* End new all-day recurring events on the date picked
* Open hours that start inside a DST jump when the clocks land
* Warn when the calendar bookings go to has turned read-only
* Stop attendees from refunding bookings when cancelling
* Stop duplicating a long-named schedule from freezing the page
* Reject reminders more than a year ahead when adding them
* Warn when time off covers existing bookings
* Add time off so days away close without touching a calendar


[1.15.8]
* Keep the video link on calendar events when booking jobs overlap
* Only ask for a calendar reconnect when the provider refused it
* Book into a working calendar when the chosen one needs reconnecting
* Apply values from /app/data/.env in the Docker image
* Stop raising admin alerts for unknown LiveView events
* Rebuild database indexes an interrupted upgrade left invalid
* Allow booking a time freed by a host's reschedule request
* Ask owners to reconnect a calendar whose access was refused
* Tell calendar owners when Google or Outlook access was revoked
* Give Google Meet participants the plain meeting link


[1.15.7]
* [BREAKING] Read .env files identically at boot and in the release: .env values are no longer interpolated. ${VAR} and $(command) are kept as literal text, and a # not preceded by whitespace is part of an unquoted value. A .env that relied on either needs the final value written out.
* Tell users when a calendar has stopped syncing
* Show Telegram and Slack meeting times in the organiser's timezone
* Keep meeting links and query strings out of analytics
* Show the embed live preview in your language
* Mark booking pages opened from the embed preview as test mode
* Surface Google calendars whose event listing exceeds the page limit
* Stop deselected calendars hiding matches in search and reminders
* Email owners whenever a calendar or video connection needs reconnecting
* Keep the reconnection reason when calendar tokens refresh
* Show why a calendar needs reconnecting in the owner's language
* Read .env files safely with NUL bytes and Unicode spaces
* Email calendar owners when a calendar needs reconnecting
* Hide deselected calendars from search and desktop reminders
* Give intranet visitors their own rate limits
* Rebuild the calendar event index if an interrupted migration broke it
* Stop forcing HTTPS onto sibling subdomains by default
* Stop the Link embed preview from making real bookings
* Restore outbound HTTPS requests through a configured proxy


[1.15.6]
* Tell users when their Google account has no Google Calendar
* Stop discarding booking emails after two slow sends
* Stop silently dropping email when the SMTP relay is unreachable
* Email calendar owners when a calendar needs reconnecting
* Hide deselected calendars from search and desktop reminders
* Stop strict mail gateways deferring booking calendar invites


[1.15.5]
* Hide deselected calendars from the dashboard agenda
* Open the dashboard calendar on today in your own timezone
* Show the host's avatar in booking emails opened in Gmail
* Restore outbound HTTPS requests through a configured proxy


[1.15.4]
* Keep calendar deletion working when two calendars are removed at once
* Stop the popup and floating previews creating real bookings
* Restore a CalDAV booking the server no longer has
* Refuse a CalDAV connection that discovers no calendars
* Stop the booking rate limit refusing legitimate bookings
* Let the live preview complete a test booking
* Keep the organiser signed in when an embedded booking page loads
* Write through outbound calendar updates to the local event cache


[1.15.3]
* Sync every changed Google Calendar event, not just the first 250
* Connect to CalDAV servers that require digest authentication
* Keep calendar credentials out of crash reports
* Keep all-day and Google events visible in the fallback fetch
* Keep embed pages scrollable after reopening the booking popup


[1.15.2]
* Recognise Tymeslot's own bookings on CalDAV and Outlook calendars
* Keep non-ASCII values readable when importing them into .env
* Show the last sync time in calendar settings again
* Stop a CalDAV calendar silently syncing nothing
* Apply the intended retry schedule to calendar token refresh


[1.15.1]
* Clear the external-calendar warning once the calendar agrees
* Stop flagging meetings that have already happened as changed


[1.15.0]
* Stop an accented character in .env from crashing startup
* Recognise Tymeslot's own bookings on an Exchange calendar
* Apply availability breaks on the host's clock, not the booker's
* Recover a booking whose calendar copy was edited on the server
* Restore a CalDAV booking whose calendar event is missing
* Prompt a Zoom reconnect when rescheduling is not permitted
* Stop CalDAV bookings showing twice on the calendar and agenda
* Give the settings and onboarding timezone control accessible names
* Raise booking page button contrast to WCAG AA on every palette
* Give the booking page timezone controls accessible names
* Announce dropdowns as the menu or dialog they open
* Stop offering edit controls on read-only calendars
* Settle the merge fallout in aliases, migration and typing
* Keep the calendar scroll position when a sync starts
* Recover from a CalDAV server that refuses the sync method it advertises
* Close a DNS-rebinding hole in outbound requests
* Warn before a username change breaks shared links
* Surface a calendar that keeps failing to sync
* Stop reporting a working CalDAV calendar as unreachable
* Stop an expired meeting being rescheduled
* Announce the status switch state to assistive technology
* Apply maxlength and the other HTML constraints on form inputs
* Configure a Cloudron install from a file instead of the CLI
* Let visitors pause the sign-in background video
* Let visitors pause the booking page background video
* Write confirmed bookings to Exchange calendars
* Let hosts write their own booking page heading and welcome text
* Let hosts require their approval before a booking is confirmed


[1.14.0]
* Trip the calendar circuit breaker on repeated server errors
* Send mail through self-hosted SMTP relays
* Keep a switched-off setting's own toggle legible
* Connect a Microsoft Exchange calendar from the dashboard
* Let admins set a fallback language per surface
* Group admin settings into tabs
* Let hosts set how far apart booking times are offered


[1.13.2]
* Let bookers reach a month whose only free day is the first
* Tell bookers what to do when slots cannot be loaded
* Stop greying out booking days nobody checked the calendar for
* Follow the fifth redirect on a webhook delivery
* Offer the same scheduling policy presets everywhere
* Fall back to CalDAV discovery when a server answers 405
* Build the poll participant link from the matched username
* Cancel a profile photo the browser rejected as one too many
* Ignore booking query parameters of an unexpected shape
* Stop a password reset for an OAuth account crashing the page
* Invite the attendee when an ad-hoc meeting books a video room
* Send Slack notifications when Telegram is also connected


[1.13.1]
* Link the cancellation email to the host's booking page
* webhooks: Include the meeting's guests in the payload
* Open the schedule step on the next available day


[1.13.0]
* Let a password reset request use its full hourly allowance
* Count only admins who can actually sign in with a password
* Stop a replayed Connect webhook repeating its side effects
* Keep a reconnected integration out of the deletion sweep
* Show the booking and countdown messages in the visitor's language
* Validate every redirect hop when testing a webhook endpoint
* Stop a partial reminder send re-emailing the wrong recipient
* Refuse a booking when the host's schedule cannot be read
* Stop local errors opening the integration circuit breakers
* Stop an unexpected message taking the booking page down
* Put video provider calls behind their circuit breaker
* Stop the circuit breaker serialising the work it protects
* Refuse bookings for times the host's schedule never offered
* Stamp events and doc links with the running instance, not a fixed host
* Show one countdown for a meeting, not two that disagree
* Translate the booking step and readiness messages
* Answer the week strip's availability with the domain's rule
* Show throttled webhook edits and stop one user throttling all
* Refuse a conflicting integration reactivation instead of crashing
* Show failed webhook deliveries in the failure colour
* Validate every redirect hop when testing a custom video URL
* Disable a Telegram integration once the bot is blocked or kicked
* Stop dropping transactional emails during a mail outage
* Put paid bookings on the organiser's calendar
* Keep the Telegram bot token out of the request logs
* Resolve the meeting type when a booking link is opened directly
* Clear the file picker after a profile picture upload


[1.12.0]
* Stop a removed background video reporting a transcoding failure
* Settle a conflicting calendar event change without retrying
* Stop retrying Teams meetings an account cannot host
* Keep the profile photo upload from crashing the page
* Stop duplicate booking notifications when a video room arrives late
* Find CalDAV calendars on servers that answer under a subpath
* Stop rejecting valid email addresses on newer domain endings
* Stop a stray theme= parameter blocking public bookings
* Let owners test a booking from the theme preview links
* notifications: Raise meeting.created for bookings with a video room
* scheduling: Only carry theme= into locale redirects when previewing


[1.11.1]
* Let video integrations reach a server on a private network


[1.11.0]
* Keep the poll attendee stable when voters register together
* Connect Nextcloud calendars on subdirectory installs
* caldav: Stop Nextcloud discovery silently querying the DAV service root
* Let admins set an email logo, brand name and accent colour
* Add meeting polls for group scheduling


[1.10.1]
* Reject login redirect targets containing tab or newline characters


[1.10.0]
* Stop retrying webhook deliveries the endpoint will always reject
* Keep signup usable when the verification email is rate limited
* Stop one visitor's rate limit from blocking everyone behind a proxy
* Set availability per meeting type with named schedules


[1.9.0]
* Prevent calendar crash when opening an event with a reminder
* Stop alerting every cycle while a CalDAV server is down
* Flag a deleted booking calendar instead of retrying its webhook
* Keep the reconnect prompt until the owner reconnects
* Prevent availability page crash when a break is rejected
* Drop deleted events from the Up-next strip immediately
* Fall back to UTC when a profile has no timezone set
* Reject booking yourself as your own guest on the calendar
* Say which integration is missing on the Integrations badge
* Open the dashboard on your calendar


[1.8.0]
* Show password rule errors in the user's language
* Honour the classic Zoom write scope when cancelling meetings
* Show authentication and account messages in the user's language
* Correct German salutation capitalisation in email openings
* Report why a new password is rejected on the reset form
* Honour the private-network opt-out when saving a calendar server
* Paint the grid in the colour chosen for each calendar
* Raise contrast of calendar hour labels and grid lines
* Apply the clock preference across every dashboard surface
* Translate the calendar subscription name in the provider picker
* Show two lines of provider descriptions in the integration picker
* Delete provider video rooms after an integration is disconnected
* Delete provider video rooms after an integration is disconnected
* Translate the calendar colour names
* Paint each calendar colour the colour it is named after
* Show booking page times in the visitor's own language
* Preload the profile before rendering webhook-triggered emails
* Send Zoom meeting cancellations with the delete scope
* Hide the admin menu entry when the admin UI is disabled
* Apply the dashboard language switch across the whole page at once
* Translate dashboard sidebar extension labels
* Drop duration wording from the booking page intro
* Unify terminology across the German, French, Italian and Ukrainian catalogues
* Pluralise the duration and stats-period labels
* Correct verified translation defects across the catalogues
* Stop the booking page stacking duplicate prepositions
* Pluralise the reminder count in appointment emails
* Stop the German admin flashes misattributing a role change
* Warn French users that changing currency clears their prices
* Complete missing Ukrainian translations
* Localise payment timestamps and change summaries in emails
* Use Apple's own German labels in the iCloud setup steps
* Remove duplicated word from OAuth sign-up email errors
* Add Czech as a supported language
* Colour and show each calendar independently in the dashboard
* Reconcile cancelled meetings holding orphaned video rooms
* Offer to delete meeting rooms when disconnecting video
* Offer to delete meeting rooms when disconnecting video
* Record the video provider on meetings
* Let each connected calendar carry its own name and colour
* Let organisers choose a 12-hour or 24-hour clock
* Localise the strings the mail and integration work introduced
* Let hosts cap how many bookings they accept per day, week and month
* Add Ukrainian language support
* Add French and Italian language support
* Send account, auth and calendar emails in the recipient's language
* Add German translations across the app
* Add a language option to embed snippets
* Show the dashboard in each member's chosen language

[1.7.1]
* ui: Unify page headings, subsection labels and toggle styling across every dashboard page
* ui: Keep "Connect a video provider" reachable when integrations are paused
* ui: Fix cursor, focus-ring and border bugs in the shared button styles
* ui: Unify row and card appearance across Meeting Types, Integrations and Availability
* ui: Flatten the dashboard top navigation bar and fix the user-menu chevron animation
* core: Split the Integrations page back into standalone Calendars, Video and Payments pages
* auth: Replace the auth pages' video background with a gradient
* calendar: Compact the calendar month view and fix event pill overflow
* core: Fold Account Settings into Profile Settings
* ui: Fix a layout shift when navigating between pages with and without a scrollbar
* core: Move the Admin hub into the dashboard shell and give Users its own page
* dev: Bundle Chromium in the dev image for Wallaby E2E tests
* core: Move the horizontal Calendar button into the standard sidebar menu
* core: Let users assign a custom colour or rename a calendar integration
* core: Expand event colour palette to 11 semantic colours
* core: Add public read-only calendar page for organisers
* core: Add Czech as a supported UI language
* core: Let organizers require approval before confirming bookings
* core: Add phone and company fields to the booking form
* core: Stop birthday and anniversary reminders from blocking availability
* core: Read Endpoint URL and networking config from PHX_HOST/DATABASE_HOST in dev
* core: Add a local Mailpit container and dev docker-compose for bridge networking
* core: Fix scheduling-step layout jumps and spacing
* core: Publish the dev-facing port through PORT_PREFIX in docker-compose.yml
* core: Add an embedded PostgreSQL Docker image variant alongside the default split-container setup
* core: Make the application name configurable via APP_NAME
* core: Rebrand to LockMyCal with a new logo and orange colour scheme


[1.7.0]
* Keep a settled invoice from reverting to unpaid
* Stop CalDAV sync from deleting events the server withheld
* Correct booking times for 2026 Morocco and Alberta clock changes
* Repair CalDAV delta sync on servers that track changes by token
* Redact secret tokens from HTTP request logs
* Show the real reason when a calendar connection test fails
* Keep a calendar syncing when one event mixes date and date-time
* Show the attendee's message on dashboard meeting cards
* Keep recurring calendar events at their local time across DST
* Stop an all-day event from blocking all CalDAV sync
* Sync meeting reminders to the connected calendar event
* Record Stripe subscription invoices for customer retrieval
* Issue invoices for paid meeting bookings
* Subscribe to a published calendar feed by URL


[1.6.0]
* Handle CalDAV servers that answer conditional PUT with 409
* Stop a dead recipient address from blocking all outbound email
* Prevent CalDAV sync stalling permanently on an emptied calendar
* Let bookers retry after a failed security or rate-limit check
* Stop clobbering the test mailer adapter and treat blank EMAIL_ADAPTER as unset
* Run the mailer credential probe after the supervision tree starts
* Apply mail tracking at delivery time and fix inline logo Content-ID
* Stop the external-database compose file rebuilding over the published tag
* Make docker compose up work without cloning the repository
* Exclude read-only calendars from booking targets
* Keep the calendar event's video link when no meeting URL is returned
* Give connection-test rate limits a per-actor bucket
* Probe a MiroTalk server once per health check, not twice
* Keep a healthy integration healthy on its first probe
* Tell users an expired grant is expired, not undecryptable
* Store readable sync errors instead of inspected atoms
* Read the organiser from CalDAV events
* Give organisers and guests a video join link
* Align video provider capability keys so lookups are complete
* Stop attaching video rooms that cannot be joined
* Block private IPv6 addresses that URI parsing hid
* Greet users by name in emails, and escape it only once
* Stop booking page views from seeding meeting types
* Add SendGrid, Mailgun and AhaSend as email delivery options


[1.5.0]
* [BREAKING] Select an external database only when DATABASE_URL is remote: DATABASE_URL now selects an external database on the Docker image, where releases up to 1.4.4 ignored it and always used the bundled PostgreSQL. Only a URL naming a remote host changes behaviour, as a URL pointing at localhost still means the bundled database. Remove any stale DATABASE_URL before upgrading if you want to keep using the bundled database.
* Recover calendar sync when a provider event no longer exists
* Accept calendar event ids up to Google's documented maximum
* Keep database credentials out of the process list at startup
* Honour the sslmode parameter in DATABASE_URL
* Open the mobile dashboard sidebar
* Stop the setup checklist crushing its rows on narrow screens
* Name the calendar selection dialog by its heading alone
* Give footer column headings a sequential level
* ci: Align test DB pool with Oban concurrency
* calendar: Use provider event IDs for OAuth events
* Show the saved icon on meeting type cards
* Show the meeting type icon picker and mode-toggle icons
* Run PostgreSQL as its own container with the slim image
* Connect to an external PostgreSQL with DATABASE_URL and TLS


[1.4.4]
* Prevent availability crash on days the attendee's clocks change
* Allow the Stripe Connect onboarding redirect through the CSP
* Show the meeting description on meeting type cards


[1.4.3]
* Clear the reschedule-requested state once the attendee rebooks
* Remove calendar event and reminders when a reschedule is requested
* Show current city names for legacy timezone ids browsers report
* Show cancel and reschedule times in the attendee's timezone
* Accept valid timezones the format check wrongly rejected
* Retry the initial Outlook calendar sync after connecting


[1.4.2]


[1.4.1]
* Fix invisible outline button in onboarding calendar skip modal
* Show a branded 404 page for unknown routes


[1.4.0]
* Stop an empty CalDAV fetch from wrongly cancelling booked meetings
* Stop CalDAV colour change from reverting a server-side event edit
* Restore the setup step in the first-visit dashboard tour
* Make the booking calendar accessible to keyboard and screen readers
* Make modals and form errors accessible to keyboard and screen readers
* Preserve reschedule context on Choose New Time
* Return booker to schedule step when a slot is taken mid-submit
* Show progress during onboarding CalDAV calendar discovery
* Prevent calendar sync failure on very large initial imports
* Render rounded-token-full pills and badges as circles
* Gate admin feature announcements by signup date
* Show the Analytics Pro badge across all dashboard pages
* Redesign integrations with a provider picker and inline actions
* Decouple and make rotatable the data-at-rest encryption key
* Add calendar (.ics) download to the booking confirmation screen
* Colour calendar events from the dashboard agenda
* Nudge users to reconnect before skipping calendar in onboarding
* Open appointment details in a modal from the dashboard agenda
* Add a live "Your day" agenda to the dashboard overview
* Improve dashboard calendar readability and contrast
* Allow private-IP calendar, video and webhooks for self-hosters via env vars
* Highlight dashboard sidebar items that still need setup
* Redirect common login/signup URL aliases to the auth pages
* Add dismissible dashboard onboarding checklist
* Greet first-time users with "Welcome" on the dashboard
* Prompt to connect a calendar or video provider when none is set up
* Give sidebar setup indicators specific tooltips
* Autofocus the first field on auth pages


[1.3.0]
* Describe Calendar as a full calendar view in the onboarding tour
* Address the user as "you" in the Google sign-up confirmation
* Keep sidebar View Page button on one line to prevent overflow
* Stop all-day recurring events running past their end date
* Keep weekly repeat-on-weekday events at local time across DST
* Prevent booking-page previews from creating real bookings
* Correct CalDAV event times for unrecognised timezones
* Stop sending event-update emails to guests who declined
* Keep recurring events at their local time across DST changes
* Add live booking-page preview and theme step to onboarding
* Add Apple iCloud as a calendar provider
* Link to the WordPress.org plugin from embed settings
* Set a per-event colour in the calendar
* Add a mini-month date picker to the calendar toolbar
* Add an agenda view to the calendar
* Search your calendar events
* Keyboard shortcuts and a shortcuts help overlay for the calendar
* Quick-add events from a single line of text
* Create and edit recurring events
* Set event reminders that sync to your calendar provider
* Create and toggle all-day events in the calendar


[1.2.5]
* Accept wildcard TLS certificates from SMTP servers
* Show real meeting duration on Quill booking confirmation
* Let hosts attach files to a meeting type
* Enrich calendar events with conference links, language tags and free/busy status
* Publish a per-user free/busy calendar feed


[1.2.4]
* End live sessions immediately on logout and credential changes
* Return a real 404 for unknown URLs instead of redirecting home


[1.2.3]
* Prevent calendar crash on stale create-event integration change
* Prevent crash when a dashboard modal is confirmed twice
* Point WordPress users to the official plugin from the embed dashboard
* Show a notice instead of the homepage when an embed is blocked


[1.2.2]
* Give the analytics dashboard refresh visible feedback
* Add one-click Google Calendar connect to onboarding
* Refine and gate the booking analytics dashboard
* Exclude an organizer's own page visits from booking analytics


[1.2.1]
* Only require ANALYTICS_SALT_SECRET when booking analytics is enabled
* Stop button icons wrapping onto their own line
* Show hamburger nav on tablets, not just phones
* Match mobile nav menu structure to desktop
* Keep Quill booking content readable over image backgrounds
* Present booking-analytics visitors and conversion as estimates
* Suppress false booking-analytics anomaly alerts on small samples
* Stop capturing arbitrary query parameters in booking analytics
* Count booking-page visitors consistently when the client IP is unknown
* Trust forwarded IP headers only from known proxies on live connections
* Resolve the real client IP on live connections behind a proxy
* Prevent scheduling page crash when booking analytics is enabled
* Rate-limit booking confirmations per recipient to curb email abuse
* Block SSRF to internal hosts on CalDAV and video integrations
* Base booking-analytics conversion on actual converting visitors
* Count a booking-page visitor once across meeting types
* Show custom question answers in synced calendar events
* Add device-type breakdown to booking analytics
* Add admin toggle for booking analytics
* Make booking analytics opt-in via config flag
* Add analytics dashboard with sources and visits over time
* Persist UTM and tracking params on bookings end-to-end
* Log page views on public scheduling routes
* Persist UTM and tracking parameters on bookings
* Add analytics_events table for booking analytics


[1.2.0]
* Prevent booking page step labels from clipping in themes
* Accept text/plain handshake for calendar webhook validation
* Scroll to top reliably when navigating between pages
* Improve Quill booking card contrast on bright backgrounds
* Correct wrong English text in notification emails
* Correct English UI labels broken by a stale gettext merge
* Add config-driven Resources navigation menu
* Announce guest attendees and illustrate the booking-link modal
* Add booking-link share previews with organiser photo and details
* Add icons to the navigation menu and Features dropdown
* Scroll to top on internal link navigation site-wide
* Add Contact link to desktop site navigation
* Surface the guest limit in the meeting type editor
* Refine the guest booking flow across both themes
* Add private and direct booking links for meeting types
* Add guest attendees with email RSVP to bookings


[1.1.1]
* Stop Zoom video integration falsely reporting connection issues
* Create Google Meet links without a duplicate calendar event
* Prevent calendar webhook renewal crash on provider network errors
* Show try-later message when Stripe payment setup is temporarily unavailable


[1.1.0]
* [BREAKING] Correct Docker Compose env forwarding, volumes, and DB config: the embedded PostgreSQL volume is now named tymeslot_pg everywhere. Installs created before this change keep their data in the old volume (postgres_data, or <project>_postgres_data under Compose). Re-point the new mount at the old volume, or migrate the data into tymeslot_pg, before upgrading or the app starts against an empty database.
* Correct sender identity in host operational alert emails
* Treat unfinished Stripe onboarding as incomplete, not restricted
* Distinguish superseded from expired email verification links
* Stop duplicate emails when SMTP delivery is slow
* Keep verification and reset links valid after a resend
* Prevent Google Calendar sync crash on token-refresh failure
* Prevent admin-alert floods from repeated crashes and job failures
* Stop endless sync retries when a calendar is deleted on the provider side
* Auto-deselect Google calendars deleted on the provider side
* Make POSTGRES_PASSWORD optional when building the Docker image
* Prevent admin alert email floods when many jobs fail at once
* Keep password-reset and verification links out of job logs
* Reject theme video uploads when transcoding is unavailable
* Give dropdown dialogs accessible names
* Improve the dashboard tour on small screens
* Restore centred embed layout and make wide layout opt-in
* Translate booking flash messages
* Remove orphaned calendar events when booking sync fails
* Block private-network addresses in calendar server URLs
* Prevent a crash when dismissing an announcement twice
* Prevent locking yourself out of sign-in settings
* Validate custom question answers and bounds more strictly
* Improve paid booking reliability and payment errors
* Keep video meeting links in sync when bookings change
* Protect Slack webhook secrets and handle rate limits
* Update final onboarding step CTA to go to dashboard
* Keep dashboard sidebar fixed while only the content scrolls
* Preserve typed answers when navigating booking questions
* Reject overly long phone numbers in booking questions
* Keep Quill meeting-type cards a fixed size on hover and selection
* Size Quill meeting-type step to match the calendar step
* Remove clipped copy-link confirmation tooltip in dashboard sidebar
* Stop false type-change warning when editing a custom question
* Show embed live preview before embed domains are configured
* Copy booking link to clipboard on onboarding ready step
* Show Rhythm booking meeting-type descriptions on wide screens
* Show Quill booking meeting-type descriptions on wide screens
* Keep Quill booking time-slot buttons a uniform size
* Keep Quill booking time slots scrollable and free of overflow on small screens
* Reflow the Quill booking overview to fit and use space across screen sizes
* Prevent embedded booking from flickering and lurching on resize
* Apply all Stripe Connect account updates, not just the first
* Translate booker-facing booking and payment strings for de/fr/uk/it
* Show booker-facing emails in the recipient's language for de/fr/uk
* Show payment confirmation time in the attendee's timezone
* Let attendees return to booking after a cancelled payment
* Record disputes and refunds that arrive before payment confirmation
* Allow refunds when no reason is supplied
* Record Stripe charge id to enable refunds and disputes
* Fix checkout failure for paid bookings
* Show calendar reconnect prompt when event creation needs reauth
* Allow disconnecting a Slack OAuth integration
* Harden DashboardTour hook against scroll-jack and resize
* Persist dashboard tour completion across all dismissal paths
* Accept both yes and no as valid answers to a yes/no question
* Keep edit button visible on each custom-question list row
* Allow disabling password auth when no admin auth path is currently active
* Redirect non-admins to dashboard from admin page
* Show Baikal in the dashboard calendar integration list
* Remove jumping hover effect on action buttons
* Note acknowledgement not accepted in custom questions wizard
* Persist custom_fields through the meeting type save path
* Tighten Slack integration lifecycle and error reporting
* Correct Slack worker retry handling and rate-limit backoff
* Enforce refund window in cancel-meeting modal
* Correct refund and disconnect flow in host payments dashboard
* Show Pro and Stripe-required automation gates as user flashes
* Make Stripe Connect onboarding country configurable
* Block default currency change when pending payments exist
* Omit application_fee_amount when zero in Stripe Checkout sessions
* Prevent duplicate payment notification emails on Oban retry
* Return 503 when Stripe Connect webhook secret is missing
* Serialise charge.refunded webhook against in-app refunds
* Recover meeting state when paid checkout completes after expiry
* Close TOCTOU race when host disconnects Stripe with pending bookings
* Preserve booking payments past host deletion with nil attendee data
* Use integer arithmetic for payment money math
* Drop the literal "there" salutation on anonymous refund emails
* Show Zoom as an OAuth provider in the video integration list
* Fix pixelated Cloudron dashboard icon
* Repair Zoom meeting creation and harden the OAuth flow
* Show a loading spinner while opening Stripe Connect onboarding
* Auto-save meeting type edits as you change them
* Show price and custom-question count on meeting type cards
* Add slow fade animations to the dashboard tour
* Add a cooldown to the resend verification email button
* Announce custom questions, payments and Zoom in a what's-new modal
* Widen the Quill booking card on short, wide viewports
* Trim trailing empty weeks so the booking calendar fits
* Fit Quill and Rhythm booking pages to short viewports
* Add a payments dashboard for Stripe Connect, currency, and refunds
* Let hosts set a price on paid meeting types
* Toggle meeting payments from the admin settings page
* Show reconnect prompt for revoked video integrations
* Default new embed snippets to column layout
* Auto-fit embed height and add column layout option
* Add Reconnect button to pending Slack OAuth integrations
* Redesign custom questions step with in-brand answer controls
* Add post-onboarding dashboard tour
* Edit custom question options as individual fields
* Add SSO, reCAPTCHA, and admin alert toggles to admin settings
* Disable password-auth toggle when lockout would apply
* Show display name and booking slug in admin users table
* Protect admin panel from auth lockout and allow self-demotion
* Add admin control panel for self-hosted installs
* Group calendar providers into OAuth and CalDAV sections
* Show what's-new modal on dashboard for unseen feature announcements
* Show custom-field answers on host booking cards
* Include custom-field answers in ICS event description
* Include custom-field answers in appointment emails
* Show custom-field answers on Rhythm confirmation step
* Show custom-field answers on Quill confirmation step
* Confirm before clearing type-specific config on type change
* Add custom questions builder to meeting type form
* Persist custom-field snapshot and answers on booking submission
* Allow refreshing Slack channel list without reopening the form
* Notify Slack when meetings are booked, cancelled, or rescheduled
* Add Slack dashboard UI
* Add Baikal CalDAV calendar integration
* Add SlackDeliverySchema and slack_integration factory
* Add SlackIntegrationSchema with OAuth + webhook URL modes
* Add slack_deliveries table
* Add slack_integrations table
* Sync Zoom meetings when bookings are rescheduled or cancelled
* Cancel in-flight bookings when host disconnects Stripe
* Translate meeting payments into de/fr/it/uk
* Retain payment records past user deletion for tax compliance
* Email hosts when Stripe restricts their connected account
* Email hosts when Stripe opens a dispute on their booking
* Email attendees when their booking payment is refunded
* Add received-amount summary to organiser confirmation email
* Add receipt block to attendee confirmation email
* Add refunds context and host dashboard refund flow
* Retain payment_transactions past user deletion for tax compliance
* Remove Zoom integration automatically when uninstalled from Zoom
* Add Zoom as a video meeting provider


[1.0.5]
* Keep real-time calendar sync working for all connected calendars


[1.0.4]
* Restore clipped dropdown menus in the calendar grid toolbar
* Refresh Outlook calendars on demand with a rolling sync window
* Create Google Meet links inline with Google Calendar events


[1.0.3]
* Allow moving events between calendar integrations
* Prevent email header injection in subject lines
* Use a neutral greeting in transactional emails when no name is set
* Respect calendar selection in meeting picker and grid
* Show placeholder hints in form inputs
* Prevent CalDAV event delete and update from failing through circuit breaker
* Prevent Docker container from failing to restart with an existing volume
* Preserve special characters in meeting titles and labels


[1.0.2]
* Prevent duplicate booking invites from CalDAV servers (closes #41)


[1.0.1]
* Correct availability and slot ordering in the booking calendar
* Fix pixelated Cloudron dashboard icon


[1.0.0]


[0.100.16]
* Apply calendar deselection to CalDAV sync immediately
* Prevent calendar dashboard crash on 3+ overlapping all-day events
* Reject Google Calendar connections without write access
* Add custom colour picker for booking page palettes and backgrounds
* Add rotating file logs with sensitive-data redaction


[0.100.15]
* Translate reCAPTCHA notice text so it localises with the booking form
* Translate location placeholder in booking confirmation emails
* Fix invisible reply text in Thunderbird dark mode
* Restore CalDAV booking creation when discovery omits path


[0.100.14]
* Prevent CalDAV sync crash on all-day recurring events with EXDATEs
* Fix Nextcloud connection test failing for bare server URLs
* Auto-pause integrations stuck unhealthy past the configured cutoff


[0.100.13]
* Fix mailbox.org calendar discovery failing with unsupported provider error
* Prevent crash when clicking mailbox.org calendar provider
* Reject blank CalDAV credentials before connecting
* Keep Radicale auth failures flagged for reauth after 403 mapping change
* Auto-discover calendars during CalDAV onboarding
* Finish wiring mailbox.org through onboarding and runtime client paths
* Keep signup form responsive when the email field is missing
* Downgrade webhook redirects from POST to GET on 301/302/303
* Make Outlook delta sync resilient to expired and partial responses
* Align booking integration selection across meeting schemas
* Enable mailbox.org in the runtime calendar-provider toggle list
* Include mailbox.org in remaining CalDAV provider lists
* Stop duplicating attendee message in calendar events
* Hide task-only CalDAV calendars from event calendar pickers
* Prevent CalDAV permission errors from disconnecting calendars
* Pre-fill and lock server URL in mailbox.org calendar setup
* Add setup guide links to CalDAV provider configuration forms
* Notify users immediately when integration credentials become invalid
* Add mailbox.org as a CalDAV calendar provider
* Load environment variables from a .env file at boot


[0.100.12]
* Stop deleted CalDAV events from reappearing on refresh
* Keep the dashboard in sync after editing a calendar event
* Preserve CalDAV reauth flag when worker DB write fails
* Harden CalDAV reconnect flow
* Add 3-day view, swipe navigation, and responsive view demotion
* Flag CalDAV integrations needing reauth when sync hits 401
* Allow CalDAV credential rotation without recreating the integration
* Add OAuth reconnect button to calendar integration cards


[0.100.11]
* Prevent reCAPTCHA tokens being corrupted during form validation
* Derive with_retry_async's Task.await timeout from the retry budget
* Prevent search engines from indexing booking pages
* Surface timezone conversion failures from ensure_utc/1
* Surface OAuth token persistence failures loudly
* Deliver reschedule confirmation emails without pattern mismatch
* Warn when toggling a deleted calendar integration
* Show validation error when break end time precedes start time


[0.100.10]
* Count all concurrent failed login attempts toward account lockout
* Deliver attendee notifications on calendar event updates
* Prevent password-reset race that could overwrite a user's new password
* Prevent availability crash on DST-transition break times
* Collapse duplicate time slot labels on daylight-saving fall-back days
* Prevent CalDAV sync crash on malformed server responses
* Reject double-encoded open-redirect payloads
* Sign pagination cursors to prevent forged keyset offsets
* Block webhook delivery redirects to private networks
* Flag calendar integrations for reauth on decryption failure
* Preserve circuit-breaker state across worker restarts
* Keep account lockout counter in effect across restarts
* Block XSS via custom theme CSS breakout
* Require OAuth callback state to match session user
* Add Italian to supported booking and email languages


[0.100.9]
* Prevent uploaded non-media files from being served as HTML
* Restore Outlook calendar sync broken by Graph delta query rejection
* Prevent Nextcloud calendar setup failure on common hostnames
* Make Docker QuickStart succeed on Docker Desktop and bind-mounts
* Surface calendar refresh flashes that were silently dropped
* Surface booking and theme error flashes that were silently dropped
* Translate user-facing emails in French, German, and Ukrainian
* Warn in dashboard when a calendar integration has no calendars selected


[0.100.8]
* Prevent Docker first-run failure when PostgreSQL volume is root-owned
* Move video-room HTTP call outside DB transaction
* Invalidate availability cache after calendar sync persists
* Re-anchor UTC-midnight all-day events to owner tz in availability


[0.100.7]
* Prevent calendar grid crash on invalid user timezone
* Extend IDOR prevention to booking-form reschedule paths
* Prevent IDOR on meeting cancel/reschedule
* Emit METHOD:PUBLISH cancellations and harden ICS parameters
* Allow Stripe billing and checkout hosts in CSP form-action


[0.100.6]
* Suppress CalDAV/iMIP auto-scheduling for booked events
* Widen provider_calendar_events text columns to unbounded text
* Handle 3-tuple api_error in Outlook fallback sync sweep
* Deduplicate upsert batch by uid to prevent cardinality violation
* Accept calendar server URLs without an explicit scheme


[0.100.5]
* Expand recurring events in fresh-fetch availability path


[0.100.4]
* Use boolean stable field in CloudronVersions.json


[0.100.3]
* Add local icon path to manifest and use boolean stable field
* Populate empty 0.99.32 changelog and correct install URL


[0.100.2]
* Guard against nil calendar_paths in CalDAV queue wiring
* Retain etag in provider_metadata for CalDAV events
* Refresh scheduling page availability on calendar sync
* Make CalDAV full-fetch reconciliation atomic
* Centralise attendee notifications with change detection and ICS sequencing
* Handle move_event_async failures via offline queue
* Wire dashboard direct edit into CalDAV offline queue
* Wire dashboard create/delete into CalDAV offline queue
* Wire CalendarEventWorker into CalDAV offline queue
* CalDAV offline write queue
* Persist raw iCal body alongside parsed CalDAV events
* Re-probe CalDAV sync tier on forced full fetch
* Retry CalDAV conditional PUTs on transient errors
* CalDAV conflict-resolution policy on 412


[0.100.1]
* Address deep review findings for Outlook sync bootstrap refactor
* Handle DST transitions in convert_to_utc and expand TZID coverage
* Strip quoted TZID and normalise provider timezones (closes #38)
* Align booking conflict check with canonical blocking predicate
* Harden security module against edge-case bypasses
* Honour configured meeting type order on public booking page
* Normalise provider to atom in CalDAV health check client
* Stop entity-encoding plain-text fields in UniversalSanitizer
* Prevent Quick Actions card overflow on mobile dashboard
* Prevent logo and user dropdown overlap on mobile dashboard
* Hide back-to-website button on mobile auth pages


[0.100.0]
* Unbreak dashboard event creation async result path
* Redirect to /dashboard after onboarding and update e2e test for 7-step flow
* Wire password toggle hook on every auth form and give each a unique id
* Stop back-to-website button animating from inside auth card
* Style rhythm overview empty state
* Register grid-cols-14 and grid-cols-16 in Tailwind config
* Replace stale xs: breakpoint on automation card test buttons
* Use turquoise scale for reCAPTCHA notice links
* Harden 2026 email helpers against edge-case inputs
* Render quill time slots in a responsive grid
* Adapt rhythm schedule step to iframe height via flex
* Preserve unspecified calendar preference fields on partial upsert
* Re-centre dashboard calendar on current time after refresh
* Keep cancel button icon and label on one line
* Handle OAuth plain-map events in blocking? and convert_events_to_timezone
* Convert CalDAV EXDATE values to Date for cache storage
* Fold created_by_tymeslot into recreate_provider_calendar_events migration
* Normalize OAuth calendar events in EventsRead fetch path
* Replace fixed CSS values with fluid responsive equivalents
* Validate calendar discovery input before rate-limiting
* Add missing rate limits to calendar event creation and connection tests
* Bound health check job execution to prevent 10+ minute runs
* Redesign transactional and system emails for 2026
* Add periodic forced full re-sync for CalDAV integrations
* Fingerprint calendar events created by Tymeslot
* Add og-image.png social card for Open Graph meta tags
* Normalise all calendar providers through canonical CalendarEvent
* Add canonical CalendarEvent struct and provider_calendar_events table
* Enrich admin alerts with structured reason and PII scrubbing
* Add standardised admin alerts infrastructure


[0.99.40]
* Skip duplicate transaction on initial subscription invoice
* Remove dead pattern match branch in get_calendar_path
* Add missing user FK constraint to integration_health_states
* Add translations for attendee discard confirmation plural string
* Notify attendees when organiser updates event details
* Redesign onboarding with split-screen layout and individual scheduling steps
* Add 310 missing IANA TLDs to validation list
* Expand TLD list with 77 missing domain extensions
* Add TLD validation to domain validator
* Add TLD validation to email validator
* Add TLD list module with typo suggestions
* Add calendar invitation emails with attendee management
* Add TLD data file for domain ending validation
* Add multi-attendee support to calendar events
* Add ad-hoc meeting invitations from dashboard calendar
* Show empty state banner when no calendars are connected


[0.99.39]


[0.99.38]


[0.99.37]


[0.99.36]
* Preserve expanded recurring event occurrences in dedup
* Expand CalDAV recurring events for availability checking
* Centralise sync window and widen to 365 days back
* Scope detect_deletions to calendar path in multi-calendar CalDAV sync
* Harden calendar sync against webhook abuse, circuit breaker misfire, and duplicate notifications
* Correct action_button doc and info_box spec
* Harden calendar sync with batch webhooks, async CRUD, and race fixes
* Make profile timezone optional and rename video integration route
* Update booking, meeting list, and email UI
* Calendar grid inline editing and event management
* Update calendar webhook controllers
* Improve calendar sync workers
* Calendar API and backend sync improvements
* Add calendar grid UI with inline title editing
* Add calendar event sync engine
* Rename integration routes and add scheduling/calendar mode tab bar


[0.99.35]


[0.99.34]
* Derive display location from meeting fields in AppointmentBuilder
* Translate email location labels at render time per recipient locale
* Remove double scrollbar on time slots in constrained-height embeds
* Fix timezone dropdown height, width, and popular ordering
* Improve Quill overview duration card visibility and avatar alignment
* Prevent time slots from stretching when period has few slots
* I18n organizer reminder email and sanitize error output in CalDAV sync
* Replace TzExtra with curated continent city modules
* Multi-account integration support
* Multi-account integration support with per-account uniqueness


[0.99.33]
* Add tzdata and logger config to core runtime.exs
* Resolve WebSocket and OAuth failures on Cloudron deployment


[0.99.32]
* Resolve WebSocket and OAuth failures on Cloudron deployment
* themes: Scope container margin removal to modal embed mode only
* Harden availability edge cases — IDOR protection, cache invalidation, input guards
* Point tzdata at writable directory on Cloudron


[0.99.31]
* Clarify embed option descriptions for non-technical users
* Strip URL scheme/port/path in validate_domain/1
* Compute availability over full 42-day calendar display range
* Add missing "All rights reserved" to footer copyright
* Reject domains with protocols in embed domain validation
* Use Oban unique jobs for video transcoding and clean up variants on delete
* Split Night period into Early Morning and Late Night
* Split embed system into inline and modal modes
* Responsive video transcoding for uploaded backgrounds
* Add responsive video transcoding for uploaded backgrounds
* Add natural sort for meeting types in LocalizationHelpers


[0.99.30]
* Hide reCAPTCHA v3 badge per Google's terms
* Clean up iframe embedding security headers
* Use signed parent_origin for embed domain verification
* Redesign site_footer with supplemental_nav slot and column layout
* Add supplemental_nav slot to site_footer for injecting extra link columns


[0.99.29]
* Fix dashboard headline position on automation and profile pages
* Use check_all_queues in healthcheck to handle test mode
* Calendar integration edge cases — stale refs, timezone boundaries, error reporting
* Harden video integration edge cases — upsert on OAuth, unique constraint, graceful JSON handling
* Fix stale modal retry interval and digested filename error handler
* Harden embed edge cases found in audit
* Harden theme customisation — error tuples, browsing_type guard, image size limit
* Discard permanent meeting errors and log confirmation step failures
* Guard booking step against double-submission and direct URL access
* Restore keyboard focus visibility and consolidate Inter font import
* Add empty state to Rhythm overview and replace emoji icons in Quill meeting pages
* Improve theme error logging and plug exception handling
* Return error when all selected calendars fail in MultiCalendarFetch
* Harden auth security — email normalisation, token hashing, open redirect
* Harden infrastructure resilience and healthcheck
* Decrypt CalDAV credentials and forward custom video URL in health check
* Validate email format in PasswordReset.initiate_reset before anti-enumeration path
* Handle invalid_input map from authenticate_user in session controller
* Restore PubSub alias and canonical URL logic
* Pass parent-origin to embedded iframe URL
* Fall back to parent-origin param when referrer is stripped
* Normalise canonical URLs to strip query params and trailing slashes
* Add minimum height floor to inline embeds
* Handle three-tuple OAuth discovery error and move tidewave to saas
* Harden embed security, accessibility, and reliability
* Respect calendar event transparency (free/busy) across all providers
* Wire availability overrides into business hours calculation
* Config-driven dashboard extension system with parallel init and health check fixes
* Harden iframe embed security with wildcard domains and www auto-matching


[0.99.28]
* Use IANA zone1970.tab for primary timezone country assignment
* Correct iconUrl path in Cloudron manifests
* Compile app before asset setup in Dockerfiles
* Add session-free WebSocket for cross-origin embed iframes


[0.99.27]
* Replace cookie rewriting with signed token auth for embeds
* Add Tymeslot.Embed.Token for signed embed tokens


[0.99.26]
* Show booking validation errors per-field based on touched state


[0.99.25]


[0.99.24]
* Restrict valid? to country-based timezones to prevent UTC fallback showing first list entry
* Add features_url config and safelist display token classes
* Add GitHub release workflows and cliff.toml


[0.99.23]


[0.99.22]
* Show theme background in embedded Rhythm iframes
* Fix timezone dropdown positioning in embedded iframes
* Use fixed height on iframe wrapper instead of minHeight
* Display version number in site footer
* Rewrite session cookie to SameSite=None for cross-site iframes


[0.99.21]
* Correct build-docker.sh to operate within apps/tymeslot/


[0.99.20]
* Log Cloudron addon detection at startup
* Auto-detect Cloudron OIDC addon in runtime config
* Auto-detect Cloudron sendmail addon in runtime config
* Add CloudronConfig module for sendmail addon
* Declare OIDC addon in Cloudron manifest
* Declare sendmail addon in Cloudron manifest


[0.99.19]
* Stop sanitizing calendar integration passwords
* Prevent integration passwords from leaking into debug logs


[0.99.18]
* Allow localhost embedding in dev/test without configuring allowed domains
* Add iframe embedding, weekly calendar view, and shared scheduling init
* Add canonical URL tag and current_url/1 layout helper


[0.99.17]
* Address code review issues in Telegram integration
* Skip calendar deletion for unlinked meetings and fix resolve_client fallback
* Resolve confirmation page overflow in rhythm theme
* Pass attendee_locale through ContentBuilder for cancellation and reschedule emails
* Add Telegram notification integration
* Add Credo check for hand-rolled modal backdrops
* Shared-bot Telegram wizard with link expiry and reconnect
* Add Telegram notification integration


[0.99.16]
* Request meetings.space.created scope in Google Meet OAuth flow
* Use hexpm bookworm builder to satisfy cloudron/base OpenSSL 3.0
* Use debian:trixie-slim runtime to satisfy OpenSSL 3.4 requirement
* Add changelog link to site footer
* Add Docs link to site footer


[0.99.15]
* Move circuit breaker provider lookups from compile time to runtime
* Use consistent short labels for OAuth buttons on signup page
* Resolve flaky booking LiveView tests caused by config pollution
* Add update_subscription_status/3 callback to SubscriptionManager behaviour
* Fix reset-password token URI matching and update OAuth tests to use session
* Add is_verified flag to OAuth email-linking test
* Fill empty English translations for cancel/reschedule meeting strings
* Unwrap {state, timestamp} tuple in OAuth state session test
* Correct OAuth provider callback specs and remove dead clauses
* Add top-level aliases and remove TODO tag in OAuth state modules
* Harden OAuth SSO security and validation
* Accept string email_verified claim and document IdP switching
* Add defensive fallbacks and fix email verification default
* Use constant-time comparison and TTL for OAuth state
* Move OAuth registration data from URL params to session
* Add PASSWORD_AUTH_ENABLED flag to disable password-based auth


[0.99.14]
* Validate generic OAuth config and respect email_verified claim
* Dispatch meeting.rescheduled event in reschedule flow
* Add generic OAuth/OIDC provider support for SSO authentication
* Localize meeting cancel, reschedule, and cancel-confirmed pages


[0.99.13]
* Request calendar.events scope instead of broad calendar scope


[0.99.12]
* Gate OAuth registration paths on REGISTRATION_ENABLED flag
* Deduplicate registration-disabled message and gate complete-registration route
* Build embed.js via esbuild and bump version to 0.99.12
* Add REGISTRATION_ENABLED flag to gate all registration paths


[0.99.11]
* Name unused variable consistently in calendar workflows
* Add missing in_person provider icon assets
* Correct broken calendar link in meeting settings empty state
* Show inactive calendar integrations in meeting settings and fix persist fallback
* Add arrow_right icon to IconComponents


[0.99.10]
* health_check: Name unused pattern variables consistently
* onboarding: Persist browser-detected timezone to DB on mount
* health_check: Normalize orchestrate_health_check return to match spec
* test: Configure google_oauth state secret in VideoOAuthController test setup
* test: Fix FunctionClauseError in webhook worker timeout test


[0.99.9]
* dialyzer: Suppress false-positive call_without_opaque in gettext.ex
* Harden worker logging — safe error formatting, early discard on missing meeting
* payments: Expire superseded Stripe checkout sessions on retry
* db: Cascade delete meetings when user is deleted
* structured_logger: Suppress unused variable warning in log_by_phase/2
* Add ObanLogger telemetry handler for job process tracing
* Add LoggerMetadataHook for LiveView process tracing
* webhooks: Store Stripe event payload and auto-nullify after 30 days


[0.99.8]
* logging: Raise Credo checks to :high and clear all remaining Core violations (Phase 5)
* logging: Fix workers and web layer Logger violations (Phase 3)
* logging: Fix infrastructure and security domain Logger violations (Phase 3)
* logging: Fix integrations domain Logger violations (Phase 3, integrations)
* logging: Fix payments domain Logger violations (Phase 3, payments)
* logging: Fix auth domain Logger violations (Phase 3, auth)
* credo: Detect lazy Logger fn forms; disable MissedMetadataKeyInLoggerConfig
* credo: Add logger hygiene checks (Phase 2)
* logging: Structured logging infrastructure (Phase 1)


[0.99.7]
* Correctly preserve meeting duration through the booking flow (closes #17)
* video-oauth: Use provider-specific state secrets for Google Meet and Teams


[0.99.6]


[0.99.5]
* caldav: Correct false-vs-nil conflation and remove dead rescue
* caldav: Harden percent-encoding fix for reliability and completeness
* caldav: Handle percent-encoded calendar IDs in validation and matching
* dev: Increase Oban stage_interval to avoid crash during code reload
* tests: Resolve ambiguous selectors and async assertion in VideoSettingsComponentTest
* dialyzer: Suppress false contract_with_opaque on valid_ids/0
* caldav: Suppress retries on guessed discovery path
* ui: Move integration card action buttons next to toggle on desktop
* ui: Improve theme customization toolbar and background tabs on mobile
* ui: Improve webhook card layout on mobile
* ui: Improve calendar integration card layout on mobile
* ui: Improve video integration card and modal layout on mobile
* ui: Fix mobile layout of meeting type cards and edit form header
* ui: Raise mobile sidebar z-index above top navigation bar
* Per-attendee locale for email rendering
* emails: Add plain-text fallbacks to all email templates
* caldav: Add RFC 4791 discovery fallback, Zimbra CRUD coverage, and XML parser improvements
* ui: Add mobile timeline view for availability grid
* video: Add edit modal, show URLs in list, fix test connection
* ui: Close mobile sidebar on nav link selection
* ui: Add logo to mobile sidebar header next to close button


[0.99.4]
* Add zimbra to calendar provider DB constraint
* Convert non-standard HTTP methods to uppercase strings for Finch
* Left-align body text in integration unhealthy email
* config: Fix coveralls terminal_options key and set file_column_width to 125
* lint: Resolve Credo warnings in CalDAV base and discovery service
* Migrate CalDAV header handling to Req map format
* Add Zimbra to DiscoveryService routing and path_utils
* Snooze CalendarEventWorker for circuit recovery on :circuit_open
* Return error when all calendar fetches fail in range queries
* Register Zimbra provider in registry and add discovery case
* Resolve Credo warnings for unused var names and thin wrapper
* Correct country mapping for Asia/Yangon to Myanmar
* Sort availability slots chronologically within each time period
* deploy: Make asset builds hermetic in all Dockerfiles


[0.99.3]
* Restore visibility and center "Forgot password?" link on login


[0.99.2]
* Build JS bundles in Docker and make asset build hermetic
* railway: Replace shell script with railpack.json start command
* railway: Use absolute path for release binary in railway_start.sh
* railway: Use shell script for start cmd to avoid eval escaping issues
* railway: Move nixpacks.toml to apps/tymeslot (Railway root directory)


[0.99.1]
* microsoft-oauth: Surface admin consent required error to users
* docker: Remove redundant hex/rebar install step
* csp: Resolve Credo warnings in SecurityHeadersPlug
* csp: Add analytics provider origins to script-src
* test: Rename bare _ to _i in for comprehension to satisfy Credo consistency check
* test: Pre-exhaust rate limit via API to prevent clear_all race in embed settings test
* Resolve compiler warnings and Credo violations
* Language switcher clickaway and lazy hook destroy collision
* Guard against nil duration in maybe_assign_meeting_type
* Address code review issues in embed test suite
* Fix scheduling box overflow when time slots list is too long
* Remove duplicate Tymeslot suffix from page titles
* Harden password DoS guard and sanitize backslash redirects
* auth: Add regenerate_verification_token/1 to Auth context
* Add integration_unhealthy email template tests and fix strong tag rendering
* Persist integration health state and notify users on sustained failures
* Add page titles and meta descriptions to auth pages


[0.99.0]
* Fix failing and flaky tests across multiple test modules
* Remove unused LinkAccessPolicy alias in theme integration test
* Move @moduletag after use in all test modules
* Add @moduletag :security to rate_limiter_dashboard_test
* Add @moduletag taxonomy tags to test modules
* Remove @moduletag inserted inside alias blocks in test files
* Sort Tymeslot.Security aliases alphabetically in auth modules
* Rename anonymous _ variables to _error in input validators test
* Remove unreachable list guard in booking orchestrator
* Remove unreachable catch-all clause in theme customization rate limiter
* Correct @spec type for assign_form_errors from list() to map()
* Remove unreachable nil guard in assign_theme_customization_data
* Address review issues in webhook input validation sanitization
* Add UniversalSanitizer to webhook name and URL validation
* Update rhythm theme confirmation page layout and label
* Fix reCAPTCHA v3 hook so booking form token is populated on submit
* Fix honeypot visibility and recaptcha disclaimer layout in booking themes
* Fix logger_json formatter config for OTP 28
* Remove unreachable clause in sanitize_css_class
* Fix type errors in proxy verifier
* test: Make availability fetch truly synchronous in tests
* Align credo version and resolve sitemap routing issues
* Handle HTML entity escaping in theme readiness error test
* Resolve compiler warnings and test failures
* Exclude Credo checks from compilation paths
* Add Phoenix.CodeReloader listener to mix.exs
* Resolve Credo warnings for nested module aliases and line length
* Handle empty string meeting_id in custom video provider
* Add rate limiting to all dashboard write operations
* Implement structured logging with logger_json
* security: Add spam protection to booking forms with honeypot and reCAPTCHA v3
* security: Add rate limiting to theme customization and meeting operations
* Add Zimbra calendar provider with SSRF protection
* Fix proxy authentication and add verification tools


[0.98.1]
* security: Sanitize CSS class names in icon rendering to prevent XSS
* coverage: Replace .coveralls.exs with coveralls.json for proper exclusions
* brand: Add w-auto to logo images to preserve dimensions while fixing layout
* brand: Add explicit dimensions to logo images to prevent layout shift
* rhythm theme: Improve language dropdown text contrast
* test: Correct error message expectation in ErrorHandler test
* test: Use dynamic future date in quill meeting tests
* quill: Improve step navigation contrast on bright backgrounds
* scheduling: Hide language dropdown after slide 1 and fix layout jump
* Correct CAStore API usage in SMTP config
* Remove unreachable pattern match in meeting settings card
* onboarding: Remove unreachable pattern match clauses
* Correct CAStore API usage in mailer health check
* quill: Add --flag-height design token for consistency


[0.98.0]
* Add HTTP proxy environment variable support
* Add HTTP proxy configuration support
* Add Zimbra calendar provider support


[0.97.1]
* Resize caldav, local, and custom icons to match other provider icons
* Remove vertical jump on brand-card hover
* Remove false positive logging in universal sanitizer
* Restore spillover functionality in availability tests
* Sync video circuit breaker providers with actual video integrations
* Add fallback for unsupported Flagpack country codes in timezone selector
* Correctly parse castore CA certificates from PEM file
* Improve CalDAV server detection accuracy and legacy support
* Correct Docker build context and use committed dependency versions
* Correct Microsoft OAuth redirect URIs and add missing details in .env.example
* Correct Google Meet provider name from google_calendar to google_meet
* Support slug format in duration formatting
* Move custom_input_mode_helper.ex to match module name convention
* Use consistent provider icons across all integration UI surfaces
* Update test assertions after component and locale changes
* Update locale plug tests after adding French support
* Auto-detect CalDAV server types for proper authentication
* Add missing translation strings to English locale
* Add configurable LISTEN_IP with robust validation
* Enhance custom video provider support
* Add template variable support for custom video URLs with fragment validation
* Add complete French (fr) translation support


[0.96.2]
* Align postgrex version in core mix.lock with root
* Use dynamic app URL instead of hardcoded domain in onboarding
* Use standard ports for Docker URL generation in production
* Add nil-safe fallbacks to pricing and fix zero-duration parsing


[0.96.1]
* Explicitly block auth routes in robots.txt
* Remove unused variable in ensure_calendar_list
* Resolve code quality warnings
* Improve code readability and performance in core
* Resolve race condition and improve queue monitoring infrastructure
* Remove Core deps symlink and align dependency versions
* Enable standalone core deployment and make Stripe optional
* Skip empty blur validation and extract avatar modal
* Unify form input spacing for leading icons and prefixes
* Streamline video room creation and theme tests
* Import flash_group in auth layout
* embed: Build safe URLs and restore overflow
* Stop video playback on slow connections
* Address compilation and credo warnings
* utils: Improve ISO 8601 duration parsing correctness
* Guard dashboard hook config
* Suppress log noise during initial booking form render
* Make language switcher click-away handler conditional
* Add missing track_form_change event handler in VideoSettingsComponent
* Resolve UndefinedFunctionError in MiroTalk provider HTTP client
* Improve MiroTalk provider robustness and fix test assertions
* Improve video room worker robustness and fix test assertions
* Allow localhost and 127.0.0.1 for embedding in development
* Restore QuillVideo hook and add theme hook tests
* Remove unused scheduling.css from tailwind build config
* quill: Prevent duration tag from stretching with multi-line titles
* Ensure custom credo checks are loaded in core app
* Expand Stripe webhook handling and idempotency
* Enhance payment reconciliation and subscription persistence reliability
* Improve payment system robustness and configuration consistency
* Resolve credo and logger warnings in admin alerts and email service
* Resolve credo issues and warnings across umbrella project
* Resolve unreachable patterns and high complexity in webhook handlers
* Allow websocket connections in dev by updating CSP
* Improve citation box rotation and mobile responsiveness
* Add missing @spec type specifications and fix linting issues
* Improve locale persistence and navigation on theme booking pages
* Replace String.to_atom/1 with String.to_existing_atom/1 in validation helpers
* test: Improve test robustness, performance, and utility nil-safety
* security: Implement recursive sanitization and deterministic errors
* Handle DST gaps in business hours and harden OAuth token validation
* availability: Respect business days in fallback logic and harden tests
* email-testing: Update testers with missing fields for template rendering
* email: Add comprehensive SMTP configuration and startup validation
* Add external database support for Docker deployment
* Restore marketing screenshots and update gitignore rules
* Generate video poster frames from video start
* Add video background posters separate from thumbnails
* theme: Add video poster for presets
* booking: Suppress validation errors until form interaction
* Enhance datetime utils with more robust parsing and testing
* Add user agent to LiveView connect_info and improve extraction
* Add generic analytics provider support with Umami implementation
* Dynamic robots.txt serving based on deployment type
* Implement sitemap.xml for SaaS marketing site
* Suppress LiveView disconnect toast during OAuth navigation
* Implement secure-by-default embedding and dashboard preview
* Implement video room recovery mechanism and enhanced retry logic
* Implement feature gating for automations and SaaS subscription integration
* Cache branding status and refresh on subscription changes
* Add show_branding feature flag to control "Powered by Tymeslot" visibility
* Rename notification settings to automation and add bolt icon
* Implement integrated branding footer for scheduling pages
* Background subscription event processing and cancellation persistence
* Replace native confirmation with themed modal for subscription cancellation
* Add support for customer.updated webhook event
* Enhance subscription flow with race condition handling and trialing support
* Add Stripe billing portal support and subscription status views
* Implement Phase 4 - payment system feature completeness
* Make add break form collapsible in availability settings
* Implement robust Stripe webhook handlers for disputes, refunds, and trials
* Implement SaaS-specific payment email templates and tests
* Log unhandled stripe events and update env template
* Enhance embed widget security and customization
* Implement drag-and-drop reordering for meeting types
* Implement Stripe payments and SaaS subscription management
* Enhance SaaS email infrastructure and dashboard integration
* Add default reminder settings and transition to slug-based meeting types
* Customizable multiple reminders per appointment type
* integrations: Harden Outlook availability and Microsoft Teams OAuth
* integrations: Enhance Microsoft (Outlook and Teams) integration
* security: Enhance input validation, rate limiting, and security test coverage
* availability: Implement duration-aware gap logic and ETS caching
* layout: Implement generic theme extension system for UI injection
* auth: Harden session security and improve OAuth resilience
* security: Add support for wildcard domain prefixes in allowed embed domains
* emails: Redesign templates with modern design tokens and Inter font
* ui: Overhaul dashboard UI with token-based design system and glassmorphism
* Enhance availability engine and scheduling logic
* webhooks: Enhance security, delivery resilience, and atomic failure tracking
* i18n: Implement comprehensive localization and internationalization support
* integrations: Implement pluggable calendar architecture and improve worker resilience
* Add internationalization (i18n) support for booking pages
* Implement booking widget embedding with security controls
* Complete app redesign and modernization
* Refactor webhooks into a unified notifications dashboard

