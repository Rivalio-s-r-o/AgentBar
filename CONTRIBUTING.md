# Contributing to AgentBar

Thanks for your interest! Issues and pull requests are welcome.

## Project layout

- `Sources/StatusBarKit/` — pure, testable logic (parsing, formatting,
  projections). No AppKit / UI.
- `Sources/StatusBarApp/` — the app itself (menu bar, popover, settings, live
  data sources, system access).
- `Tests/StatusBarKitTests/` — Swift Testing tests for the Kit.
- `docs/superpowers/` — design specs and implementation plans, one per feature.
- `scripts/` — `make-app.sh` (build the `.app`), `setup-signing.sh` (stable
  self-signed cert), `make-icon.sh`.

## Building & testing

Requires **Xcode 16** (Swift 6).

```bash
swift build      # must be warning-free
swift test       # run the full suite
```

> Tests are free `@Test` functions, so `swift test --filter <name>` matches
> nothing — always run the full suite.

Build a runnable app bundle:

```bash
./scripts/make-app.sh        # produces AgentBar.app
```

## Conventions

- Swift 6 strict concurrency; the build must stay **warning-free**.
- Keep `StatusBarKit` pure and unit-tested; keep system access in the app target.
- User-facing strings are localized in both `en` and `cs`
  (`Localizable.strings` in each target); parity tests enforce that the key sets
  match.
- Never log raw conversation contents or OAuth tokens.

## Workflow

Each feature gets a short design spec and an implementation plan under
`docs/superpowers/`. For a larger change, opening an issue to discuss first is
appreciated.
