# Security Policy

We take the security of LockMyCal seriously. Because LockMyCal can be
self-hosted, a responsibly disclosed vulnerability lets us ship a fix before it
can be exploited in the wild. Thank you for helping keep users safe.

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues,
discussions, or pull requests.** A public report exposes every self-hosted
instance until a fix is released.

Instead, report privately through either channel:

- **GitHub Private Vulnerability Reporting** (preferred) — open the
  [Security tab](https://github.com/lockmycal/lockmycal/security) and click
  **"Report a vulnerability"**. This creates a private advisory visible only to
  the maintainers.
- **Contact form** — [www.lockmycal.com/en/contact](https://www.lockmycal.com/en/contact).
  Mark your message as a security report and we will follow up privately.

Please include as much of the following as possible:

- The type of issue (e.g. authentication bypass, injection, SSRF, privilege
  escalation, data exposure).
- The affected version or commit, and your deployment type (self-hosted Docker
  or the LockMyCal cloud).
- Step-by-step instructions to reproduce, including any proof-of-concept.
- The impact — what an attacker could achieve.

## What to expect

- **Acknowledgement** within **72 hours**.
- An initial assessment and severity rating within **7 days**.
- Regular updates as we work on a fix, and coordination with you on a
  disclosure timeline (we aim to release a patch within **90 days**, sooner for
  actively exploited issues).
- **Credit** in the release notes and security advisory for the fix, unless you
  prefer to remain anonymous.

## Supported versions

Security fixes are released against the **latest version** in this
repository. Self-hosters should stay current to receive security updates. The
[LockMyCal cloud](https://lockmycal.app) always runs a supported version.

## Scope

In scope: the LockMyCal codebase in this repository and the LockMyCal cloud
service.

Out of scope: vulnerabilities in third-party dependencies (report those upstream,
though we appreciate a heads-up), issues requiring physical access to a
self-hoster's server, and findings that depend on a misconfigured deployment
rather than a flaw in LockMyCal itself.

LockMyCal is based on [Tymeslot](https://github.com/tymeslot/tymeslot). If a
vulnerability also affects upstream Tymeslot, we will coordinate with its
maintainers, or you may report it to them directly under their own policy.

## Safe harbour

We will not pursue or support legal action against researchers who act in good
faith, follow this policy, avoid privacy violations and service disruption, and
give us reasonable time to remediate before any public disclosure.
