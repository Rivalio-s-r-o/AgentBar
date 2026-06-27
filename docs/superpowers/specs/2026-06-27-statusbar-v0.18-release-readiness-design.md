# StatusBar v0.18 — Release readiness (proud C1 + C3)

- **Datum:** 2026-06-27
- **Stav:** Návrh odsouhlasen uživatelem (cíl: open-source repo pro vývojáře; MIT; rename→AgentBar; CI ano; copyright „Rivalio s.r.o."; screenshoty = ImageRenderer mockupy zatím).
- **Motivace:** Proud C z optimalizačního auditu — připravit repo na veřejné zveřejnění jako open-source dev nástroj. Tento cyklus pokrývá **C1 (obsah & hygiena)** + **C3 (CI)**. **C4 (go-live: rename, zveřejnit, první release)** je samostatný uživatelem spouštěný krok (dokumentovaný na konci, NEimplementuje se zde). **C2 (notarizovaná binárka) ODPADÁ** — vývojáři si app staví sami (`make-app.sh`, `.build` existuje → překlady fungují).
- **Verze:** 0.18.0. Větev `feat/v0.18-release-readiness`. Baseline 177 testů.

## 1. Rozhodnutí (odsouhlasena)
- Cíl = **veřejný zdrojákový repo pro vývojáře** (build-it-yourself), BEZ Developer ID/notarizace ($99).
- **Rename** GitHub repa `Rivalio-s-r-o/StatusBar` → `Rivalio-s-r-o/AgentBar` (provede se v C4; kódové odkazy se ale upraví už teď).
- Licence **MIT**, držitel **„Rivalio s.r.o."**, rok 2026.
- **CI ano** (GitHub Actions: `swift build` + `swift test`).
- Screenshoty = vygenerované ImageRenderer mockupy (nahraditelné reálnými).
- Bundle id `cz.rivalio.statusbar` ZACHOVÁN; název aplikace AgentBar beze změny.

## 2. Deliverables (nové soubory + úpravy)

| Soubor | Akce | Obsah |
|---|---|---|
| `LICENSE` | nový | MIT, „Copyright (c) 2026 Rivalio s.r.o." (standardní text) |
| `README.md` | nový | viz §2.1 |
| `CHANGELOG.md` | nový | keep-a-changelog; `v0.18.0` = první veřejný release (souhrn funkcí); stručné dřívější milníky |
| `CONTRIBUTING.md` | nový | build/test/styl/jak postavit app/kde jsou spec+plán docs |
| `SECURITY.md` | nový | nahlášení zranitelnosti + privacy model (read-only creds, žádné logování tokenů, řízený write-back) |
| `.github/workflows/ci.yml` | nový | macOS runner: `swift build` + `swift test` na push/PR (viz §2.3) |
| `docs/images/popover.png`, `docs/images/settings.png` | nové | ImageRenderer mockupy pro README |
| `.gitignore` | úprava | `.claude/settings.local.json` → celé `.claude/`; přidat `AgentBar.app/` |
| `Sources/StatusBarApp/UpdateCoordinator.swift:15` | úprava | `let repo = "StatusBar"` → `"AgentBar"` |
| `Sources/StatusBarApp/AppDelegate.swift:47` | úprava | `github.com/Rivalio-s-r-o/StatusBar` → `…/AgentBar` |
| `RELEASING.md` | úprava | aktualizovat na AgentBar + postup `gh release create` |
| `Resources/Info.plist` | úprava | verze 0.18.0 |

### 2.1 README.md — struktura
1. **Titul + tagline** + badge (CI status, MIT licence). Tagline: „Native macOS menu bar app tracking your Claude Code & Codex usage and limits."
2. **Screenshoty** (popover + Nastavení z `docs/images/`).
3. **What it is** — krátký odstavec.
4. **Features** — bullet list (živé limity Claude+Codex, burn-rate projekce, dvoubarevný bar, 30denní cena, notifikace, styly lišty, vzhled, lokalizace en/cs, baterie-aware).
5. **Requirements** — macOS 14+; **a alespoň jeden z: Claude Code CLI nebo Codex CLI nainstalovaný a přihlášený** (AgentBar čte jejich data — viz onboarding z v0.17). Build: Xcode 16 / Swift 6.
6. **Install (from source)** — `git clone`; volitelně `./scripts/setup-signing.sh` (stabilní podpis, bez opakovaných keychain promptů); `./scripts/make-app.sh`; přesunout `AgentBar.app` do `/Applications`.
7. **How it works & privacy** — čte `~/.claude`/`~/.codex` **read-only**; **nemá vlastní login** (přihlášení obstarají oficiální CLI); OAuth tokeny JEN in-memory, **NIKDY se nelogují/neukládají jinam**; jediný zápis = řízený refresh tokenu (round-trip validovaný, atomický).
8. **Settings** — stručný přehled (lišta styl/providery/okno, vzhled, notifikace, aktualizace, připojení).
9. **Contributing** (odkaz) + **License** (MIT).

### 2.2 CHANGELOG.md
Keep-a-changelog. `## [0.18.0] — 2026-06-27` jako první veřejné vydání se souhrnem hlavních funkcí (sekce Added). Volitelně `### Development history` se stručnými milníky (v0.6 živé Claude API, v0.7 Codex+styly, v0.9 lokalizace+30d, v0.10 burn-rate+updater, v0.12 Timeline redesign, v0.14 baterie, v0.15 AgentBar identita, v0.16 přehlednější popover, v0.17 adaptivní providery). Bez tokenů/citlivých dat.

### 2.3 CI — `.github/workflows/ci.yml`
- Runner **macos-15** (má Xcode 16 / Swift 6; projekt = swift-tools 6.0, `.macOS(.v14)`).
- Kroky: `actions/checkout@v4` → `swift build` → `swift test`.
- Pojistka Xcode: krok `sudo xcselect` na Xcode 16 NEBO `maxim-lobanov/setup-xcode@v1` s `xcode-version: '16.x'` (ověřit dostupnost na runneru v plan-forge/při běhu).
- Testy jsou CI-safe (Kit pure, `ConnectivityTests` injektuje temp home — nezávisí na reálném `~/.claude`/`~/.codex`).

## 3. Verifikace a meze
- **Auto:** `swift build` 0 warningů, `swift test` 177 (kódová změna = jen 2 string konstanty repa → žádný nový test; existující projdou). `plutil -lint` na nezměněných `.strings` netřeba.
- **Markdown/obsah:** vizuální kontrola README (odkazy na obrázky sedí na `docs/images/`), LICENSE platný MIT text, CHANGELOG/CONTRIBUTING/SECURITY bez placeholderů.
- **CI:** workflow se reálně ověří až po pushi/zveřejnění (na privátním repu Actions běží taky — lze ověřit před go-live, pokud uživatel chce). Lokálně ověřit YAML lint.
- **Screenshoty:** ImageRenderer PNG (popover + Nastavení) — vizuální kontrola jako u předchozích mockupů.
- **GAP (uživatel):** finální vzhled README na GitHubu; rozhodnutí o C4 spouštěčích.

## 4. C4 — Go-live (samostatný krok, NEimplementuje se zde; uživatelem spouštěné)
Pořadí s pojistkami:
1. **Sken git historie na tajemství** — `git log -p | grep -iE "token|secret|bearer|sk-|password"` (a podobné) → potvrdit, že žádný commit neobsahuje OAuth token/credential. **Pokud něco → STOP**, neřešit zveřejnění, řešit historii.
2. `gh repo rename AgentBar -R Rivalio-s-r-o/StatusBar` + `gh repo edit -R Rivalio-s-r-o/AgentBar --description "..."`.
3. `gh repo edit -R Rivalio-s-r-o/AgentBar --visibility public --accept-visibility-change-consequences`.
4. `git tag v0.18.0 && git push origin v0.18.0` + `gh release create v0.18.0 --title "AgentBar v0.18.0" --notes-file <CHANGELOG sekce>` → rozsvítí updater.
- **Vše nevratné / uživatelovo rozhodnutí** — agent NEzveřejní autonomně (security constraint).

## 5. Rizika
- **R1 (střední) — tajemství v git historii po zveřejnění:** mitigace = povinný sken historie (C4 krok 1) PŘED `--visibility public`. Tokeny dle architektury nikdy nebyly logovány/commitovány, ale ověřit.
- **R2 (nízké) — CI Xcode verze:** macos-15 runner musí mít Swift 6; mitigace = explicitní výběr Xcode 16 v workflow + ověření prvního běhu.
- **R3 (nízké) — rename rozbije updater na privátním repu:** updater na privátním repu stejně dostává 404 (tiše „unknown"); po renamu+zveřejnění+releasu začne fungovat. Kódová konstanta `repo="AgentBar"` musí sedět s reálným názvem po renamu (C4 krok 2). GitHub navíc staré URL přesměruje.
- **R4 (nízké) — `.gitignore` `.claude/`:** v repu nic z `.claude/` není commitnuté (ověřeno) → bezpečné.
- **R5 (nízké) — screenshoty mock vs realita:** mockupy jsou reprezentativní; uživatel je může kdykoli nahradit reálnými (README na ně odkazuje cestou, ne obsahem).
