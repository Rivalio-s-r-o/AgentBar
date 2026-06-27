# Changelog

All notable changes to AgentBar are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/).

## [0.18.0] - 2026-06-27

First public release.

### Added
- Live usage limits for Claude Code (5-hour session + weekly) and Codex
  (session + weekly) with reset countdowns.
- Burn-rate projection with a two-tone "remaining" bar and an early-exhaustion
  warning ("limit in ~Xh").
- Pace indicator (`buffer` / `over`) per window.
- Today's cost and a rolling 30-day token + dollar estimate.
- Adaptive providers: connected tools shown as cards, others as a small
  "not connected" ghost row; a welcome screen when nothing is connected.
- Configurable menu bar (indicator styles, provider selection, watched window).
- Opt-in low-limit notifications.
- System / Light / Dark appearance; English / Czech localization.
- Battery-aware refresh (`NSBackgroundActivityScheduler`, display-sleep aware).
- Notify-only update check against GitHub Releases.

### Earlier development

A condensed history of the pre-release milestones:

- **0.17** — adaptive providers + onboarding (ghost rows, welcome screen,
  Connections settings).
- **0.16** — clearer popover (a single pace signal per window).
- **0.15** — renamed to **AgentBar**; app icon, About panel, accessibility.
- **0.14** — battery & performance (background scheduler, sleep/wake handling).
- **0.12** — Timeline redesign + System-Settings-style preferences.
- **0.11** — graphical burn-rate bar in the menu bar.
- **0.10** — burn-rate estimate + update check.
- **0.9** — richer popover, 30-day cost, English / Czech localization.
- **0.7–0.8** — live Codex limits, configurable bar styles, real-cost fix,
  live-data reliability (throttle / backoff / token refresh).
- **0.6** — live Claude usage API.
- **0.1–0.5** — initial menu bar app, today's cost, alerts, settings, lazy scan.

[0.18.0]: https://github.com/Rivalio-s-r-o/AgentBar/releases/tag/v0.18.0
