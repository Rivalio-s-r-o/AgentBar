# StatusBar v0.8a — Reálná cena + error-path testy

- **Datum:** 2026-06-24
- **Stav:** Návrh (rozsah + UX odsouhlaseno uživatelem)
- **Navazuje na:** v0.1–v0.7b.
- **Cyklus COST (1. ze 2 ve v0.8).** Cyklus LIVE (#3 throttle/backoff + #1 token refresh) je samostatný spec/cyklus.

## 1. Přehled

Dvě věci:
- **#4 Reálná cena:** „útrata ≈ $" dnes zahrnuje cache tokeny (cacheWrite+cacheRead), takže `$455` neodpovídá reálné spotřebě (3.75 M reálných tokenů). Uživatel chce, aby `$` ukazovalo **jen cenu reálných (přijatých+odeslaných) tokenů** = `input×cena + output×cena`. Cache zůstane vidět jako počet tokenů, ale ne v `$`.
- **#2 Error-path testy:** doplnit ~13 chybějících error/edge testů v Kit vrstvě (parser error cesty, pricing větve, collector hranice).

### Cíle
- Zobrazená denní cena = reálná (input+output), bez cache. Per provider i v hlavičce „Dnes ≈".
- Vyšší pokrytí error cest (robustnost, regrese-safety).

### Ne-cíle (YAGNI)
- Zobrazovat plnou cenu s cache (uživatel ji nechce). `PricingEstimator.estimate` (plná) zůstává jako utilita, ale UI ji nezobrazuje.
- Cokoli z cyklu LIVE (throttle/backoff/refresh) — samostatný cyklus.
- Změna pricing tabulky (ceny beze změny).

## 2. Diagnóza (ověřeno)
- `PricingEstimator.estimate(_:model:)` (`PricingEstimator.swift:8-9`) = `input + output + cacheWrite + cacheRead`. `TodayUsage.estimatedCost` (`TokenUsage.swift:29`) drží tuto plnou cenu; plní ji scannery: `ClaudeTokenScanner.swift:33` a `CodexTokenScanner.swift:33` přes `PricingEstimator.estimate(perModel)`.
- Zobrazení: `PopoverView.swift:11` (součet `dnesCelkem`), `:20` (header „Dnes ≈"), `:64` (per-provider „≈ $"). MenuBar cenu nezobrazuje.
- Existující testy: `PricingEstimatorTests` testuje `estimate` (plnou) exaktně → zůstává. Scanner testy testují jen `estimatedCost > 0` → fixtury mají nenulové input/output (Claude 100/50, Codex real 2500) → po přechodu na `estimateReal` stále `> 0`. Žádný existující test se nerozbije.

## 3. Architektura změny (#4)

| Komponenta | Vrstva | Změna | Test |
|---|---|---|---|
| `PricingEstimator` | Kit | přidat `estimateReal(_:model:)` + `estimateReal(_ perModel:)` = jen `input×p.input + output×p.output` (cache vynechána). `estimate` (plná) beze změny. | **unit** |
| `ClaudeTokenScanner` | Kit | `:33` `estimatedCost: PricingEstimator.estimateReal(perModel)` (místo `estimate`) | (existující `> 0`) |
| `CodexTokenScanner` | Kit | `:33` `estimatedCost: PricingEstimator.estimateReal(perModel)` | (existující `> 0`) |
| `TokenUsage.swift` (TodayUsage) | Kit | doc komentář: `estimatedCost` = reálná cena (jen input+output, bez cache) | — |
| `PopoverView` | App | **beze změny kódu** — `estimatedCost` teď nese reálnou cenu; text „`<real> tok (+<cache> cache) ≈ $<real>`" tím dává smysl. | build/smoke |

Pozn.: `estimatedCost` field zůstává pojmenovaný stejně (drží teď reálnou cenu) → minimální ripple, PopoverView beze změny.

## 4. Error-path testy (#2) — seznam (~13)

Všechny inline (bez nových fixtur, pokud neuvedeno), vzor existujících testů. Pure Kit.

1. **`apiParserHodíChybnýJSON`** — `ClaudeUsageCacheParser.parseAPIWindows(Data("nonsense"))` hodí (throws).
2. **`apiParserPrázdnéLimitsPrázdnéPole`** — `parseAPIWindows({"limits":[]})` → `[]`.
3. **`apiParserNeznámýKindIgnorován`** — `parseAPIWindows` s limitem `kind:"daily"` (neznámý) → přeskočí, vrátí zbylá okna.
4. **`cacheParserStrukturálněChybnýJSON`** — `ClaudeUsageCacheParser.parse` s JSON co má strukturu ale chybí povinné pole (např. bez `data`) → hodí DecodingError.
5. **`codexAPIParserUsedPercentNilOknoNil`** — `CodexUsageAPIParser.parse` s `primary_window` bez `used_percent` → okno se nevytvoří → (jen-primary bez secondary) → nil.
6. **`codexAPIParserLimitWindowSecondsNilJe5h`** — `primary_window` bez `limit_window_seconds` → `(nil ?? 0) < 86400` → `.rolling5h`.
7. **`codexRateLimitParserJenSekundární`** — JSONL `token_count` s `primary:null, secondary:{…}` → snapshot s jedním `.weekly` oknem.
8. **`codexRateLimitParserObaUsedPercentNil`** — primary i secondary existují, oba `used_percent:null` → `windows` prázdné → nil.
9. **`pricingCacheWriteSonnetHaiku`** — `PricingEstimator.estimate` s nenulovým `cacheWrite` pro Sonnet (3.75) a Haiku (1.25) → očekávaná hodnota.
10. **`pricingGPT5Větve`** — `PricingTable.pricing("gpt-5")` a `("gpt-5.5")` → správné ceny (5/30 resp. 2.5/15).
11. **`claudeCollectorPrázdnýSouborUnavailable`** — `ClaudeCodeCollector` s cachePath na existující 0-bajtový soubor → `.unavailable` (parse hodí → catch).
12. **`estimateRealJenInputOutput`** — `estimateReal` ignoruje cacheWrite/cacheRead (Opus: input 1M + output 1M + cacheRead 100M → cena = 5 + 25 = 30, ne víc); `estimateReal(perModel)` součet; neznámý model → 0.

(Pozn.: test 12 patří k #4, ostatní 1–11 k #2.)

## 5. Verifikace a meze
- **Plně ověřitelné (auto):** unit testy `estimateReal` + 12 error-path; `swift build` (Kit+App) čistý; `swift test` zelený (existující + ~13 nových); scanner testy `> 0` stále projdou.
- **GAP (ověří uživatel):** vizuál nižší (reálné) ceny v popoveru.

## 6. Fázování (2 tasky)
1. **#4 reálná cena:** `PricingEstimator.estimateReal` (×2 overload) + scannery na `estimateReal` + doc TodayUsage + test `estimateRealJenInputOutput` (a varianta perModel + neznámý model). Build+test.
2. **#2 error-path testy:** ~12 testů (parser/pricing/collector error cesty) do příslušných test souborů. Build+test.

## 7. Rizika
- **R1 (nízké):** scanner test `estimatedCost > 0` by se rozbil, kdyby fixtura měla 0 reálných tokenů → ověřeno: Claude 100/50, Codex real 2500 → `> 0` drží. Mitigace: pokud by někdy fixtura měla jen cache, test upravit/fixturu doplnit.
- **R2 (nízké):** `estimateReal` semanticky mění `estimatedCost` (plná→reálná) → žádný test neasertuje exaktní scanner cenu (jen `> 0`); plnou cenu testuje `estimate` (zachována). Ověřeno grepem.
- **R3 (nízké):** error-path testy odhalí reálný bug v parseru → to je žádoucí; pokud test selže na chování, opravit chování nebo zpřesnit test (eskalovat při neshodě se specem).
