# StatusBar v0.9a — Bohatší popover: Pace + „Updated X ago" + rychlé odkazy

- **Datum:** 2026-06-24
- **Stav:** Návrh (rozsah odsouhlasen uživatelem)
- **Navazuje na:** v0.1–v0.8b.
- **Cyklus 1 ze 3 v0.9** (inspirace CodexBar referencí). v0.9b = 30denní cena, v0.9c = lokalizace (nakonec).

## 1. Přehled

Tři prvky do popoveru (inspirace referencí):
- **#A „Aktualizováno před X"** — čerstvost dat per provider (řeší i throttle z v0.8b: po throttle se vrací cachovaný snapshot, takže musí ukázat reálné stáří, ne „teď").
- **#B Pace (tempo čerpání)** — u oken: jdeš napřed/pozadu vůči lineárnímu tempu do resetu (jako „Pace: Behind (−42%)").
- **#C Rychlé odkazy** — Stav Anthropic/OpenAI + Usage dashboardy.

### Cíle
- Honest čerstvost dat (správné „před X min" i pro cachovaný/throttlovaný snapshot).
- Tempo čerpání limitů (rychlá indikace „dojde mi to dřív?").
- Rychlý přístup na status/usage stránky.

### Ne-cíle (YAGNI)
- 30denní cena (samostatný cyklus v0.9b), lokalizace (v0.9c), více providerů, extra-usage.

## 2. Architektura

Výpočty (relativní čas, pace) jsou pure Kit (testovatelné). UI + odkazy v App.

| Komponenta | Vrstva | Odpovědnost | Test |
|---|---|---|---|
| `RelativeTimeFormatter` | Kit | `string(from:now:) -> String`: <60s „právě teď", <60min „před N min", <24h „před N h", jinak „před N d" | **unit** |
| `PaceCalculator` | Kit | `pace(window:now:) -> Int?` — z `kind` (délka 5h/7d) + `resetAt` spočítá `vyčerpáno% − uplynulo%` (signed Int %); nil když `resetAt` nil nebo už v minulosti | **unit** |
| `PaceLabel` | Kit | `text(deltaPercent:) -> String`: >0 „napřed o X %", <0 „pozadu o X %", 0 „v tempu" | **unit** |
| `ClaudeLiveUsage` (změna) | Kit | `+ fetchedAt: Date` (init default `Date()` → staré konstrukce kompilují) | (přes collector testy) |
| `CodexLiveUsage` (nový wrapper) | Kit | `{ snapshot: CodexSnapshot, fetchedAt: Date }`; `CodexUsageSource.fetchFresh() -> CodexLiveUsage?` (změna návratu) | (přes collector testy) |
| `ClaudeCodeCollector`/`CodexCollector` (změna) | Kit | `lastUpdated: fresh.fetchedAt` (místo `now`) na živé cestě | unit (fake source s fetchedAt) |
| `LiveClaudeUsageSource`/`LiveCodexUsageSource` (změna) | App | konstruují `ClaudeLiveUsage`/`CodexLiveUsage` s `fetchedAt: Date()` na úspěchu; `lastGood` drží jeho čas | build/smoke |
| `PopoverView` (změna) | App | header karty „Aktualizováno před X" (z `usage.lastUpdated`); pod oknem pace řádek; sekce odkazů | build/smoke |

### Pace výpočet
`PaceCalculator.pace(window:now:)`:
- `guard let reset = window.resetAt, reset > now else { return nil }`
- `duration: TimeInterval = window.kind == .rolling5h ? 5*3600 : 7*24*3600` (weekly).
- `start = reset.addingTimeInterval(-duration)`; `elapsed = now.timeIntervalSince(start)`; `elapsedFraction = min(1, max(0, elapsed/duration))`.
- `delta = (window.usedFraction - elapsedFraction) * 100` → `Int(delta.rounded())`.
- Kladné = čerpáš rychleji než lineárně (napřed, riziko); záporné = pomaleji (pozadu, rezerva).

### „Aktualizováno před X" (fetchedAt)
Dnes collector na živé cestě nastavuje `lastUpdated: now` i pro throttle-cachovaný snapshot → vždy „teď". Proto `fetchedAt` (čas posledního ÚSPĚŠNÉHO fetche) teče přes `ClaudeLiveUsage`/`CodexLiveUsage` do `ProviderUsage.lastUpdated`. Cache-fallback cesta už `lastUpdated` má správně (čas souboru). Popover: `RelativeTimeFormatter.string(from: usage.lastUpdated, now: Date())`.

### Odkazy (App)
`PopoverView` sekce (nad „Nastavení…/Konec"): tlačítka otevírající přes `NSWorkspace.shared.open`:
- „Stav Anthropic" → `https://status.anthropic.com`
- „Stav OpenAI" → `https://status.openai.com`
- „Usage Claude" → `https://claude.ai/settings/usage`
- „Usage OpenAI" → `https://platform.openai.com/usage`

## 3. Datový tok (fetchedAt)
1. `LiveClaudeUsageSource` na 200 → `ClaudeLiveUsage(windows, planLabel, fetchedAt: Date())`, uloží do `lastGood`. Throttle/cache → vrátí `lastGood` (s jeho původním `fetchedAt`).
2. `ClaudeCodeCollector`: `if let fresh = await liveSource?.fetchFresh()` → `ProviderUsage(..., lastUpdated: fresh.fetchedAt, ...)`.
3. Codex analogicky přes `CodexLiveUsage` (`fresh.snapshot.windows`, `CodexPlan.label(fresh.snapshot.planType)`, `lastUpdated: fresh.fetchedAt`).

## 4. Verifikace a meze
- **Plně ověřitelné (auto):** unit testy `RelativeTimeFormatter` (hranice), `PaceCalculator` (kladný/záporný/nil/hranice), `PaceLabel`; collector testy s fake source nesoucím `fetchedAt` → `lastUpdated == fetchedAt`; `swift build`+`swift test`.
- **GAP (ověří uživatel):** vizuál „Aktualizováno před X", pace řádků, fungující odkazy.

## 5. Fázování (3 tasky)
1. **Kit výpočty:** `RelativeTimeFormatter` + `PaceCalculator` + `PaceLabel` + testy.
2. **fetchedAt threading (Kit+App):** `ClaudeLiveUsage +fetchedAt` (default `Date()`), `CodexLiveUsage` wrapper + `CodexUsageSource` návrat, collectory `lastUpdated: fresh.fetchedAt`, live sources konstrukce s `fetchedAt`, aktualizovat fake-source testy. Build+test.
3. **App UI:** `PopoverView` (Aktualizováno před X, pace řádky, sekce odkazů) + verze 0.8.1. Build+smoke.

## 6. Rizika
- **R1 (nízké):** `fetchedAt` ripple rozbije fake-source testy → aktualizovat 2 testy (Claude/Codex collector); `ClaudeLiveUsage` default `Date()` drží staré konstrukce. `CodexUsageSource` návrat = hard změna → live source + collector + test ve stejném tasku (build green).
- **R2 (nízké):** pace u `rolling5h` je volatilní → akceptováno (caption2, drobné); nil když resetAt v minulosti (stará data).
- **R3 (nízké):** URL dashboardů se můžou změnit → degradace neškodná (otevře se stránka/404), verzovat.
- **R4 (nízké):** `RelativeTimeFormatter`/`PaceLabel` jsou česky natvrdo → lokalizace až v0.9c (záměr).
