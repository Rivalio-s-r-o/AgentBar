# Security Policy

## Reporting a vulnerability

Please report security issues privately via GitHub's **Report a vulnerability**
(Security → Advisories) on this repository, or by email to the maintainers.
Please do not open a public issue for security-sensitive reports.

We will acknowledge your report and keep you updated on the fix.

## Supported versions

AgentBar is pre-1.0; only the latest release receives fixes.

## How AgentBar handles your data

AgentBar is designed to be minimal and read-only:

- It reads `~/.claude` and `~/.codex` **read-only** — it never modifies your
  conversations or settings.
- **OAuth tokens (access / refresh) and account IDs stay in memory only.** They
  are never logged, persisted elsewhere, or sent to any third party.
- Raw conversation contents are never logged — only aggregate numbers (tokens,
  costs, percentages).
- Network requests go only to Anthropic's and OpenAI's own usage endpoints, and
  anonymously to the GitHub Releases API for the update check.
- The only write-back is a **token refresh** when a token has expired: the new
  token is validated by a round-trip parse and written atomically back to the
  original store (Keychain / `auth.json`), mirroring what the official CLIs do.
