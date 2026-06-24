# StatusBar v0.5 — Líný sken today + polish z review

- **Datum:** 2026-06-24
- **Stav:** Návrh (rozsah vybrán uživatelem)
- **Navazuje na:** v0.1–v0.4.

## 1. Přehled

v0.5 je **výkonová + úklidová** iterace:
1. **Líný sken today** — sken dnešních tokenů (souborové IO v `~/.claude/projects` a `~/.codex/sessions`) běží **jen při otevření popoveru / manuálním refreshi**, ne při každém 60s background refreshi (kdy popover nikdo nevidí). Limity se dál čtou každých 60s (levné cache čtení).
2. **Polish z review** — komentář k dosud nepoužitým `gpt-5.x` větvím v `PricingTable` (scanner emituje „codex"), negativní testy `CodexTokenScanner` (včerejší mtime / prázdný adresář → `nil`).

### Cíle
- Při zavřeném popoveru se today-sken neprovádí (úspora IO každých 60s).
- Při otevřeném popoveru/refreshi se today naskenuje čerstvě a zobrazí.
- **Žádné blikání:** background refresh (limity) nesmí smazat „Dnes" řádek, když je popover otevřený → koordinátor zachová poslední naskenované today.
- Limit-/today-logika i UI jinak beze změny.

### Ne-cíle
- OpenAI API (odloženo — chybí Admin klíč), styly lišty (v0.6+).

## 2. Klíčová rozhodnutí

1. **`includeToday: Bool` se prožene od refreshe do collectoru.** `UsageProvider.fetch(includeToday:)` — když `false`, collector today **neskenuje** (`today = nil`).
2. **Koordinátor drží cache `lastToday: [ProviderID: TodayUsage]`.** Při `includeToday == true` cache aktualizuje podle čerstvého skenu (nil sken klíč vyřadí — řeší přechod přes půlnoc). Při `false` čerstvý sken neproběhne a výsledku se **přiloží** cached today (`with(today:)`), takže „Dnes" nezmizí.
3. **Kdy `true` / `false`:** start appky + 60s timer = `false` (rychlé, jen limity); otevření popoveru + tlačítko refresh = `true` (skenuj today). Popover už při otevření volá refresh, takže today naskočí krátce po otevření.
4. Default `refreshNow(includeToday: Bool = true)` (zpětná kompatibilita existujícího testu).

## 3. Architektura (změny)

| Komponenta | Změna |
|---|---|
| `UsageProvider` | `func fetch(includeToday: Bool) async -> ProviderUsage` |
| `ClaudeCodeCollector` / `CodexCollector` | `today = includeToday ? scanner.todayUsage(now:) : nil` |
| `RefreshCoordinator` | `refreshNow(includeToday: Bool = true)`; cache `lastToday`; preserve při `false` |
| `AppDelegate` | klik=`true`, start/timer=`false` |
| testy | aktualizovat call-sites na `fetch(includeToday:)`; nové coordinator preserve testy; gate test collectoru |
| `PricingTable` | komentář k `gpt-5.x` dead-code větvím |
| `CodexTokenScannerTests` | negativní testy (včerejší mtime / prázdný adresář → nil) |

## 4. Datový tok
- **Background (timer, `false`):** fetch limitů (cache) → collector vrátí `today=nil` → koordinátor přiloží `lastToday` → store. Menu bar i otevřený popover drží poslední „Dnes".
- **Popover open / refresh (`true`):** fetch limitů + today sken → koordinátor aktualizuje `lastToday` → store. Čerstvé „Dnes".

## 5. Testování
- **Unit (jádro, deterministicky):**
  - `RefreshCoordinator`: (a) `true` sken naplní today; (b) následný `false` refresh today **zachová** (cache); (c) `false` bez předchozího `true` → today `nil`.
  - `ClaudeCodeCollector.fetch(includeToday: false).today == nil` (gate; deterministické — sken se nespustí).
  - `CodexTokenScanner`: včerejší-mtime soubor → `nil`; prázdný adresář → `nil`.
- **Build/smoke:** `swift build` čistý, `swift test` (43 + nové), app naběhne; popover po otevření ukáže „Dnes".

## 6. Fázování
1. Líný sken: protokol + collectory + `RefreshCoordinator` (cache/preserve) + AppDelegate wiring + aktualizace/nové testy.
2. Polish: `gpt-5.x` komentář + negativní `CodexTokenScanner` testy.

## 7. Rizika
- **R1 (nízké):** přechod přes půlnoc → cache by držela včerejší today; mitigace: `true` sken cache přepíše i na `nil` (vyřadí klíč), popover při otevření vždy skenuje `true`.
- **R2 (nízké):** migrace signatury `fetch` zasáhne víc call-sites; mitigace: enumerováno (1 src + 5 test call-sites), default param u `refreshNow`.
- **R3 (nízké):** `.unavailable` provider by dostal cached today (nezobrazí se — `unavailable` karta todayRow neukazuje); neškodné.
