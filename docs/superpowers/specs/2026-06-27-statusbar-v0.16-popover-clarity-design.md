# StatusBar v0.16 — Přehlednější popover (per-okno blok)

- **Datum:** 2026-06-27
- **Stav:** Návrh odsouhlasen uživatelem (mockup ImageRenderer ověřen, „sedí").
- **Motivace:** Uživatel: „máme strašně moc textu a není to přehledné. Hlavně info o tom jestli jsme pozadu a kolik zbývá do resetu." Per okno jsou 3 řádky se 4 čísly, z nichž 3 popisují tutéž trajektorii; navíc „behind" zní obráceně (pomalejší čerpání = dobré, ale slovo čteš jako problém).
- **Verze:** 0.16.0. Větev `feat/v0.16-popover-clarity`. Baseline 174 testů.

## 1. Rozhodnutí (odsouhlasena)
Varianta **B — vypustit jen duplicitní projekci, tempo nechat číslem v srozumitelné češtině**. Struktura zůstává 3 řádky na okno, ale 3. řádek se výrazně zkrátí.

1. **3. řádek = jediný signál.** Vypouští se text projekce `→ ~X% left at reset` (je redundantní — bar ho kreslí plnou částí + ryskou). Zůstává **výstraha** `limit ~za X` (NE-redundantní: spustí se jen když podle tempa vyčerpáš limit **dřív** než reset; konkrétní čas z baru nevyčteš). Logika: je-li `BurnProjection.timeToExhaustion != nil` → ukaž výstrahu (červeně), jinak ukaž tempo.
2. **Přeformulování tempa** (`PaceLabel`, base en + cs), aby valence slova odpovídala realitě:
   - `d < 0` (čerpáš pomaleji než plyne čas → máš náskok, zeleně): cs `rezerva %lld %%`, en `%lld%% buffer`
   - `d > 0` (čerpáš rychleji → varování, oranžově): cs `skluz %lld %%`, en `%lld%% over`
   - `d == 0`: cs `rovnoměrné tempo`, en `on pace`
   - Klíče se přejmenují kvůli sémantice: `pace.ahead`→`pace.over`, `pace.behind`→`pace.buffer`, `pace.onpace` beze změny.
3. **Headline bez slova „zbývá"/„left".** `popover.remaining`: cs `%lld %%` (→ „95 %"), en `%lld%%` (→ „95%"). Bar je remaining-framed, číslo je v kontextu jednoznačné.
4. **Čas do resetu zvýrazněn.** Ikonka `clock` (SF Symbol, dekorativní → `.accessibilityHidden(true)`) + barva z `.tertiary` na `.secondary`. Separátor „·" nahrazen ikonou.

### Ne-cíle (YAGNI)
- Beze změny: bar (`TimelineBarView`), today/month/links řádky, menu bar, `BurnRateLabel` (jen se v popoveru zavolá pouze pro výstrahu — projekční větev zůstává pro případné jiné callery), Kit logika výpočtu (`PaceCalculator`/`BurnRateCalculator`).

## 2. Architektura (dotčené soubory)

| Soubor | Změna | Test |
|---|---|---|
| `Sources/StatusBarKit/Providers/Pace.swift` | klíče `pace.ahead`→`pace.over`, `pace.behind`→`pace.buffer` (logika d>0/d<0 beze změny) | PaceTests |
| `Sources/StatusBarKit/Resources/en.lproj/Localizable.strings` | nové klíče+hodnoty pace | parity |
| `Sources/StatusBarKit/Resources/cs.lproj/Localizable.strings` | nové klíče+hodnoty pace | parity |
| `Tests/StatusBarKitTests/PaceTests.swift` | aktualizovat 6 očekávaných řetězců (RED→GREEN) | — |
| `Sources/StatusBarApp/Resources/en.lproj/Localizable.strings` | `popover.remaining` = `%lld%%` | parity |
| `Sources/StatusBarApp/Resources/cs.lproj/Localizable.strings` | `popover.remaining` = `%lld %%` | parity |
| `Sources/StatusBarApp/PopoverView.swift` | reset = clock+secondary; `paceRow` přepsán (výstraha-nebo-tempo); projekční text vypuštěn | build/smoke |
| `Resources/Info.plist` | verze 0.16.0 | — |

## 3. Verifikace a meze
- **Auto:** `swift build` 0 warningů (projekt vyžaduje), `swift test` (174, PaceTests upraveny — počet stejný). Parity en==cs (Kit `kitKlíčeEnACsShodné`, App `appKlíčeEnACsShodné`) drží, protože klíče přejmenovány v obou jazycích souběžně. `BurnRateLabelTests` beze změny (BurnRateLabel netknut).
- **GAP (uživatel):** přestavěná `AgentBar.app` — 3. řádek je jen `rezerva/skluz/rovnoměrné tempo` nebo `limit ~za X`; headline `95 %` bez „zbývá"; reset s ikonkou hodin čitelnější; bar beze změny.

## 4. Rizika
- **R1 (nízké) — přejmenování klíčů rozbije parity:** mitigace — přejmenovat v en i cs současně; parity test to ohlídá.
- **R2 (nízké) — `paceRow` ukáže prázdno:** když `reset > now`, `PaceCalculator.pace` je vždy non-nil (stejný guard jako burn) → 3. řádek má vždy obsah, dokud běží okno. Když reset proběhl/chybí, prázdno = shodné se současným chováním.
- **R3 (nízké) — `%`/`%%`:** literální `%` v hodnotách `.strings` musí být `%%` (vstup pro `String(format:)`). Hlídá vizuální kontrola + existující vzor.
