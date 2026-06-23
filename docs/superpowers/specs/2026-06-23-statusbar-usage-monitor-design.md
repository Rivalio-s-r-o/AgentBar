# StatusBar — menu bar monitor spotřeby pro Claude Code, Codex a OpenAI API

- **Datum:** 2026-06-23
- **Stav:** Návrh odsouhlasen, připraveno k tvorbě implementačního plánu
- **Repo:** `Rivalio-s-r-o/StatusBar` (privátní; před vydáním zvážit veřejné)
- **Platforma:** macOS (nativní Swift + SwiftUI)

## 1. Přehled

StatusBar je nativní macOS menu bar aplikace, která na první pohled ukazuje
**spotřebu a limity** AI nástrojů, které vývojář používá každý den:
**Claude Code**, **Codex** a **OpenAI API**. Cílem je odpovědět na otázku
„kolik mi zbývá do limitu?" bez otevírání terminálu nebo dashboardu.

Inspirace: [CodexBar](https://github.com/steipete/CodexBar) (široký monitor
spotřeby/limitů napříč 50+ poskytovateli) a
[claude-status](https://github.com/gmr/claude-status) (sledování stavu
běžících sessions). StatusBar si bere filozofii „spotřeba & limity" z CodexBaru,
ale **záměrně se zužuje na Claude + Codex/OpenAI** — méně rozptýlení, čistší a
udržitelnější produkt.

### Cíle
- Glanceable přehled limitů Claude Code a Codexu přímo v liště.
- Detailní panel s 5h/týdenními okny, dnešními tokeny a útratou.
- Lokální zpracování dat — žádný cloud, soukromí na prvním místě.
- Nízká spotřeba paměti i baterie (nativní app, ne Electron).

### Ne-cíle (mimo rozsah)
- Sledování stavu běžících sessions (active/idle/waiting) — to dělá claude-status.
- Podpora dalších poskytovatelů (Cursor, Gemini, Copilot, …). Architektura to
  ale nesmí znemožnit do budoucna.
- Cross-platform (Windows/Linux). Pouze macOS.
- Úpravy nebo řízení samotných CLI nástrojů.

## 2. Hlavní uživatelský scénář

Vývojář pracuje celý den s Claude Code a Codexem. V liště pořád vidí dvě
procenta (🟠 Claude / 🟢 Codex). Když se některé blíží stropu, barva čísla
zoranžoví/zčervená; volitelně přijde notifikace. Kliknutím rozbalí panel s
detaily — kolik zbývá v 5h okně, kdy se resetuje týdenní limit, kolik tokenů
dnes profrčel a jaká je odhadovaná/skutečná útrata.

## 3. Architektura

Systém je rozdělen na malé, samostatně pochopitelné a testovatelné jednotky.
Komunikují přes jasně definovaná rozhraní; vnitřek každé jednotky lze měnit bez
dopadu na ostatní.

### 3.1 Komponenty

| Komponenta | Co dělá | Závisí na |
|---|---|---|
| `UsageProvider` (protokol) | Společné rozhraní pro každý zdroj dat. Metoda typu `fetch() async -> Result<ProviderUsage, ProviderError>`. | — |
| `ClaudeCodeCollector` | Získá spotřebu a limity Claude Code. | `~/.claude`, příp. OAuth usage endpoint |
| `CodexCollector` | Získá spotřebu a limity Codexu. | `~/.codex` |
| `OpenAIAPICollector` | Získá útratu přes OpenAI Admin API. | Admin API klíč (Keychain) |
| `UsageStore` | Jediný in-memory zdroj pravdy o aktuálním stavu všech poskytovatelů. Publikuje změny do UI (ObservableObject). | model `ProviderUsage` |
| `RefreshScheduler` | Periodicky spouští collectory, ošetřuje timeouty a chyby, řídí interval. | collectory, `UsageStore` |
| `PricingEstimator` | Přepočítává tokeny → odhad ceny podle tabulky cen modelů. | tabulka cen |
| `MenuBarController` | Spravuje `NSStatusItem`, vykresluje glanceable widget podle zvoleného stylu. | `UsageStore`, `Settings` |
| `PopoverView` (SwiftUI) | Detailní panel (layout A) + obrazovka Nastavení. | `UsageStore`, `Settings` |
| `NotificationManager` | Prahové alerty při blížícím se limitu. | `UsageStore`, `Settings` |
| `Settings` | Trvalá konfigurace (UserDefaults + Keychain pro klíče). | — |

### 3.2 Princip izolace
Každý collector zná jen svůj zdroj a produkuje sjednocený `ProviderUsage`.
Přidání/odebrání poskytovatele je lokální změna jednoho modulu. UI a scheduler
pracují jen s protokolem `UsageProvider` a modelem `ProviderUsage`, nikdy ne s
detaily konkrétního zdroje.

## 4. Zdroje dat

> ⚠️ **Hlavní technické riziko.** Přesné mechanismy je nutné ověřit
> **jako úplně první krok implementace** (spike). Architektura je na detailech
> nezávislá (collectory jsou vyměnitelné), ale konkrétní implementace ano.
> Níže je současný stav poznání, ne potvrzená fakta.

### 4.1 Claude Code (CLI předplatné, plán Max)
- **Tokeny per session:** lokální soubory `~/.claude/projects/**/*.jsonl`. Každý
  řádek nese `message.usage` (input/output/cache tokeny) a `model`. Osvědčený
  přístup, používá ho i nástroj `ccusage`.
- **5h a týdenní limity:** počítají se na serveru. Dvě možné cesty:
  1. dopočítat z lokálních dat podle pravidel plánu, nebo
  2. načíst přes OAuth usage endpoint (přístup, který používá CodexBar).
- **Spike ověří:** existenci a formát JSONL, dostupnost limitního endpointu,
  kde leží OAuth token (Keychain `~/.claude`).

### 4.2 Codex (CLI předplatné)
- Lokální data v `~/.codex` (sessions a/nebo rate-limit cache).
- **Spike ověří:** které soubory nesou tokeny a rate-limit info (5h/týden) a
  jejich formát.

### 4.3 OpenAI API (pay-as-you-go)
- Útrata přes **OpenAI Admin API** (usage + cost endpointy). Vyžaduje **admin**
  API klíč uložený v Keychainu.
- Nejlépe dokumentovaný zdroj z této trojice.

## 5. Datový model (`ProviderUsage`)

Sjednocený model, který umí popsat všechny tři poskytovatele:

- `providerId` (claudeCode | codex | openAIAPI)
- `displayName`, `planLabel` (např. „Max", „Plus", „pay-as-you-go")
- `windows: [UsageWindow]` — každé okno má: `kind` (rolling5h | weekly),
  `usedFraction` (0–1), `resetAt` (Date), volitelně absolutní hodnoty.
- `today: { tokens: TokenBreakdown, estimatedCost: Decimal?, actualCost: Decimal? }`
  - `TokenBreakdown` drží rozpad podle modelu (Opus/Sonnet/…).
  - `estimatedCost` = odhad (předplatné), `actualCost` = reálná útrata (API).
- `month: { actualCost: Decimal? }` (jen tam, kde dává smysl — OpenAI API).
- `status` (ok | degraded | unavailable) + volitelná `message` pro tooltip.
- `lastUpdated: Date`.

## 6. Datový tok

1. `RefreshScheduler` ve zvoleném intervalu (ruční / 1 / 2 / 5 / 15 min) spustí
   všechny zapnuté collectory **paralelně**.
2. Každý collector vrátí `ProviderUsage` nebo `ProviderError`.
3. `UsageStore` atomicky aktualizuje stav a publikuje změnu.
4. `MenuBarController` a `PopoverView` se reaktivně překreslí.
5. `NotificationManager` zkontroluje prahy a případně pošle alert.

Vše běží lokálně. Jediná síťová volání jsou OpenAI Admin API a (případně)
Claude OAuth usage endpoint — obojí přímo k danému poskytovateli.

## 7. Uživatelské rozhraní

### 7.1 Widget v liště
Výchozí **styl A**: dvě procenta vedle sebe — 🟠 Claude, 🟢 Codex; procento =
nejbližší limit (5h nebo týden). Barva čísla: zelená < oranžová < červená podle
naplnění. Styl je **přepínatelný v Nastavení**:

- **A — Dvě procenta** (výchozí): `🟠 42%  🟢 78%`.
- **B — Jen nejkritičtější:** jediná hodnota, ta nejblíž stropu.
- **C — Mini progress bary:** vizuální „nádrže" místo čísel.
- **D — Jedna ikona:** mění barvu podle nejhoršího limitu, nejmenší stopa.

### 7.2 Rozkliknutý panel (layout A — karty po nástrojích)
- **Hlavička:** titulek „Spotřeba" + souhrn vpravo **„Dnes celkem ≈ $X"**.
- **Karta Claude Code (Max):** bar 5h okno (% + reset), bar Týden (% + reset),
  řádek **Dnes** (tokeny + `≈ $` odhad), pod ním rozpad **Opus / Sonnet**.
- **Karta Codex (Plus):** bar 5h okno, bar Týden, řádek **Dnes** (tokeny + `≈ $`).
- **Karta OpenAI API:** řádek **Dnes** (tokeny · reálná `$`), řádek **Tento měsíc** (`$`).
- **Patička:** „Aktualizováno před … · ↻ (ruční refresh)" + ⚙︎ (Nastavení).

`≈ $` u předplatného je **odhad** (co by tytéž tokeny stály v API cenách; reálně
se platí paušál). U OpenAI API jde o **skutečnou** útratu. Tento rozdíl musí být
v UI vizuálně i textově zřejmý (legenda/tooltip).

### 7.3 Nastavení
- Zapnout/vypnout jednotlivé poskytovatele.
- Zadat OpenAI admin API klíč (uložení do **Keychainu**, nikdy do plaintextu).
- Interval refreshe (ruční / 1 / 2 / 5 / 15 min).
- Styl widgetu v liště (A / B / C / D).
- Prahy notifikací (např. upozornit při 80 % a 95 %).
- Spouštět při přihlášení.

## 8. Pricing estimator
Tabulka cen modelů (input/output/cache za 1M tokenů) drží přepočet tokeny → `$`.
Tabulka je verzovaná data v appce; aktualizuje se při změně cen. Estimator je
čistá funkce nad `TokenBreakdown` — plně unit-testovatelný.

## 9. Ošetření chyb a hraniční stavy
- Chybějící CLI / nepřihlášený uživatel / chybný nebo chybějící klíč /
  rate-limit od poskytovatele → daný poskytovatel přejde do stavu
  `unavailable`/`degraded`, v UI ukáže nenásilné „—" nebo ⚠️ s vysvětlujícím
  tooltipem. **Ostatní poskytovatelé fungují dál.**
- Žádné pády, žádné modální dialogy.
- Timeout na collector, aby pomalý zdroj nezablokoval refresh ostatních.
- První spuštění bez konfigurace → onboarding stav s výzvou nastavit poskytovatele.

## 10. Soukromí a bezpečnost
- Veškerá data zůstávají lokálně. Žádná telemetrie.
- API klíče a OAuth tokeny pouze v **Keychainu**.
- Čteme jen známé lokace (`~/.claude`, `~/.codex`) v režimu jen pro čtení.
- Síťová volání pouze na oficiální API daných poskytovatelů.

## 11. Testování
- **Unit testy (jádro):** JSONL parsery (na fixturách vzorových souborů),
  `PricingEstimator`, výpočet oken a reset časů, prahová logika notifikací,
  mapování chyb na `status`. Collectory testovat proti uloženým fixturám, ne
  proti živým zdrojům.
- **Smoke/manuální:** vykreslení widgetu (všechny styly A–D), popover,
  Nastavení, Keychain ukládání klíče.
- Cíl: jádro (parsování + výpočty) plně pokryté bez nutnosti UI nebo živých dat.

## 12. Distribuce
- GitHub Releases + **Homebrew cask**.
- **Notarizace** (Apple Developer) a **auto-update** (Sparkle) až ve fázi
  vydání (v1.0). MVP stačí lokální build z Xcode.

## 13. Fázování

- **MVP (v0.1):**
  1. **Spike datových zdrojů** (Claude Code + Codex) — ověřit formáty a limity.
  2. Collectory Claude Code + Codex, `UsageStore`, `RefreshScheduler`.
  3. Widget v liště (styl A) + panel A (bez OpenAI, bez notifikací).
- **v0.2:** `OpenAIAPICollector` (útrata), „Dnes" tokeny + `PricingEstimator`
  odhady, souhrn „Dnes celkem".
- **v0.3:** notifikace (prahy), přepínatelné styly lišty (B/C/D), obrazovka
  Nastavení, spouštět při přihlášení.
- **v1.0:** leštění, notarizace, auto-update (Sparkle), Homebrew cask,
  dokumentace, README → veřejné vydání.

## 14. Otevřené otázky / rizika
- **R1 (vysoké):** Přesný způsob získání 5h/týdenních limitů Claude Code
  (lokální dopočet vs OAuth endpoint) — vyřešit ve spike.
- **R2 (střední):** Formát a stabilita lokálních dat Codexu v `~/.codex`.
- **R3 (střední):** OpenAI Admin API vyžaduje admin klíč — ne každý uživatel ho
  má; degradovat elegantně.
- **R4 (nízké):** Tabulka cen modelů zastará — řešit verzováním a snadnou
  aktualizací; `≈` jasně komunikovat jako odhad.
