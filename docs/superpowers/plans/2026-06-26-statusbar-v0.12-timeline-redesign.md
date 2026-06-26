# StatusBar v0.12 — Timeline popover + System Settings — Plán

> Implementace: orchestrátor přímo (pixel-precizní SwiftUI, vizuál ověřen ImageRenderer PNG předem), build+test+commit po dávkách, finální Opus review před merge.

**Verze:** 0.12.0. Větev `feat/v0.12-timeline-redesign`. Baseline 168 testů.
Spec: `docs/superpowers/specs/2026-06-26-statusbar-v0.12-timeline-redesign-design.md`.

## Global Constraints
- Nulová regrese: menu bar (burn bar) beze změny; `appearance` default `.system` = beze změny; ostatní featury (update check, notifikace, 30d cena, pace/burn data) nedotčené.
- Lokalizace `bundle: Bundle? = nil`, %/%%, nové klíče en+cs, parity testy zelené.
- Build 0 warningů, plný `swift test`. NEspouštět GUI.

## Dávka 1 — Kit: Appearance + prefs + lokalizace
- `Sources/StatusBarKit/Formatting/Appearance.swift`: `public enum Appearance: String, Sendable, Hashable, CaseIterable { case system, light, dark }` + `displayName(bundle:)` (`appearance.system/light/dark`) + `var displayName`.
- `PreferenceKeys.appearance = "appearance"`; `PreferencesStore.appearance: Appearance` (default `.system`).
- Kit `en/cs` strings: `appearance.system` (Systém/System), `appearance.light` (Světlý/Light), `appearance.dark` (Tmavý/Dark).
- Test `AppearanceTests.swift`: displayName en/cs, allCases, rawValue; `PreferencesUpdateTests` rozšířit o appearance default+persistence.
- **Commit** `feat: Appearance enum (Systém/Světlý/Tmavý) + PreferencesStore.appearance`.

## Dávka 2 — App: reusable views
- `Sources/StatusBarApp/ProviderBadge.swift`: zaoblený čtverec (24, radius 7) accent providera; Claude = sluneční burst (`Canvas`, 8 paprsků inner 0.155·w, outer 0.42·w, bílé, lineWidth 2, round), Codex = `Text(">_")` mono bold. Accent Claude `#D97557`, Codex `#0FA380`.
- `Sources/StatusBarApp/TimelineBarView.swift`: `init(bar: BurnBar)`; výška 10, Capsule track; **plná** `[0, 1−projected]` = `overLimit ? .red : level(projectedLevel)`; **šrafy** `[1−projected, 1−used]` = `overLimit ? .red : level(usedLevel)` (Canvas diagonální pruhy ~0.5 alpha); **ryska** na `1−projected` (mimo clip, přesah ±2). Barvy z `UsageLevel`. (Ověřeno ImageRenderer.)
- **Commit** `feat: ProviderBadge + TimelineBarView (Timeline vizuál, ověřeno renderem)`.

## Dávka 3 — App: PopoverView Timeline redesign
- `ProviderCard` přepsán: badge + název + plan chip + Spacer + freshness (pulzující tečka <3m zelená/<15m amber/jinak červená + `RelativeTimeFormatter`). Per okno: `label · Spacer · tučné „% zbývá" · „reset {čas}"`, `TimelineBarView`, pace+projekce barevně (pozadu→zelená, napřed→amber). 30d útrata, odkazy. Hlavička/patička/update banner zachovány. Šířka 340.
- **Commit** `feat: PopoverView — Timeline redesign (badge, freshness, timeline bary)`.

## Dávka 4 — App: SettingsView System Settings redesign + Vzhled + živý náhled
- `SettingsView` přepsán do karet (`SettingsCard`/`SettingsRow` helpery): Náhled (živý z `store`), Obecné (Launch, **Vzhled** picker), Zobrazení (Styl, Číslo, Okno), Upozornění, Aktualizace.
- `MenuBarPreview` (živý): dot + zbývající bar + % pro `store.orderedUsages` (≤2), reaguje na `showUsedPercent`. Caption.
- `SettingsWindowController`: přidat `store` + `onAppearanceModeChanged` param → `SettingsView`.
- `AppDelegate`: `applyAppearance()` (NSApp.appearance dle prefs, start + onChange), předat `store` do settings.
- App `en/cs` strings: `settings.appearance`, `settings.preview`, `settings.previewCaption` (Styl %@ · číslo %@), případně `settings.watched`.
- **Commit** `feat: SettingsView — System Settings styl + Vzhled přepínač + živý náhled`.

## Dávka 5 — Finalizace
- Parita Kit+App en==cs. Verze 0.12.0 (Info.plist oba klíče). Plný `swift test` + `swift build -c release` 0 warn.
- ImageRenderer smoke celého popoveru + Nastavení (kontrola).
- **Commit** `chore: verze 0.12.0 (Timeline redesign)`.

## Finální review (Opus, fresh) → merge FF → rebuild → uživatel ověří → push na souhlas.
