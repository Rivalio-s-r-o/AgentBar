# StatusBar v0.9d — UX polish + perf (Session/Weekly názvy, per-provider odkazy, lišta dle okna, paralelní sken)

- **Datum:** 2026-06-24
- **Stav:** Návrh (rozsah odsouhlasen uživatelem)
- **Navazuje na:** v0.1–v0.9b+c (0.9.0).
- **Verze:** 0.9.1. Větev `feat/v0.9d-ux-polish-perf`.
- **Inspirace:** CodexBar reference (screenshot od uživatele).

## 1. Přehled

Pět souvisejících vylepšení (UX + perf), jeden cyklus:

1. **Perf — paralelní 30denní sken.** `rangeUsage` (Claude+Codex) parsuje soubory sekvenčně (~12 s u heavy uživatele). Změna: `DispatchQueue.concurrentPerform` napříč jádry → ~2-3 s. Žádný persistent stav.
2. **Názvy oken.** `rolling5h` → „Session"/cs „Relace"; `weekly(nil)` → „Weekly"/cs „Týden"; `weekly(scope: m)` → název modelu `m` (např. „Sonnet", jako na fotce; nepřekládá se).
3. **Per-provider odkazy.** Místo globálního bloku 4 odkazů dostane každá karta kompaktní řádek „Usage · Status" mířený na správného poskytovatele. Patička → jen „Nastavení…" + „Konec".
4. **Lišta dle okna (NOVÉ nastavení).** `BarWindowSource { auto, session, weekly }` — uživatel volí, které % (a barvu) lišta ukazuje. Default `.auto` = dnešní chování (nejhorší okno) → nulová regrese.
5. **Přehlednější Nastavení.** Přeskupení do sekcí Obecné / Lišta / Upozornění + nový picker okna.

### Cíle
- 30denní sken nezdržuje (~2-3 s místo 12 s).
- Popover čitelnější (názvy dle reference, odkazy u svého poskytovatele).
- Uživatel si zvolí, jestli lišta hlídá Session nebo Weekly limit (nebo nejhorší).
- Nastavení přehledné.

### Ne-cíle (YAGNI)
- Taby poskytovatelů, Add Account, více providerů (velký samostatný krok).
- Extra usage / overage budget, Cost expander.
- „used" místo „zbývá" jako default (už existuje přepínač `showUsedPercent`).
- Persistent cache 30denního skenu na disk (zatím stačí paralelizace + 6h throttle).

## 2. Architektura

| Komponenta | Vrstva | Změna | Test |
|---|---|---|---|
| `ClaudeTokenScanner.rangeUsage` | Kit | paralelní parse přes `concurrentPerform` + `withUnsafeMutableBufferPointer` (distinktní sloty) + sekvenční merge | unit (existující range testy — chování beze změny) |
| `CodexTokenScanner.rangeUsage` | Kit | totéž (paralelní `lastTotal` per soubor) | unit (existující) |
| `WindowLabel.text(for:bundle:)` | Kit | Session/Weekly/scope-název + nové klíče | **unit (en+cs přes injektovaný bundle)** |
| `BarWindowSource` (nový) | Kit | `enum: String { auto, session, weekly }` + `displayName(bundle:)` | unit |
| `ProviderUsage.usedPercent(for:)` (nový) | Kit | vrátí used% zvoleného okna (fallback `nearestLimitPercent`) | **unit** |
| `MenuBarTitleBuilder.segments(…source:)` | Kit | nový param `source: BarWindowSource = .auto`; %/level z `usedPercent(for:)` | **unit (source × styly)** |
| `PreferencesStore.barWindowSource` | Kit | klíč `barWindowSource`, default `.auto` | unit |
| `PopoverView` (ProviderCard) | App | per-provider řádek odkazů Usage/Status; zrušit globální blok | build/smoke |
| `SettingsView` | App | reorganizace sekcí + picker `barWindowSource` | build/smoke |
| `MenuBarController.render` | App | předat `prefs.barWindowSource` do `segments` | build/smoke |
| `Resources/Info.plist` | App | verze 0.9.1 | — |

### 2.1 Paralelizace skenu
`ClaudeTokenScanner.rangeUsage(start:end:)`:
1. Sekvenčně posbírej `[URL]` souborů s `mtime ≥ start` (enumerator je levný).
2. `var perFile = [[String: TokenUsage]](repeating: [:], count: urls.count)`; `perFile.withUnsafeMutableBufferPointer { buf in DispatchQueue.concurrentPerform(iterations: urls.count) { i in if let data = try? Data(contentsOf: urls[i]) { buf[i] = ClaudeTokenParser.sumByModel(fromJSONL: data, dayStart: start, dayEnd: end) } } }`. Zápis do distinktního `buf[i]` z paralelních closure = bezpečné (různá paměť, žádný resize). `sumByModel` je pure static → thread-safe.
3. Sekvenční merge `perFile` → `byModel`, pak filtr 0-token + sort + `estimateReal`.

Codex analogicky (`[TokenUsage?]` sloty, `lastTotal` per soubor, respektuje `maxFilesToScan` cap přes `prefix`). `todayUsage` dál deleguje na `rangeUsage` (today sken malý → overhead paralelizace zanedbatelný).

**R-OVĚŘENÍ (plan-forge empiricky):** že `concurrentPerform` + `withUnsafeMutableBufferPointer` projde Swift 6 strict concurrency, je korektní (stejný výsledek jako sekvenční) a reálně zrychlí (změřit proti živým ~/.claude datům). Fallback: pokud strict concurrency odmítne unsafe-buffer capture → lock-protected merge nebo ponechat sekvenční.

### 2.2 Lišta dle okna
`BarWindowSource: String, Sendable, CaseIterable { case auto, session, weekly }` + `displayName(bundle: Bundle? = nil)` (auto→„barsource.auto", session→„window.session", weekly→„window.weekly").

`ProviderUsage.usedPercent(for source: BarWindowSource) -> Int`:
- `.auto` → `nearestLimitPercent` (= max přes okna; dnešní chování).
- `.session` → okno `.rolling5h`: `Int((usedFraction*100).rounded())`; chybí → `nearestLimitPercent`.
- `.weekly` → nejhorší z `weekly(*)` oken; chybí → `nearestLimitPercent`.

`segments(for:style:showUsedPercent:source: BarWindowSource = .auto)`: všude, kde se dnes bere `u.nearestLimitPercent`, vzít `u.usedPercent(for: source)` (číslo i `level`/barva). Styl `.worst` vybírá nejhoršího providera podle téhož `usedPercent(for: source)`. **Default `.auto` → `usedPercent(.auto) == nearestLimitPercent` → bajt-za-bajt dnešní chování (existující testy projdou beze změny).**

**Kompromis (dokumentováno):** při `.session`/`.weekly` lišta ukazuje JEN zvolené okno — když je druhé okno kritické, lišta to nesignalizuje. `.auto` (default) zachová hlídání nejhoršího. Záměr (uživatel chce volbu).

### 2.3 Per-provider odkazy (App)
`ProviderCard` dostane řádek (pod `monthRow`, jen u `.ok`/`.degraded`):
- Claude: Usage `https://claude.ai/settings/usage`, Status `https://status.anthropic.com`
- Codex: Usage `https://platform.openai.com/usage`, Status `https://status.openai.com`
Tlačítka = ikona + text: Usage `chart.line.uptrend.xyaxis` + „card.usage" („Usage"), Status `waveform.path.ecg` + „card.status" („Status"). `NSWorkspace.shared.open`. Globální blok 4 odkazů v `PopoverView.body` se ODSTRANÍ (i klíče `popover.link.*`).

### 2.4 Nastavení (App)
Sekce s jasnými hlavičkami:
- **Obecné:** Spouštět při přihlášení.
- **Lišta:** Styl · Číslo ukazuje (Zbývající/Vyčerpané) · **Okno v liště** (picker `BarWindowSource.allCases`, default Auto) — `onChange → onAppearanceChanged()`.
- **Upozornění:** přepínač + práh.
- patička: verze.

## 3. Lokalizace
Nové/změněné `.strings` klíče (Kit i App), en base / cs:
- Kit: `window.session` („Session"/„Relace"), `window.weekly` („Weekly"/„Týden"), `barsource.auto` („Auto"/„Auto"). ODSTRANIT `window.5h`, `window.week`, `window.week.scope` (scope se zobrazí přímo jako název modelu, bez klíče).
- App: `card.usage` („Usage"/„Usage"), `card.status` („Status"/„Stav"), `settings.barWindow` („Okno v liště"/„Menu bar window"). ODSTRANIT `popover.link.anthropic/openai/usageClaude/usageOpenai`.
Pravidlo %/%% a `bundle: Bundle? = nil` (z v0.9c) platí. Test úplnosti `kitKlíčeEnACsShodné` musí dál platit; přidat App variantu kdyby chyběla.

## 4. Verifikace a meze
- **Auto (Kit):** `WindowLabel` (Session/Relace/Weekly/Týden/scope), `BarWindowSource.displayName`, `ProviderUsage.usedPercent(for:)` (session/weekly/auto/fallback/chybějící okno), `segments(source:)` (auto = beze změny; session/weekly vybere správné okno; level dle zvoleného okna), paralelní `rangeUsage` (existující range testy — stejný výsledek), klíče en==cs; `swift build` + `swift test`.
- **R-GAP (plan-forge empiricky):** paralelizace Swift 6 compile + korektnost + reálné zrychlení (změřit).
- **GAP (ověří uživatel):** vizuál per-provider odkazů, přepínač okna v liště (Session/Weekly/Auto mění číslo), přehlednost Nastavení, čitelné Session/Weekly v popoveru, reálná rychlost skenu.

## 5. Fázování (orientačně 7 tasků; detail v plánu)
1. **Kit perf:** paralelizace `ClaudeTokenScanner.rangeUsage` + `CodexTokenScanner.rangeUsage` (existující testy projdou) + plan-forge měření.
2. **Kit názvy:** `WindowLabel` Session/Weekly/scope + nové `.strings` klíče + testy (en+cs) + odstranit staré klíče.
3. **Kit lišta-zdroj:** `BarWindowSource` + `ProviderUsage.usedPercent(for:)` + `segments(source:)` + `PreferencesStore.barWindowSource` + `barsource.auto` klíč + testy.
4. **App popover odkazy:** per-provider Usage/Status v kartě, zrušit globální blok, `card.*` klíče.
5. **App Nastavení + lišta:** reorganizace `SettingsView` + picker okna, `MenuBarController.render` předá source, verze 0.9.1. Build+smoke.
6. **Lokalizace doplnění:** dotáhnout cs překlady nových klíčů, test úplnosti, grep na vynechané literály.
7. (případně sloučeno) finální smoke.

## 6. Rizika
- **R1 (střední) — paralelizace Swift 6 / korektnost:** unsafe-buffer capture v `concurrentPerform` může narazit na strict concurrency, nebo merge chybu. **Mitigace:** plan-forge empiricky ověří (compile + výsledek == sekvenční + měření); fallback lock/sekvenční.
- **R2 (nízké) — lišta `.session/.weekly` skryje kritické druhé okno.** Akceptováno; `.auto` default hlídá nejhorší.
- **R3 (nízké) — odstranění starých `window.*`/`popover.link.*` klíčů:** musí zmizet z kódu i `.strings` současně (jinak chybějící klíč → zobrazí se klíč). Hlídá test úplnosti + grep.
- **R4 (nízké) — `weekly(scope)` → jen název modelu** může být bez kontextu („Sonnet"). Akceptováno (dle fotky); je vizuálně pod Weekly oblastí.
- **R5 (nízké) — `@AppStorage<BarWindowSource>`** vyžaduje `RawRepresentable`(String) — splněno (jako `MenuBarStyle`).
