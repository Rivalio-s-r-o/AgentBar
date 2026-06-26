# StatusBar v0.14 — Baterie & výkon

- **Datum:** 2026-06-26
- **Stav:** Návrh (audit kódu proveden, rozsah + scheduler odsouhlaseny uživatelem).
- **Motivace (uživatel):** „optimalizovat bar pro baterii, rychlost — kvalitní doplněk pro mac." Tento cyklus = proud A (baterie/výkon) z auditu. Proudy B (polish: ikona/About/a11y) a C (zveřejnění: LICENSE/README/distribuce) jsou samostatné budoucí cykly.
- **Verze:** 0.14.0. Větev `feat/v0.14-battery-performance`. Baseline 174 testů.

## 1. Přehled
Pět změn, aby byla app „dobrý občan macOS" (App Nap, coalescing probuzení, žádné polování neviditelné lišty, respekt přístupnosti, žádná zbytečná práce). Žádná změna chování dat ani vzhledu — jen *kdy* a *jak často* se věci dějí.

### Cíle
- App se kvalifikuje pro App Nap; probuzení slučovaná OS; obnovování se odkládá při zátěži/baterii/Low Power Mode.
- Žádné obnovování, když je displej zhasnutý (lišta neviditelná).
- Pulzující tečka respektuje „Omezit pohyb" a neběží, když je popover zavřený.
- Lišta se nepřekresluje, když se data nezměnila.

### Ne-cíle (YAGNI — auditem nízký dopad, odloženo)
- `discretionary`/vlastní URLSession config (u běžné session reálně skoro nic; frekvenci řídí 5min throttle).
- Přesun dnešního skenu mimo cooperative pool (sken malý, NEběží na hlavním vlákně — ověřeno, `RefreshCoordinator.refreshNow` spouští `fetch` přes `withTaskGroup.addTask` = cooperative pool, ne MainActor).
- Žádné nové featury, žádný vizuální redesign.

## 2. Architektura (vše App vrstva mimo §2.4)

| Komponenta | Změna | Test |
|---|---|---|
| `AppDelegate` | Timer → `NSBackgroundActivityScheduler`; observery spánku displeje; `applyAppearance` netknuté | build/smoke |
| `AppDelegate` (sleep/wake) | `NSWorkspace.screensDidSleep/Wake` → invalidate/re-schedule + refresh | build/smoke |
| `PopoverVisibility` (nový, App) | `@MainActor final class ObservableObject { @Published var isOpen }` | — |
| `MenuBarController` | `NSPopoverDelegate` → přepíná `PopoverVisibility`; render přeskočí když signatura beze změny | (signatura Kit) |
| `FreshnessDot` (PopoverView) | respekt `accessibilityReduceMotion` + animace jen když `isOpen` | build/smoke |
| `MenuBarRenderSignature` (nový, Kit) | čistá signatura render-vstupů + `Equatable` | **unit** |

### 2.1 Periodické obnovování → `NSBackgroundActivityScheduler`
V `AppDelegate` nahradit `timer = Timer.scheduledTimer(withTimeInterval: 60, …)`:
```swift
private let refreshActivity = NSBackgroundActivityScheduler(identifier: "cz.rivalio.statusbar.refresh")
…
refreshActivity.repeats = true
refreshActivity.interval = 60
refreshActivity.tolerance = 20
refreshActivity.qualityOfService = .utility
startRefreshScheduler()
```
```swift
private func startRefreshScheduler() {
    refreshActivity.schedule { [weak self] completion in
        // handler běží na background queue → hop na MainActor
        Task { @MainActor in
            await self?.coordinator.refreshNow(includeToday: false)
            completion(.finished)
        }
    }
}
```
- `interval = 60` zachová dnešní kadenci; `tolerance = 20` umožní OS slučovat. Scheduler sám **odkládá při Low Power Mode / thermal / baterii** → free low-power awareness.
- Start (`refreshNow(includeToday:false)`), 30denní `costHistory.refreshIfStale()` i `updates.checkIfDue()` při startu a popover-open **beze změny**.
- `.completion(.finished)` po dokončení (ne `.deferred`).

### 2.2 Pauza při spánku displeje
V `applicationDidFinishLaunching` zaregistrovat:
```swift
let nc = NSWorkspace.shared.notificationCenter
nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
    self?.refreshActivity.invalidate()
}
nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
    guard let self else { return }
    self.startRefreshScheduler()                                   // znovu naplánovat
    Task { await self.coordinator.refreshNow(includeToday: false) } // jeden okamžitý refresh
}
```
- `invalidate()` zastaví scheduler; `startRefreshScheduler()` ho znovu naplánuje. (Systémový spánek řeší scheduler sám; tohle řeší zhasnutý displej při bdícím systému = neviditelná lišta.)
- POZN.: observery na `.main` queue; `@MainActor` AppDelegate — closure hopne přes `Task { @MainActor }` kde volá async. Ověřit Swift 6 sendable (closure zachytává `self` weak; `@Sendable`).

### 2.3 Pulzující tečka (FreshnessDot)
- `@Environment(\.accessibilityReduceMotion) private var reduceMotion`.
- `@EnvironmentObject var popoverVisibility: PopoverVisibility` (injektováno na root PopoverView přes `.environmentObject`).
- Animace se spustí **jen** když `!reduceMotion && popoverVisibility.isOpen`; jinak statická tečka (plná barva, bez pulzu). Při zavření popoveru (`isOpen = false`) se `pulse` resetuje a animace se zastaví.
```swift
private struct FreshnessDot: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var vis: PopoverVisibility
    @State private var pulse = false
    var body: some View {
        Circle().fill(color).frame(width: 5, height: 5)
            .opacity(pulse ? 0.45 : 1).scaleEffect(pulse ? 0.82 : 1)
            .onChange(of: vis.isOpen) { _, open in update(open) }
            .onAppear { update(vis.isOpen) }
    }
    private func update(_ open: Bool) {
        if open && !reduceMotion {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        } else {
            withAnimation(.linear(duration: 0)) { pulse = false }
        }
    }
}
```

### 2.4 Signatura překreslení lišty (Kit, pure, testovatelné)
Nový `MenuBarRenderSignature` (Kit) = `Equatable` snímek toho, co určuje vzhled lišty, NEZÁVISLE na `lastUpdated` (které se mění každý fetch i při stejných číslech):
```swift
public struct MenuBarRenderSignature: Equatable, Sendable {
    // per zobrazený provider: id, leading kind+text, %text, level; pro burnBar: BurnBar?+percent
    // (přesný tvar dotáhne plán — stačí Equatable a deterministicky odvozený z render-vstupů)
}
```
Buildr: `MenuBarRenderSignature.make(usages:style:showUsedPercent:source:providers:now:)` (now jen tam, kde už segments/burnBar `now` berou — pozor: burnBar projekce závisí na `now` → signatura se MĚNÍ s časem, takže diff by burnBar nikdy nepřeskočil. **Rozhodnutí:** pro burnBar styl signatura zahrne `BurnBar` (used/projected/levels/overLimit) — ty se s časem mění jen pomalu (projekce), ale mění → diff u burnBaru bude skoro vždy re-renderovat. Pro burnBar tedy diff NEpřináší zisk; přínos je hlavně u textových stylů (dotPercent/labelPercent/dotOnly/worst), kde se signatura mění jen při změně % nebo levelu. **Akceptováno:** diff přeskočí redundantní re-render u textových stylů; u burnBaru re-renderuje dál (projekce se mění). To je korektní — burnBar SE vizuálně mění.)

`MenuBarController` drží `lastSignature`; v `render`: spočítat novou signaturu z (filtrovaných) usages + prefs; pokud `== lastSignature` → `return` (nepřekreslovat); jinak vykreslit + uložit. Tooltip se aktualizuje vždy? Ne — tooltip taky jen při změně (součást rozhodnutí; jednodušší: přeskočit celý render včetně tooltipu, protože tooltip se mění se stejnými daty).

**R-OVĚŘENÍ (plan-forge):** že signatura je deterministická, Equatable, a že pro identická data (textový styl) vrací shodu (diff přeskočí), ale při změně %/level/providerů/stylu se liší (re-render proběhne). Že `lastUpdated` NENÍ v signatuře.

## 3. Verifikace a meze
- **Auto (Kit):** `MenuBarRenderSignature` — determinismus, Equatable, shoda při identických datech textového stylu, rozdíl při změně %/level/style/providers, `lastUpdated` ignorováno. `swift build` + `swift test`.
- **GAP (uživatel/manuální):** App Nap status + nízká energie v Monitoru aktivity; reduce-motion → statická tečka; spánek displeje → obnovování se zastaví, probuzení → jeden refresh; lišta se po 60 s nepřekresluje při stejných číslech (těžko pozorovatelné — spíš měření energie).
- **Build:** 0 warningů, Swift 6 sendable u observerů/scheduler handleru.

## 4. Rizika
- **R1 (střední) — Swift 6 concurrency u scheduler handleru + NSWorkspace observerů.** Handler `NSBackgroundActivityScheduler` běží na background queue; `@Sendable` closure → `Task { @MainActor }`. Observery `queue: .main` ale closure musí být `@Sendable`. Mitigace: `[weak self]` + hop přes Task; plan-forge ověří compile.
- **R2 (nízké) — `NSBackgroundActivityScheduler` odkládá víc, čísla v liště občas starší.** Akceptováno (popover-open si vynutí refresh; síť stejně 5min throttle).
- **R3 (nízké) — diff signatura u burnBaru nepřeskočí** (projekce se mění s časem). Akceptováno — burnBar se vizuálně mění; zisk je u textových stylů.
- **R4 (nízké) — `PopoverVisibility` env object plumbing** přes hlubokou hierarchii. Mitigace: `.environmentObject` na rootu, `@EnvironmentObject` ve `FreshnessDot`.
- **R5 (nízké) — `screensDidSleep` při externím monitoru / clamshell** může chovat různě. Akceptováno (degraduje na „refresh jako dřív").
