# StatusBar v0.14 — Baterie & výkon

- **Datum:** 2026-06-26
- **Stav:** Návrh (audit kódu proveden, rozsah + scheduler odsouhlaseny uživatelem).
- **Motivace (uživatel):** „optimalizovat bar pro baterii, rychlost — kvalitní doplněk pro mac." Tento cyklus = proud A (baterie/výkon) z auditu. Proudy B (polish: ikona/About/a11y) a C (zveřejnění: LICENSE/README/distribuce) jsou samostatné budoucí cykly.
- **Verze:** 0.14.0. Větev `feat/v0.14-battery-performance`. Baseline 174 testů.

## 1. Přehled
Tři změny, aby byla app „dobrý občan macOS" (App Nap, coalescing probuzení, žádné polování neviditelné lišty, respekt přístupnosti). Žádná změna chování dat ani vzhledu — jen *kdy* a *jak často* se věci dějí.

### Cíle
- App se kvalifikuje pro App Nap; probuzení slučovaná OS; obnovování se odkládá při zátěži/baterii/Low Power Mode.
- Žádné obnovování, když je displej zhasnutý (lišta neviditelná).
- Pulzující tečka respektuje „Omezit pohyb" a neběží, když je popover zavřený.

### Ne-cíle (YAGNI — auditem nízký dopad, odloženo)
- `discretionary`/vlastní URLSession config (u běžné session reálně skoro nic; frekvenci řídí 5min throttle).
- Přesun dnešního skenu mimo cooperative pool (sken malý, NEběží na hlavním vlákně — ověřeno, `RefreshCoordinator.refreshNow` spouští `fetch` přes `withTaskGroup.addTask` = cooperative pool, ne MainActor).
- **Diff překreslení lišty** (signatura render-vstupů) — vyhozeno pro štíhlejší rozsah: auditem nízký dopad a u stylu burnBar/Timeline (který uživatel používá) by projekce v baru beztak vynutila re-render.
- Žádné nové featury, žádný vizuální redesign.

## 2. Architektura (vše App vrstva)

| Komponenta | Změna | Test |
|---|---|---|
| `AppDelegate` | Timer → `NSBackgroundActivityScheduler`; observery spánku displeje; `applyAppearance` netknuté | build/smoke |
| `AppDelegate` (sleep/wake) | `NSWorkspace.screensDidSleep/Wake` → invalidate/re-schedule + refresh | build/smoke |
| `PopoverVisibility` (nový, App) | `@MainActor final class ObservableObject { @Published var isOpen }` | — |
| `MenuBarController` | `NSPopoverDelegate` → přepíná `PopoverVisibility` (didShow/didClose) | build/smoke |
| `FreshnessDot` (PopoverView) | respekt `accessibilityReduceMotion` + animace jen když `isOpen` | build/smoke |

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

## 3. Verifikace a meze
- **Auto:** žádná nová Kit logika → žádné nové unit testy; existujících 174 testů musí dál procházet (App-only změny). `swift build` (0 warningů, Swift 6 sendable u observerů/scheduler handleru) + `swift test`.
- **GAP (uživatel/manuální):** App Nap status + nízká energie v Monitoru aktivity; reduce-motion → statická tečka; spánek displeje → obnovování se zastaví, probuzení → jeden refresh.

## 4. Rizika
- **R1 (střední) — Swift 6 concurrency u scheduler handleru + NSWorkspace observerů.** Handler `NSBackgroundActivityScheduler` běží na background queue; `@Sendable` closure → `Task { @MainActor }`. Observery `queue: .main` ale closure musí být `@Sendable`. Mitigace: `[weak self]` + hop přes Task; plan-forge ověří compile.
- **R2 (nízké) — `NSBackgroundActivityScheduler` odkládá víc, čísla v liště občas starší.** Akceptováno (popover-open si vynutí refresh; síť stejně 5min throttle).
- **R3 (nízké) — `PopoverVisibility` env object plumbing** přes hlubokou hierarchii. Mitigace: `.environmentObject` na rootu, `@EnvironmentObject` ve `FreshnessDot`.
- **R4 (nízké) — `screensDidSleep` při externím monitoru / clamshell** může chovat různě. Akceptováno (degraduje na „refresh jako dřív").
