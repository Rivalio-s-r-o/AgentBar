# StatusBar v0.9b + v0.9c — 30denní cena + projekce, a lokalizace en/cs

- **Datum:** 2026-06-24
- **Stav:** Návrh (rozsah odsouhlasen uživatelem)
- **Navazuje na:** v0.1–v0.9a.
- **Cykly 2 a 3 ze 3 v0.9** (inspirace CodexBar referencí). Dělány **dohromady, jedna větev** `feat/v0.9bc-30day-cost-and-localization`, fázovaně: nejdřív feature v0.9b (zavede nové stringy), pak v0.9c lokalizuje vše naráz.

## 1. Přehled

Dvě části v jedné větvi:

- **v0.9b — 30denní cena + projekce.** Do každé karty popoveru pod „Dnes" přibude řádek `30 dní: $X · Y tok` + decentní měsíční projekce `≈ $Z/měs`. Cena = reálná spotřeba (input+output, `estimateReal`, konzistentní s v0.8a). **Perf-kritické:** 30denní sken čte stovky MB → běží **off-main, throttlovaně, mimo rychlou cestu** (ne na 60s timeru, ne synchronně na popover-open).
- **v0.9c — lokalizace en/cs (POSLEDNÍ).** Všechny user-facing stringy (Kit i App, vč. v0.9a/b) přes lokalizační systém. Base **en** (fallback), **cs** jako lokalizace, runtime jazyk dle macOS. SwiftPM (ne Xcode) → `defaultLocalization: "en"` + `Localizable.strings` resources v OBOU targetech.

### Cíle
- Uživatel vidí, kolik by ho stála spotřeba za posledních 30 dní (reálné tokeny, USD odhad) + hrubý měsíční výhled.
- 30denní sken nikdy nezablokuje UI ani nezpomalí lištu.
- Aplikace běží v jazyce systému (cs/en), s angličtinou jako spolehlivým fallbackem.

### Ne-cíle (YAGNI)
- 30denní cena v liště (zůstává jen v popoveru) — backlog.
- Per-model rozpad u 30denní ceny (jen total cost + total real tokens).
- Lokální měna / přepočet kurzu — `$` je USD API-ekvivalentní **odhad**, zůstává `$` v obou jazycích.
- Plurálové `.stringsdict` — zkrácený styl je plurálově invariantní (viz §4.3), stačí prosté format-stringy.
- Lokalizace názvů plánů (Max/Pro/Free/Team/Enterprise) a názvů modelů — vlastní jména, zůstávají.
- Další jazyky než en/cs.

## 2. Architektura — v0.9b (30denní cena)

Princip: **rychlá cesta (collectory → `ProviderUsage`) se 30denní ceny vůbec nedotkne.** 30denní data tečou samostatným kanálem.

| Komponenta | Vrstva | Odpovědnost | Test |
|---|---|---|---|
| `PeriodCost` (nový) | Kit | `{ tokens: TokenUsage, cost: Decimal }` — souhrn ceny za období pro zobrazení | unit (triviální) |
| `CostProjection` (nový) | Kit | `monthly(cost:days:) -> Decimal` (`cost/days*30.4`), `monthlyTokens(_:days:) -> UInt` — pure extrapolace | **unit** |
| `ClaudeTokenScanner.rangeUsage(start:end:)` (nový) | Kit | sečte tokeny per model v `[start,end)`; refaktor — sdílený privátní helper s `todayUsage` (DRY) | **unit (fixtura)** |
| `CodexTokenScanner.rangeUsage(start:end:)` (nový) | Kit | sečte `lastTotal` přes session soubory s `mtime` v rozsahu (vzor `todayUsage`, bez limitu 50 souborů) | **unit (fixtura)** |
| `CostHistoryStore` (nový) | Kit | `@MainActor ObservableObject`: `@Published history: [ProviderID: PeriodCost]`, `isComputing: Bool`, `lastComputed: Date?`; `refreshIfStale(now:)` → throttle + off-main compute → publikace | **unit (fake provider, řízený čas)** |
| `AppDelegate` (změna) | App | zkonstruuje `CostHistoryStore` s reálným provider closurem (běží skenery přes `Task.detached(.utility)`); zavolá `refreshIfStale` při startu i na popover-open | smoke |
| `PopoverView` (změna) | App | per-provider řádek „30 dní: …" / „počítám…" (čte `CostHistoryStore`); verze 0.8.2 | build/smoke |

### 2.1 Datový tok (30denní cena)
1. `CostHistoryStore` drží cache `history` + `lastComputed`. Provider closure (`@Sendable (Date) async -> [ProviderID: PeriodCost]`) je injektovaný (testovatelnost); v appce běží reálné skenery.
2. `refreshIfStale(now:)`:
   - `guard !isComputing else { return }`
   - `guard lastComputed == nil || now.timeIntervalSince(lastComputed!) >= staleInterval else { return }` (staleInterval = **6 h**)
   - `isComputing = true`; `Task { let h = await provider(now); self.history = h; self.lastComputed = now; self.isComputing = false }`
3. Reálný provider (App): `start = now - 30*86400`; uvnitř `Task.detached(priority:.utility)` (mimo main) spustí `ClaudeTokenScanner().rangeUsage(...)` a `CodexTokenScanner(maxFilesToScan: .max).rangeUsage(...)`, namapuje `TodayUsage` → `PeriodCost(tokens: today.total, cost: today.estimatedCost)`. Skenery jsou `Sendable` struct, `TodayUsage`/`PeriodCost` `Sendable` → Swift 6 OK.
4. `AppDelegate`: `refreshIfStale(now:)` jednou při startu (data nachystaná do prvního otevření) + v `onClick` (popover-open) hned po `refreshNow(includeToday:true)`. 60s timer **nevolá** `refreshIfStale`.
5. `PopoverView`: `@ObservedObject costHistory`. V kartě providera: pokud `history[id]` existuje → `30 dní: $cost · tokens tok` + `≈ $monthly/měs`; jinak pokud `isComputing` → „30 dní: počítám…"; jinak řádek skrýt.

### 2.2 Proč mimo `ProviderUsage`
`ProviderUsage` staví collectory na rychlé cestě (start/60s/refresh). Přidat tam 30denní cenu = buď skenovat při každém refreshi (perf zabiják), nebo protahovat cache hodnotu collectory (zamotané). Samostatný `CostHistoryStore` drží pomalý kanál čistě oddělený; `PopoverView` čte oba (`UsageStore` pro karty, `CostHistoryStore` pro 30denní řádek).

### 2.3 Reuse `TodayUsage` v `rangeUsage`
`rangeUsage` vrací `TodayUsage?` (= `{ perModel, estimatedCost }`) — stejný agregační typ jako `todayUsage`, jen pro libovolný rozsah. Žádný nový skenerový návratový typ; název `TodayUsage` je interní agregát (akceptováno, přejmenování by rozvířilo v0.2 kód). `PeriodCost` je až display vrstva (`tokens: today.total`, `cost: today.estimatedCost`).

### 2.4 Projekce
`CostProjection.monthly(cost:days:)` = `cost / Decimal(days) * 30.4` (days = 30, fixní délka okna). Tokeny analogicky. **Známé omezení (dokumentováno):** při méně než 30 dnech dat (čerstvá instalace) projekce mírně podstřelí (dělí 30, ne skutečným počtem dní). Pro reálné uživatele s měsíci historie přesné. Zobrazení: `≈ $Z/měs` jako sekundární `caption2` pod 30denním řádkem.

## 3. Architektura — v0.9c (lokalizace)

### 3.1 SwiftPM setup
- `Package.swift`: top-level `defaultLocalization: "en"`.
- OBA targety (`StatusBarKit`, `StatusBarApp`) dostanou `resources: [.process("Resources")]` a adresář `Sources/<target>/Resources/` s `en.lproj/Localizable.strings` + `cs.lproj/Localizable.strings`. SwiftPM vygeneruje `Bundle.module` per target.
- **R-OVĚŘENÍ (plan-forge empiricky):** že `swift build`, `swift test` i `scripts/make-app.sh` reálně zabudují `.lproj` do správných bundle a `String(localized:bundle:.module)` se v runtime přeloží. `.strings` zvoleno místo `.xcstrings` kvůli spolehlivosti v čistém SwiftPM — pokud by empirie ukázala problém, fallback je `.xcstrings` (rozhodne plan-forge dle reality).

### 3.2 Lokalizační API + testovatelnost (Kit)
Kit formattery dnes vrací natvrdo český string a unit testy porovnávají přesný výstup. Po lokalizaci by výstup závisel na locale procesu → testy nedeterministické. **Řešení: injektovatelný `bundle`.**
- Každý lokalizující Kit formatter dostane parametr `bundle: Bundle = .module` a uvnitř volá `String(localized: "key", bundle: bundle, ...)` (resp. `NSLocalizedString`).
- Testy injektují jazykově specifický `.lproj` bundle a asertují konkrétní jazyk:
  ```swift
  let cs = Bundle(url: Bundle.module.url(forResource: "cs", withExtension: "lproj")!)!
  #expect(RelativeTimeFormatter.string(from: t, now: n, bundle: cs) == "před 5 min")
  let en = Bundle(url: Bundle.module.url(forResource: "en", withExtension: "lproj")!)!
  #expect(RelativeTimeFormatter.string(from: t, now: n, bundle: en) == "5 min ago")
  ```
- **R-OVĚŘENÍ (plan-forge empiricky):** že injektce `.lproj` bundle do `String(localized:bundle:)` v tomto SwiftPM testu vrátí cílový jazyk. Pokud ne → fallback: testy asertují jen en base + jeden CS smoke; rozhodne plan-forge.
- App stringy (`Text`, tlačítka, notifikace, tooltipy) jdou přes `String(localized:bundle:.module)` přímo (App nemá tak striktní exact-match testy — má smoke).

### 3.3 Inventář stringů (68 literálů, z toho 28 s interpolací; podklad pro plán)
Inventář byl pořízen průchodem obou targetů; kategorie a počty:
- **Kit — formattery (exact-match testy → injektovatelný bundle):** `RelativeTimeFormatter` (4: „právě teď", „před X min/h/d"), `Pace.PaceLabel` (3: „napřed/pozadu o X %", „v tempu"), `Formatting`: `ResetFormatter` („teď", „Xh Ym", „Xm"), `WindowLabel` („5h okno", „Týden", „Týden · scope"), `MenuBarStyle.displayName` (4 styly), MenuBar segment „—".
- **Kit — collector hlášky (degraded/unavailable, jdou přes lokalizaci, shell tokeny `/usage`/`` `codex` `` se nepřekládají):** `ClaudeCodeCollector` (3), `CodexCollector` (3).
- **Kit — planLabel:** NElokalizovat (vlastní jména) — ponechat literály.
- **App — `PopoverView`:** „Spotřeba", „Načítám…", „Dnes ≈ …", „… tok (+… cache) ≈ …", „X % zbývá", „Aktualizováno …", „Tempo: …", „30 dní: …"/„počítám…" (nové z v0.9b), 4 odkazy, „Nastavení…", „Konec".
- **App — `SettingsView`:** „Nastavení", „Spouštět při přihlášení", „Zobrazení lišty", „Styl", „Číslo ukazuje", „Zbývající", „Vyčerpané", „Upozornění", „Upozornit, když klesnou zbývající limity", „Práh (zbývá ≤)", „X %", „StatusBar X".
- **App — ostatní:** `NotificationService` (titulek/tělo/suffix), `MenuBarController` (fallback „StatusBar", 3 tooltip varianty), `SettingsWindowController` (titulek okna).

### 3.4 Vnořené interpolace
„Aktualizováno \(rel)" a „Tempo: \(pace)" vkládají výstup jiného lokalizovaného stringu — funguje, protože vnitřní string je už lokalizovaný; format-string drží jen jeden `%@` placeholder. Pořadí: vnitřní formatter vrací hotový lokalizovaný řetězec, vnější ho vloží.

## 4. Verifikace a meze

- **Plně ověřitelné (auto):** unit testy `CostProjection`, `rangeUsage` Claude/Codex (fixtury — rozsahové hranice, mtime filtr), `CostHistoryStore` (fake provider: throttle nezavolá při čerstvém `lastComputed`, `isComputing` guard, publikace výsledku, řízený čas), lokalizační testy formatterů (en+cs přes injektovaný bundle); `swift build` + `swift test`.
- **R-GAP (plan-forge empiricky ověří PŘED implementací):** (a) SwiftPM `.lproj` pipeline (build+make-app.sh+runtime překlad), (b) test-time `.lproj` bundle injekce do `String(localized:bundle:)`. Obojí má definovaný fallback.
- **GAP (ověří uživatel):** vizuál 30denního řádku + projekce; reálná 30denní čísla na živých datech; přepnutí jazyka systému cs↔en a vizuální kontrola popoveru/Nastavení; že 30denní sken nezpomalí otevření popoveru.

## 5. Fázování (orientačně ~9 tasků; detail v plánu)

**v0.9b (feature první — zavede nové stringy):**
1. Kit: `PeriodCost` + `CostProjection` + testy.
2. Kit: `ClaudeTokenScanner.rangeUsage` (sdílený helper s `todayUsage`) + testy.
3. Kit: `CodexTokenScanner.rangeUsage` + testy.
4. Kit: `CostHistoryStore` (throttle/off-main/published) + testy s fake providerem.
5. App: `AppDelegate` wiring (real provider přes `Task.detached`, refreshIfStale start+popover) + `PopoverView` 30denní řádek/projekce/„počítám…" + verze 0.8.2. Smoke.

**v0.9c (lokalizace druhá — pokryje vše vč. v0.9b):**
6. SwiftPM setup: `defaultLocalization` + Resources (en/cs.lproj prázdné→base) v obou targetech; **empiricky ověřit pipeline** (1 testovací string round-trip).
7. Kit formattery lokalizovány (injektovatelný bundle) + en/cs `.strings` klíče + přepsané/rozšířené testy (en+cs).
8. App stringy lokalizovány (PopoverView, SettingsView, NotificationService, MenuBarController, SettingsWindowController) + klíče do `.strings`.
9. Doplnit cs překlady všech klíčů + finální smoke (en i cs locale).

## 6. Rizika

- **R1 (střední) — SwiftPM lokalizační pipeline:** `.strings`/`.lproj` v čistém SwiftPM + make-app.sh nemusí fungovat napoprvé (resource processing, `Bundle.module` v executable targetu, runtime jazyk). **Mitigace:** plan-forge empiricky ověří round-trip PŘED napsáním 68 klíčů; definovaný fallback `.xcstrings` / en-only testy.
- **R2 (střední) — perf 30denního skenu:** stovky MB, bez limitu souborů u Codexu. **Mitigace:** off-main `Task.detached(.utility)`, throttle 6 h, `isComputing` guard, trigger jen start+popover (ne 60s). Případně doplnit horní strop velikosti/počtu souborů, pokud by smoke ukázal pomalost.
- **R3 (nízké) — `rangeUsage` reuse `TodayUsage`:** název klame (range ≠ today). Akceptováno (interní agregát), `PeriodCost` je display vrstva. Hlídat při review, ať se nikde nezobrazí jako „dnes".
- **R4 (nízké) — projekce podstřelí u čerstvé instalace** (dělí fixních 30 dní). Akceptováno + dokumentováno; reálný uživatel má historii.
- **R5 (nízké) — Codex session přes půlnoc/hranici okna** přičte i tokeny mimo rozsah (kumulativní `lastTotal`). Stejné akceptované omezení jako u `todayUsage` (F3 z v0.2); u 30 dní proporčně zanedbatelné.
- **R6 (nízké) — collector chybové hlášky** obsahují systémové `error.localizedDescription` (lokalizuje OS) — náš obal lokalizujeme, vnitřek ne. Akceptováno.
