# StatusBar v0.7a — Přepínatelné styly lišty + význam %

- **Datum:** 2026-06-24
- **Stav:** Návrh (rozsah odsouhlasen uživatelem)
- **Navazuje na:** v0.1–v0.6.
- **Cyklus 1 ze 2 ve v0.7.** Cyklus 2 (Codex/OpenAI živé limity) je samostatný spec.

## 1. Přehled

Menu bar lišta dnes umí jediný styl: barevná tečka per provider + **zbývající %**
(`● 73%  ● 45%`), barva podle nebezpečí. v0.7a přidává:

- **4 přepínatelné styly lišty** A/B/C/D.
- **Přepínač významu čísla:** *zbývající %* (současné) vs *vyčerpané %* (jako Claude TUI `/usage`).
- Obojí volitelné v okně **Nastavení**; **default = současné chování** (styl A + zbývající %),
  takže bez zásahu uživatele se nic nemění (nulové riziko regrese).

### Styly (mockup; data: Claude Code 73 % zbývá / 27 % využito, Codex 45 % / 55 %)

| Styl | Kód | Mockup | Popis |
|---|---|---|---|
| A | `dotPercent` | `● 73%  ● 45%` | Barevná tečka providera + číslo (současný). |
| B | `labelPercent` | `CC 73%  CX 45%` | Písmenný štítek (CC/CX) místo tečky + číslo. |
| C | `dotOnly` | `●  ●` | Jen tečka obarvená podle **stavu**; číslo až v popoveru. |
| D | `worst` | `● 45%` | Jediné číslo = nejnižší zbývající napříč providery/okny. |

### Cíle
- Uživatel si v Nastavení zvolí styl lišty a význam %; lišta se **okamžitě překreslí**.
- Logika stylu je celá v `StatusBarKit` (pure, unit-testovatelná); AppKit jen vykresluje.

### Ne-cíle
- Codex/OpenAI živé limity (samostatný cyklus 2).
- Per-provider odlišné styly, drag-to-reorder, vlastní barvy, ikony SF Symbols (YAGNI).
- Změna popoveru (mění se jen titulek lišty).

## 2. Architektura

Těžiště v Kitu: builder rozhoduje **veškerou** style-logiku a vrací segmenty, které
renderer v AppKitu jen mechanicky vykreslí. Žádné `if styl == …` v AppKitu.

| Komponenta | Vrstva | Odpovědnost | Test |
|---|---|---|---|
| `MenuBarStyle` (enum) | Kit | `String` rawValue (perzistence) `dotPercent`/`labelPercent`/`dotOnly`/`worst` + `displayName` + `init(rawValue:)` s fallbackem na `.dotPercent` | **unit** |
| `MenuBarSegment.Leading` (enum) | Kit | `.providerDot` / `.levelDot` / `.label(String)` / `.none` — jak vykreslit prefix segmentu | (přes builder testy) |
| `MenuBarSegment` (změna) | Kit | přidá pole `leading: Leading` (k stávajícím `providerId`, `text`, `level`) | (přes builder testy) |
| `MenuBarTitleBuilder.segments(for:style:showUsedPercent:)` (změna) | Kit | sestaví segmenty podle stylu + významu % | **unit** (matice) |
| `PreferencesStore` (změna) | Kit | `+barStyle: MenuBarStyle` (default A), `+showUsedPercent: Bool` (default false) | **unit** |
| `MenuBarController.render` (změna) | App | přečte prefs, zavolá builder, vykreslí podle `Leading` | build/smoke |
| `SettingsView` (změna) | App | sekce „Zobrazení lišty": `Picker` stylu + segmented „Zbývající / Vyčerpané"; po změně `onAppearanceChanged()` | build/smoke |
| `AppDelegate` (změna) | App | předá `prefs` do `MenuBarController`; napojí `onAppearanceChanged` → `menuBar.render(...)` | build/smoke |

## 3. Detail: `MenuBarTitleBuilder`

```swift
public static func segments(for usages: [ProviderUsage],
                            style: MenuBarStyle = .dotPercent,
                            showUsedPercent: Bool = false) -> [MenuBarSegment]
```

Default argumenty zachovají stávající volání i testy (kde se mění jen tělo, ne signatura).

**Společné per provider** (status `.ok` i `.degraded` = „zobrazitelný", má data ve `windows`):
- `used = u.nearestLimitPercent` (0–100), `remaining = max(0, 100 - used)`.
- `shown = showUsedPercent ? used : remaining`.
- `level = UsageLevel.level(forPercent: used)` — **vždy z vyčerpaného %** (nebezpečí je nebezpečí; přepínač mění jen zobrazené číslo, ne barvu).
- `.unavailable` → text `"—"`, `level = .normal`.

**Per styl:**
- **A `dotPercent`:** každý zobrazitelný provider → `Segment(providerId, leading: .providerDot, text: "\(shown)%", level)`; `.unavailable` → `(.providerDot, "—", .normal)`.
- **B `labelPercent`:** jako A, ale `leading: .label(shortLabel(providerId))`. `shortLabel`: `claudeCode → "CC"`, `codex → "CX"`.
- **C `dotOnly`:** každý provider → `(.levelDot, "", level)`; `.unavailable` → `(.levelDot, "", .normal)`.
- **D `worst`:** mezi **zobrazitelnými** providery (status ≠ `.unavailable`) vyber toho s **nejvyšším `used`** (= nejnižší zbývající). Vrať **jediný** segment `(.providerDot, "\(shown)%", level)` pro něj. Když žádný zobrazitelný není (vše `.unavailable`) → jediný segment `(.providerDot pro první vstup / nebo .none, "—", .normal)` — viz pozn. níže.

**Pozn. k D bez dat:** když je `usages` prázdné → vrať `[]` (renderer pak ukáže fallback „StatusBar", stejně jako dnes). Když jsou nějaké `usages`, ale všechny `.unavailable` → jediný segment `Segment(providerId: usages[0].providerId, leading: .none, text: "—", level: .normal)`.

## 4. Detail: renderer (`MenuBarController.render`)

Pro každý segment podle `leading`:
- `.providerDot` → `"● "` v barvě providera (`dotColor(providerId)`, font 9).
- `.levelDot` → `"● "` v barvě stavu (`levelColor(level)`, font 9).
- `.label(s)` → `"\(s) "` v barvě stavu (`levelColor(level)`, monospaced semibold 12).
- `.none` → nic.
- Pak `text` (pokud neprázdný) v barvě stavu (`levelColor(level)`, monospaced semibold 12).
- Segmenty oddělené `"  "` (dvě mezery), jako dnes.
- `segs.isEmpty` → `"StatusBar"` (jako dnes).
- Tooltip beze změny (z `usages`).

`render` čte prefs živě (`PreferencesStore` čte z `UserDefaults` při každém volání), takže
po změně v Nastavení stačí `render` znovu zavolat.

## 5. Detail: prefs + propagace změny

`PreferenceKeys`: `+barStyle = "barStyle"`, `+showUsedPercent = "showUsedPercent"`.
`PreferencesStore`:
- `barStyle: MenuBarStyle` — get: `MenuBarStyle(rawValue: defaults.string(forKey:) ?? "") ?? .dotPercent`; set: uloží `rawValue`.
- `showUsedPercent: Bool` — `defaults.bool(forKey:)` (default false), set ukládá.

**Propagace do lišty:** změna `UserDefault` sama lištu nepřekreslí (store `objectWillChange`
se netýká prefs). Zavedeme explicitní hook:
- `MenuBarController` dostane `prefs: PreferencesStore` v initu a má `func applyAppearance()` (= znovu `render(store.orderedUsages)`).
- `SettingsView` dostane closure `onAppearanceChanged: () -> Void`, kterou zavolá po každé změně stylu/významu %.
- `AppDelegate` propojí: `settings = SettingsView(onAppearanceChanged: { [weak menuBar] in menuBar?.applyAppearance() })`.

## 6. SettingsView — UI

Nová sekce **„Zobrazení lišty"** nad stávající sekcí Upozornění:
- `Picker("Styl lišty", selection:)` se 4 položkami z `MenuBarStyle.allCases`, popisky z `displayName`
  (`„Tečka + %"`, `„Štítek + %"`, `„Jen tečka"`, `„Nejkritičtější"`).
- `Picker`/segmented „Číslo ukazuje" → `„Zbývající"` / `„Vyčerpané"` (bind na `showUsedPercent`).
- Vazba na `@AppStorage` nebo na `PreferencesStore` + po `onChange` zavolat `onAppearanceChanged()`.
  (Použít stejný vzor jako stávající přepínače v `SettingsView`.)

## 7. Verifikace a meze

- **Plně ověřitelné (automaticky):** unit testy builderu (matice styl × význam × stav, výběr „worst", all-unavailable, prázdný vstup), `MenuBarStyle` rawValue/fallback/displayName, `PreferencesStore` defaulty + round-trip; `swift build` (Kit i App) čistý; `swift test` zelený; existující testy beze změny chování (default = A + zbývající).
- **GAP (ověří uživatel):** skutečný vizuál stylů v liště a okamžité překreslení po změně v Nastavení (AppKit render + `Picker` = build/smoke, vizuál je na uživateli).

## 8. Fázování (3 tasky)
1. **Kit pure:** `MenuBarStyle` (+displayName/fallback) + `MenuBarSegment.Leading` + `MenuBarTitleBuilder.segments(for:style:showUsedPercent:)` + unit testy (matice). Existující Formatting testy upravit na default-args (chování beze změny).
2. **Kit prefs:** `PreferencesStore.barStyle` + `showUsedPercent` + `PreferenceKeys` + unit testy (default + round-trip).
3. **App:** `MenuBarController` (render podle `Leading`, `applyAppearance`, `prefs` v initu) + `SettingsView` sekce + `AppDelegate` wiring + bundle verze 0.7. Build + smoke.

## 9. Rizika
- **R1 (nízké):** změna signatury `segments(for:)` rozbije volání/testy → mitigace: default argumenty → volání i staré testy beze změny.
- **R2 (nízké):** lišta se po změně v Nastavení nepřekreslí → mitigace: explicitní `onAppearanceChanged` → `applyAppearance()` (ne spoléhat na `objectWillChange`).
- **R3 (nízké):** neznámý uložený `barStyle` rawValue (např. po downgrade) → mitigace: `init(rawValue:)` fallback na `.dotPercent`.
- **R4 (nízké):** styl C/D skryje info (kdo je kdo / druhý provider) → akceptováno: je to opt-in kompaktní volba, plný detail je v popoveru.
