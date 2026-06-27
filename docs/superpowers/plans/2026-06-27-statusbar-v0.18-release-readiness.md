# Release readiness (v0.18) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax. Tento cyklus je obsahový (markdown + 2 string edity + CI) → bez TDD; každý task = vytvoř soubor(y) + ověř + commit.

**Goal:** Připravit repo na veřejné zveřejnění jako open-source dev nástroj (LICENSE, README+screenshoty, CHANGELOG/CONTRIBUTING/SECURITY, CI, hygiena, kódové odkazy → AgentBar).

**Architecture:** Přidání standardních repo-souborů + GitHub Actions CI + úprava 2 kódových konstant (název repa) a verze. Go-live (rename/public/release) je samostatný uživatelem spouštěný krok mimo tento plán.

**Tech Stack:** Markdown, GitHub Actions (macOS runner), Swift 6 / SwiftPM, ImageRenderer (screenshoty).

## Global Constraints

- Cíl = veřejný zdrojákový repo pro vývojáře; BEZ notarizace/$99.
- Licence MIT, držitel „Rivalio s.r.o.", rok 2026.
- Rename repa → `Rivalio-s-r-o/AgentBar` (kódové odkazy už teď; samotný `gh repo rename` až v C4).
- Bundle id `cz.rivalio.statusbar` ZACHOVÁN; app = AgentBar; macOS 14+; Swift 6, `swift build` 0 warningů, `swift test` 177.
- Soukromí (do README/SECURITY): čte `~/.claude`/`~/.codex` read-only; nemá vlastní login; OAuth tokeny JEN in-memory, NIKDY nelogovány; jediný zápis = řízený refresh tokenu (round-trip validovaný, atomický).
- Verze → 0.18.0.
- Agent NESPOUŠTÍ go-live akce (rename/public/release) — to je C4 s uživatelem.

---

### Task 1: LICENSE + .gitignore + RELEASING.md

**Files:**
- Create: `LICENSE`
- Modify: `.gitignore`
- Modify: `RELEASING.md`

- [ ] **Step 1: `LICENSE`** — standardní MIT text, hlavička `Copyright (c) 2026 Rivalio s.r.o.`

- [ ] **Step 2: `.gitignore`** — nahraď řádek `.claude/settings.local.json` za `.claude/`; přidej `AgentBar.app/`.

- [ ] **Step 3: `RELEASING.md`** — aktualizuj na AgentBar; postup: bump verze → commit → merge → `gh repo rename` (jednorázově) → `git tag vX.Y.Z` → `gh release create`.

- [ ] **Step 4: Ověř + commit**

```bash
git add LICENSE .gitignore RELEASING.md
git commit -m "chore: MIT LICENSE + .gitignore (.claude/, app) + RELEASING.md"
```

---

### Task 2: Kódové odkazy → AgentBar + verze 0.18.0

**Files:**
- Modify: `Sources/StatusBarApp/UpdateCoordinator.swift:15`
- Modify: `Sources/StatusBarApp/AppDelegate.swift:47`
- Modify: `Resources/Info.plist:16,18`

- [ ] **Step 1:** `UpdateCoordinator.swift:15` — `let repo = "StatusBar"` → `let repo = "AgentBar"`.
- [ ] **Step 2:** `AppDelegate.swift:47` — `"github.com/Rivalio-s-r-o/StatusBar"` → `"github.com/Rivalio-s-r-o/AgentBar"`.
- [ ] **Step 3:** `Info.plist` — obě `<string>0.17.0</string>` → `<string>0.18.0</string>`.
- [ ] **Step 4: Build + test**

Run: `swift build 2>&1 | tail -2 && swift test 2>&1 | tail -1`
Expected: Build complete (0 warnings); 177 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusBarApp/UpdateCoordinator.swift Sources/StatusBarApp/AppDelegate.swift Resources/Info.plist
git commit -m "chore: odkazy na repo → AgentBar + verze 0.18.0"
```

---

### Task 3: Screenshoty (ImageRenderer mockupy)

**Files:**
- Create: `docs/images/popover.png`
- Create: `docs/images/settings.png`

- [ ] **Step 1:** Standalone SwiftUI skript do scratchpadu, který vyrenderuje (a) popover (karta Claude + Codex, Timeline bary, „rezerva" pace, dnes/30d) a (b) Nastavení (sekce Připojení + Lišta + náhled). `MainActor.assumeIsolated`, `swiftc -O`, `ImageRenderer(scale:3).nsImage` → PNG. Dark mode.
- [ ] **Step 2:** Vyrenderuj → ulož do `docs/images/popover.png` a `docs/images/settings.png`; vizuálně zkontroluj (Read PNG).
- [ ] **Step 3: Commit**

```bash
mkdir -p docs/images
git add docs/images/popover.png docs/images/settings.png
git commit -m "docs: screenshoty (ImageRenderer mockupy) pro README"
```

---

### Task 4: README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1:** Napiš README dle spec §2.1 (anglicky — open-source publikum): Titul+tagline, badge (CI/MIT), screenshoty (`docs/images/…`), What it is, Features, Requirements (macOS 14+, Claude Code/Codex CLI prerekvizita, Xcode 16/Swift 6 pro build), Install from source (`git clone`, volitelně `./scripts/setup-signing.sh`, `./scripts/make-app.sh`, přesun do /Applications), How it works & privacy, Settings, Contributing, License. Odkazy na repo = `Rivalio-s-r-o/AgentBar`.
- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README (přehled, instalace ze zdrojáku, soukromí)"
```

---

### Task 5: CHANGELOG + CONTRIBUTING + SECURITY

**Files:**
- Create: `CHANGELOG.md`
- Create: `CONTRIBUTING.md`
- Create: `SECURITY.md`

- [ ] **Step 1: `CHANGELOG.md`** — keep-a-changelog; `## [0.18.0] - 2026-06-27` (Added: souhrn funkcí) + `### Earlier development` stručné milníky (v0.6 živé Claude API, v0.7 Codex+styly, v0.9 lokalizace+30d, v0.10 burn-rate+updater, v0.12 Timeline, v0.14 baterie, v0.15 AgentBar identita, v0.16 přehlednější popover, v0.17 adaptivní providery). Bez tokenů/citlivostí.
- [ ] **Step 2: `CONTRIBUTING.md`** — build (`swift build`), test (`swift test` — VŽDY celý suite, `--filter` nematchne volné `@Test func`), 0 warningů/Swift 6, jak postavit app (`scripts/make-app.sh`), kde jsou spec+plán docs (`docs/superpowers/`).
- [ ] **Step 3: `SECURITY.md`** — nahlášení (GitHub Security Advisory / e-mail), privacy model (read-only creds, žádné logování tokenů, řízený write-back round-trip+atomicky), supported versions.
- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md CONTRIBUTING.md SECURITY.md
git commit -m "docs: CHANGELOG + CONTRIBUTING + SECURITY"
```

---

### Task 6: CI — GitHub Actions

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1:** Workflow:
```yaml
name: CI
on:
  push:
    branches: [ main ]
  pull_request:
jobs:
  build-test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode 16
        run: sudo xcode-select -s /Applications/Xcode_16.app
      - name: Swift version
        run: swift --version
      - name: Build
        run: swift build
      - name: Test
        run: swift test
```
(Pozn.: cesta `/Applications/Xcode_16.app` — ověřit dostupný název na macos-15 runneru; pokud jiný, upravit, nebo použít `maxim-lobanov/setup-xcode@v1` s `xcode-version: '16'`. Reálný běh = až po pushi.)
- [ ] **Step 2: YAML lint (lokálně, best-effort)**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('YAML OK')"`
Expected: `YAML OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: GitHub Actions (swift build + test na macOS)"
```

---

## Self-Review

**Spec coverage:** LICENSE→T1; .gitignore→T1; RELEASING→T1; kódové odkazy+verze→T2; screenshoty→T3; README→T4; CHANGELOG/CONTRIBUTING/SECURITY→T5; CI→T6. C4 go-live = mimo plán (spec §4). ✅
**Placeholder scan:** CI Xcode cesta a YAML lint mají poznámku „ověřit při běhu" — to NENÍ placeholder, ale reálné omezení (CI běh nelze lokálně plně ověřit); workflow je kompletní.
**Konzistence:** název repa `Rivalio-s-r-o/AgentBar` jednotně (T2 kód, T4 README, T1 RELEASING); verze 0.18.0 (T2); copyright „Rivalio s.r.o." (T1).
