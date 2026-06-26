# StatusBar v0.12 — Timeline popover + System Settings redesign

- **Datum:** 2026-06-26
- **Stav:** Návrh (uživatel dodal hotový design v Claude Design, potvrdil 3 rozhodnutí).
- **Zdroj designu:** Claude Design projekt „Status Bar design pro Mac" (`1ec8fff6-…`), soubor `Spotreba Status Bar.dc.html`, varianta **03 Timeline** + sekce **Nastavení**.
- **Verze:** 0.12.0. Větev `feat/v0.12-timeline-redesign`. Baseline 168 testů.

## 1. Přehled
Vizuální redesign **popoveru** (na styl „Timeline") a **okna Nastavení** (na styl macOS System Settings) podle uživatelova návrhu. Žádná změna jádra dat — Timeline staví na existujícím `BurnBar`/`BurnRateCalculator`/`PaceCalculator`. Jedna nová funkce: přepínač **Vzhled** (Systém/Světlý/Tmavý).

### Potvrzená rozhodnutí (uživatel)
- **D1 — Vzhled = funkční** přepínač Systém/Světlý/Tmavý (override `NSApp.appearance`), default Systém → nulová regrese.
- **D2 — menu bar BEZE ZMĚNY** (burn bar z v0.11.3 zůstává; mění se jen popover + Nastavení).
- **D3 — badge ikony providerů** dle designu (Claude sluneční „burst" v zaobleném čtverci, Codex „>_").

### Ne-cíle (YAGNI)
- Varianty 01 Native / 02 Radiální (uživatel chce jen Timeline).
- Timeline vizuál v liště (D2).
- Nová data/metriky.

## 2. Architektura

### 2.1 Kit (nová pure logika)
- `Appearance` enum (`system`/`light`/`dark`, `String` RawRepresentable, `CaseIterable`) + `displayName(bundle:)` — `Formatting/Appearance.swift`. Mirror `BarWindowSource`.
- `PreferenceKeys.appearance` + `PreferencesStore.appearance: Appearance` (default `.system`).
- Lokalizace: `appearance.system`/`appearance.light`/`appearance.dark`, `settings.appearance`, `settings.preview` (náhled), `settings.watchedWindow` (přejmenování `settings.barWindow`? — necháme `settings.barWindow`), případně copy pro pace/projekci (viz §4).

### 2.2 App — nové sdílené views
- `ProviderBadge` (`Sources/StatusBarApp/ProviderBadge.swift`): zaoblený čtverec (22–24 px, radius 7) v barvě providera; Claude = sluneční burst (8 paprsků, `Canvas`/`Path`, bílé), Codex = `Text(">_")` mono bold bílé. Barvy: Claude `#D97557`, Codex `#0FA380`.
- `TimelineBarView` (`Sources/StatusBarApp/TimelineBarView.swift`): z `BurnBar` (used/projected/usedLevel/projectedLevel/overLimit). Výška 10, radius 5. Vrstvy (framing ZBÝVÁ):
  - track `var(--track)` (rezerva vpravo = vyčerpáno).
  - **plná** část `[0, 1−projected]` = co bezpečně zbyde do resetu, barva `usedLevel` (overLimit → červená).
  - **šrafovaná** zóna `[1−projected, 1−used]` = co se do resetu spálí (diagonální pruhy, barva `usedLevel`/`projectedLevel`, ~0.55 alpha).
  - **svislá ryska** na `x = 1−projected` (projektovaný stav při resetu), barva text, šířka 2, mírně přesahuje.
- `FreshnessDot` (inline ve view): pulzující tečka (animace scale/opacity 2.4 s) + krátký štítek (RelativeTimeFormatter). Barva: <3 min zelená, <15 min amber, jinak červená.

### 2.3 App — PopoverView redesign (Timeline)
`ProviderCard` přepsán: hlavička = `ProviderBadge` + název + plan **chip** (zaoblený, `--chip`) + `Spacer` + freshness tečka+štítek. Pak per okno: řádek `label · Spacer · tučné „% zbývá" · „reset {čas}"`, `TimelineBarView`, řádek tempa+projekce (barevně: pozadu→zelená, napřed→amber). Pak 30denní útrata (`30 dní · {tok}` … `{cena}`), odkazy Využití/Stav (ikony). Hlavička popoveru „Spotřeba" + dnešní cena + refresh (kruhové tlačítko `--chip`). Patička Nastavení…/Konec. Update banner zachován. Skleněné pozadí ponecháme přes materiál popoveru (NSPopover už vibrant; volitelně `.background(.ultraThinMaterial)`).

### 2.4 App — SettingsView redesign (System Settings)
- Pevná šířka ~404, sekce jako **zaoblené karty** (`--card`, vlásečnicové předěly mezi řádky), nadpisy sekcí uppercase tertiary.
- **Náhled v menu baru** (živý): malý panel s gradientem, renderuje dot + zbývající bar + % pro reálné `store.orderedUsages` (≤2), reaguje na `showUsedPercent`. Caption „Styl {X}, číslo ukazuje {zbývající/využité}". → vyžaduje předat `store` do `SettingsView`.
- **Obecné:** Spustit při přihlášení (toggle), **Vzhled** (Systém/Světlý/Tmavý picker).
- **Zobrazení v menu baru:** Styl ukazatele (picker `MenuBarStyle`), Číslo ukazuje (segmented Zbývá/Využito), Sledované okno (picker `BarWindowSource`).
- **Upozornění:** toggle + práh.
- **Aktualizace:** toggle + verze + Zkontrolovat.
- Řádky stylu: výška ~44, label vlevo, control vpravo; toggly nativní `Toggle(.switch)`, pickery nativní (vzhledově OK).

### 2.5 App — appearance aplikace
`AppDelegate`: helper `applyAppearance()` nastaví `NSApp.appearance` dle `prefs.appearance` (system→nil, light→`.aqua`, dark→`.darkAqua`). Voláno na startu + z `onAppearanceChanged` (picker Vzhled v Nastavení přidá callback). `store` předán do `SettingsWindowController`→`SettingsView` pro živý náhled.

## 3. Verifikace a meze
- **Auto (Kit):** `Appearance.displayName` en/cs, `PreferencesStore.appearance` default+persistence, klíče en==cs (Kit i App parity). `swift build` + `swift test`.
- **R-OVĚŘENO PŘEDEM (ImageRenderer PNG):** `TimelineBarView` geometrie (ryska+šrafy, framing zbývá) + `ProviderBadge` + celá karta → standalone SwiftUI `ImageRenderer` do PNG, vizuální kontrola proti designu (light+dark).
- **GAP (uživatel):** reálný vzhled popoveru/Nastavení v běžící app, přepínač Vzhled mění light/dark, živý náhled v Nastavení, badge ikony.

## 4. Lokalizace (copy)
Pace/projekce: ponecháme existující `PaceLabel`/`BurnRateLabel` (sémanticky shodné, už lokalizované) + přidáme **barevné odlišení** dle designu (pozadu/„pod tempem"→zelená, napřed/„nad tempem"→amber). Wording neměníme (menší odchylka od designu, dokumentováno). Nové klíče: `appearance.*`, `settings.appearance`, `settings.preview`, `settings.previewCaption` (Styl %@, číslo %@), případně `freshness.now`. Pravidlo `bundle: Bundle? = nil`, %/%%.

## 5. Rizika
- **R1 (střední) — SwiftUI vizuální věrnost** nelze headless 100% ověřit. Mitigace: ImageRenderer PNG předem + uživatel finálně.
- **R2 (nízké) — `NSApp.appearance` override** ovlivní všechna okna (popover, settings). Záměr. Default system = nil = beze změny.
- **R3 (nízké) — `store` do SettingsView** přidá coupling. Akceptováno (živý náhled to vyžaduje); `@ObservedObject`.
- **R4 (nízké) — badge sunburst Path** musí sedět vizuálně. Mitigace: ImageRenderer.
