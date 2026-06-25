# StatusBar v0.11 — Burn bar (grafický burn-rate v liště)

- **Datum:** 2026-06-25
- **Stav:** Návrh (vizuál + rozsah odsouhlasen uživatelem; vizuál empiricky vyrenderován do PNG a schválen).
- **Navazuje na:** v0.10 (burn-rate odhad textem v popoveru). Verze 0.11.0, větev `feat/v0.11-burn-bar`.
- **Motivace (uživatel):** „Burning odhad se vypisuje, ale chtěl bych ho spíš **graficky na liště** — znázornit, kolik mi přibližně ubyde limitu, když budu takhle pracovat. Přehledně a intuitivně."

## 1. Přehled
Nový **volitelný styl lišty** `.burnBar`: dvoubarevný „buffered" proužek (jako přehrávač videa / baterie s projekcí) per provider přímo v menu baru:
- **plná část** = vyčerpáno **teď** (stávající `usedPercent`),
- **světlejší část** = **projekce do resetu** při dosavadním tempu (`BurnRateCalculator`),
- **slabá stopa** = nedotčená rezerva,
- **přeteče-li projekce 100 % před resetem** → projekce zčervená + červená čepička na konci (limit padne dřív),
- vedle proužku malé `%` (vyčerpáno teď).

Barva proužku = nebezpečí podle `max(teď, projekce)` (green <75 / orange 75–90 / red ≥90), tj. stejná škála jako popover. Respektuje stávající nastavení **Okno v liště** (Session/Weekly/Auto). **Nový styl = přepínatelný v Nastavení, výchozí beze změny → nulová regrese.**

### Cíle
- Na jediný pohled v liště vidět „teď jsem tady, takhle daleko to dojede".
- Intuitivní metafora (plné=teď, světlé=projekce).
- Zero-regression: výchozí styl i ostatní styly nedotčené.

### Ne-cíle (YAGNI)
- Sparkline / historický graf (jiná featura).
- Odebrání textového burn řádku z popoveru (zůstává jako přesný detail „limit ~za X").
- Nový picker okna (reuse `BarWindowSource`).
- Absolutní čas resetu v liště.

## 2. Architektura

| Komponenta | Vrstva | Změna | Test |
|---|---|---|---|
| `ProviderUsage.selectedWindow(for:)` (nový) | Kit | vrátí `UsageWindow?` zvolené lištou (mirror logiky `usedPercent`); `usedPercent` na něj DELEGUJE (DRY, beze změny chování) | **unit** |
| `BurnBar` (nový) | Kit | `struct { used, projected: Double; overLimit: Bool; level: UsageLevel }` | — |
| `BurnBarBuilder.bar(for:source:now:)` (nový) | Kit | spočítá `BurnBar?` z `ProviderUsage` (nil když není okno) | **unit** |
| `MenuBarStyle.burnBar` (nový case) | Kit | + `style.burnBar` lokalizace | unit (displayName) |
| `BurnBarRenderer` (nový) | App | nakreslí kompozitní `NSImage` (oba providery: dot+proužek+%) — kód ověřený PNG renderem | (vizuál ověří user; PNG smoke) |
| `MenuBarController.render` | App | větev pro `.burnBar`: spočítá Kit `BurnBar` per provider → `BurnBarRenderer` → `button.image`, prázdný title | smoke |
| `SettingsView` | App | `MenuBarStyle.allCases` automaticky zahrne nový styl (picker beze změny kódu) | smoke |
| `Resources/{en,cs}.lproj` (Kit) | Kit | `style.burnBar` | parity test |
| `Resources/Info.plist` | App | verze 0.11.0 | — |

### 2.1 Výběr okna (Kit, DRY)
`ProviderUsage.selectedWindow(for source: BarWindowSource) -> UsageWindow?`:
- `.auto` → okno s max `usedFraction` (= nearest).
- `.session` → první `.rolling5h`; jinak okno s max `usedFraction`.
- `.weekly` → `weekly(scope: nil)`; jinak nejhorší `weekly(*)`; jinak okno s max `usedFraction`.
- prázdné `windows` → `nil`.

`usedPercent(for:)` se REFAKTORUJE na `Int(((selectedWindow(for: source)?.usedFraction ?? 0) * 100).rounded())`. **Chování čísla identické** (číslo = frakce zvoleného okna; existující `usedPercent` testy jsou pojistka). Reset/projekci pak `BurnBarBuilder` bere z TÉHOŽ okna → konzistence proužku s číslem.

### 2.2 BurnBar model (Kit, pure)
`BurnBarBuilder.bar(for usage: ProviderUsage, source: BarWindowSource, now: Date) -> BurnBar?`:
- `guard let w = usage.selectedWindow(for: source) else { return nil }`
- `let used = min(1.0, max(0, w.usedFraction))`
- `let projRaw = BurnRateCalculator.project(window: w, now: now)?.projectedFractionAtReset`
- `let projected = projRaw.map { min(1.0, max($0, used)) } ?? used` (vždy ≥ used, clamp ≤ 1 pro kreslení)
- `let overLimit = (projRaw ?? 0) > 1.0`
- `let level = UsageLevel.level(forPercent: Int((max(used, projected) * 100).rounded()))`
- vrať `BurnBar(used:projected:overLimit:level:)`

### 2.3 Kreslení (App, `BurnBarRenderer` — kód OVĚŘENÝ PNG renderem)
Per provider skupina (horizontálně): **dot** (barva providera) + proužek (zaoblený rect) + `%`.
- track (rezerva): label/white @ ~0.12–0.16 alpha.
- projekce (used→projected): `hue` @ 0.38 alpha (nebo červená @ 0.42 při overLimit).
- teď (0→used): `hue` plná.
- overLimit: červená čepička s(3) na konci.
- jemný okraj `hue` @ 0.55.
- `%` = `usedPercent` numericky, `monospacedDigitSystemFont`, `labelColor`.
- `hue` z `UsageLevel` → `.systemGreen/.systemOrange/.systemRed`.
Rozměry (1×, menu bar): dot r≈3, proužek ~52×9 (radius 3), font 11, mezery 5; oba providery vedle sebe v jednom `NSImage` (mezera ~12). `NSImage(size:flipped:drawingHandler:)` → automaticky retina. `image.isTemplate = false` (barevné). Překresluje se při každém `render`/`applyAppearance` (chytí změnu vzhledu i dat). **Unavailable provider:** dot @ 0.4 + „—" (bez proužku).

### 2.4 MenuBarController (App)
`render(_:)`: `if prefs.barStyle == .burnBar { kresli obraz }` jinak stávající text cesta. Pro `.burnBar`: pro každý `displayable` provider spočítej `BurnBarBuilder.bar(for:source:now:)`, předej `BurnBarRenderer.image(groups:)`; `statusItem.button.image = img; statusItem.button.attributedTitle = ""`. Když není žádný displayable → fallback text „StatusBar" (jako dnes). **Pozor:** při návratu z `.burnBar` na jiný styl musí render vyčistit `button.image = nil` (jinak zůstane obrázek). Tooltip beze změny.

## 3. Lokalizace
- Kit: `style.burnBar` = en „Burn bar" / cs „Burn pruh".
Pravidlo `bundle: Bundle? = nil`. Parity test (Kit en==cs) musí dál platit.

## 4. Verifikace a meze
- **Auto (Kit):** `selectedWindow(for:)` (auto/session/weekly/fallback/prázdné), `usedPercent` beze změny (existující testy), `BurnBarBuilder.bar` (used clamp, projected≥used clamp≤1, overLimit, level dle max, nil bez okna), `MenuBarStyle.burnBar.displayName` en/cs, klíče en==cs. `swift build`+`swift test`.
- **R-OVĚŘENO PŘEDEM (PNG render):** dvoubarevný proužek na light/dark, kontrast teď vs projekce, overLimit červená — vyrenderováno do PNG a vizuálně schváleno. Při smoke se z reálné implementace vyrenderuje znovu pro kontrolu.
- **GAP (ověří uživatel v liště):** reálný vzhled v menu baru (proužek+dot+%), přepnutí stylu v Nastavení živě překreslí, čitelnost na jeho pozadí, dva providery vedle sebe se vejdou.

## 5. Rozhodnutí (autonomně, uživatel revize)
- **D1 — single hue, dvě průhlednosti** (teď 100 % / projekce 38 %): nejčistší „buffered" čtení; barva z `max(teď,projekce)`.
- **D2 — % = vyčerpáno teď** (jako schválený mockup); projekce je vizuální (ghost), ne číslo.
- **D3 — reuse `BarWindowSource`**; žádný nový picker.
- **D4 — popover textový burn ZŮSTÁVÁ** (lišta=glanc, popover=přesnost).
- **D5 — nový styl, ne náhrada** (uživatel zvolil).

## 6. Rizika
- **R1 (střední) — vzhled v reálném menu baru** (výška, retina, dark/light) nelze headless 100% ověřit. **Mitigace:** PNG render předem (hotovo), `NSImage` drawingHandler retina, překreslení na `applyAppearance`; user ověří finálně.
- **R2 (nízké) — refaktor `usedPercent` na `selectedWindow`** by mohl změnit číslo. **Mitigace:** existující `usedPercent` testy = pojistka; selectedWindow mirror.
- **R3 (nízké) — přepnutí stylu nevyčistí `button.image`** → zbytek obrázku. **Mitigace:** render při ne-burnBar nastaví `button.image = nil`.
- **R4 (nízké) — šířka dvou skupin** zabere v liště místo. Akceptováno (opt-in styl).
