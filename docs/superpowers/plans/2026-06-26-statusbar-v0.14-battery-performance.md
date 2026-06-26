# StatusBar v0.14 — Baterie & výkon — Implementační plán

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps `- [ ]`.

**Goal:** Udělat z app „dobrého občana macOS" — App Nap / coalescing probuzení (NSBackgroundActivityScheduler), žádné obnovování při zhasnutém displeji, pulzující tečka respektující přístupnost a běžící jen při otevřeném popoveru.

**Architecture:** Čistě App vrstva. `NSBackgroundActivityScheduler` místo `Timer`; `NSWorkspace` sleep/wake observery; nový `PopoverVisibility` ObservableObject přepínaný `MenuBarController`em (NSPopoverDelegate) → `FreshnessDot` animuje jen když je popover otevřený a není zapnuté „Omezit pohyb".

**Tech Stack:** Swift 6 strict concurrency, AppKit (NSBackgroundActivityScheduler, NSWorkspace, NSPopoverDelegate), SwiftUI (accessibilityReduceMotion, EnvironmentObject).

## Global Constraints
- **Žádná změna chování dat ani vzhledu** — jen *kdy*/*jak často* se obnovuje + přístupnost animace. Default chování (60s kadence) zachováno.
- **Nulová regrese:** start refresh + popover-open refresh + 30denní `costHistory.refreshIfStale()` + `updates.checkIfDue()` beze změny. Existujících **174 testů** musí dál procházet (App-only změny, žádné nové Kit testy).
- **Swift 6 sendable (EMPIRICKY OVĚŘENO plan-forge, `swiftc -swift-version 6 -warnings-as-errors`):** scheduler handler `[weak self]` + `Task { @MainActor in … completion(.finished) }` = čisté; NSWorkspace observery (`@Sendable` nonisolated) MUSÍ obalit `@MainActor` přístup do `MainActor.assumeIsolated { }` (queue:.main = hlavní vlákno) — jinak warningy; NSPopoverDelegate na `@MainActor` třídě + `@Published` = čisté.
- **Verze:** 0.14.0 (Info.plist oba klíče). Build 0 warningů. NEspouštět GUI app.

---

### Task 1: AppDelegate — NSBackgroundActivityScheduler + pauza při spánku displeje

**Files:**
- Modify: `Sources/StatusBarApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `coordinator.refreshNow(includeToday:)` (existující `@MainActor async`).
- Produces: nahrazuje `timer: Timer?` za `refreshActivity: NSBackgroundActivityScheduler` + privátní `startRefreshScheduler()`.

- [ ] **Step 1:** V `AppDelegate` NAHRADIT `private var timer: Timer?` (řádek ~15) za:
```swift
    private let refreshActivity = NSBackgroundActivityScheduler(identifier: "cz.rivalio.statusbar.refresh")
```

- [ ] **Step 2:** Přidat privátní metodu (kamkoli v třídě, např. nad `applicationDidFinishLaunching`):
```swift
    private func startRefreshScheduler() {
        refreshActivity.invalidate()   // idempotentní (re-schedule po probuzení)
        refreshActivity.repeats = true
        refreshActivity.interval = 60
        refreshActivity.tolerance = 20
        refreshActivity.qualityOfService = .utility
        refreshActivity.schedule { [weak self] completion in
            // handler běží na background queue → hop na MainActor
            Task { @MainActor in
                await self?.coordinator.refreshNow(includeToday: false)
                completion(.finished)
            }
        }
    }
```

- [ ] **Step 3:** V `applicationDidFinishLaunching`, NAHRADIT blok `timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { … }` (řádky ~74–77) za:
```swift
        startRefreshScheduler()
        // Pauza obnovování, když displej spí (lišta neviditelná); probuzení → znovu naplánovat + 1 refresh.
        // POZOR (Swift 6, empiricky ověřeno plan-forge): observer closure je @Sendable nonisolated →
        // přístup na @MainActor stav (`refreshActivity`, `startRefreshScheduler`) MUSÍ být přes
        // `MainActor.assumeIsolated` (queue:.main běží na hlavním vlákně). Bez toho = warningy (build gate 0 warn padá).
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshActivity.invalidate() }
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.startRefreshScheduler()
                Task { await self.coordinator.refreshNow(includeToday: false) }
            }
        }
```
(POZN.: `NSWorkspace` je už importováno přes `import AppKit`. Existující `Task { await coordinator.refreshNow(includeToday: false) }` start-refresh, `costHistory.refreshIfStale()` a `Task { await updates.checkIfDue() }` ZŮSTÁVAJÍ beze změny.)

- [ ] **Step 4:** Build: `swift build -c debug` → 0 errors, 0 **warnings** (POZOR Swift 6: `schedule` handler `@Sendable`, observer closure `@Sendable`; `[weak self]` + Task hop). Pokud warning „capture of 'self'" → ověřit `[weak self]`.

- [ ] **Step 5:** `swift test` → 174 PASS (žádný App test, ale balíček kompiluje).

- [ ] **Step 6:** Commit:
```bash
git add Sources/StatusBarApp/AppDelegate.swift
git commit -m "perf: NSBackgroundActivityScheduler místo Timer + pauza při spánku displeje"
```

**Pozn. reviewerovi:** `refreshActivity.invalidate()` na začátku `startRefreshScheduler()` zajistí idempotenci (re-schedule po probuzení nezdvojí). `completion(.finished)` se volá po dokončení refreshe uvnitř Tasku. Scheduler sám řeší Low Power Mode / thermal / baterii.

---

### Task 2: PopoverVisibility + NSPopoverDelegate + FreshnessDot (reduce-motion + gated)

**Files:**
- Create: `Sources/StatusBarApp/PopoverVisibility.swift`
- Modify: `Sources/StatusBarApp/MenuBarController.swift`, `Sources/StatusBarApp/PopoverView.swift`

**Interfaces:**
- Produces: `@MainActor final class PopoverVisibility: ObservableObject { @Published var isOpen: Bool }`.
- `MenuBarController` se stává `NSPopoverDelegate`, vlastní `let popoverVisibility = PopoverVisibility()`, injektuje ho `.environmentObject(...)` do `PopoverView` a přepíná v `popoverDidShow`/`popoverDidClose`.
- `FreshnessDot` čte `@EnvironmentObject var vis: PopoverVisibility` + `@Environment(\.accessibilityReduceMotion)`.

- [ ] **Step 1: Vytvořit** `Sources/StatusBarApp/PopoverVisibility.swift`:
```swift
import SwiftUI

/// Sdílený stav, zda je popover otevřený — `FreshnessDot` animuje jen když ano.
@MainActor
final class PopoverVisibility: ObservableObject {
    @Published var isOpen: Bool = false
}
```

- [ ] **Step 2: MenuBarController** — přidat vlastnictví + delegate. V deklaraci třídy přidat:
```swift
    let popoverVisibility = PopoverVisibility()
```
V `init`, kde se staví `NSHostingController(rootView: PopoverView(...))`, přidat na konec view `.environmentObject(popoverVisibility)`:
```swift
        let hosting = NSHostingController(rootView:
            PopoverView(store: store, costHistory: costHistory, updates: updates,
                        onRefresh: onClick, onQuit: { NSApp.terminate(nil) },
                        onOpenSettings: onOpenSettings)
                .environmentObject(popoverVisibility))
```
(POZOR: přesná signatura `PopoverView(...)` dle aktuálního stavu souboru — zkopírovat existující volání a jen přidat `.environmentObject(popoverVisibility)`.)
A nastavit delegate (za `popover.behavior = .transient`):
```swift
        popover.delegate = self
```

- [ ] **Step 3: MenuBarController** — rozšířit o `NSPopoverDelegate`. Změnit deklaraci třídy `final class MenuBarController {` na `final class MenuBarController: NSObject, NSPopoverDelegate {` (NSPopoverDelegate vyžaduje NSObjectProtocol). Pokud třída ještě nedědí z NSObject, přidat `NSObject` a do `init` na ZAČÁTEK přidat `super.init()` (po inicializaci stored properties). Přidat delegate metody:
```swift
    func popoverDidShow(_ notification: Notification) { popoverVisibility.isOpen = true }
    func popoverDidClose(_ notification: Notification) { popoverVisibility.isOpen = false }
```
(POZN.: `@MainActor` třída + NSObject — `super.init()` nutné. Ověřit, že `togglePopover` `@objc` selektor dál funguje.)

- [ ] **Step 4: PopoverView** — `FreshnessDot` přepsat na reduce-motion + gated. NAHRADIT stávající `FreshnessDot`:
```swift
private struct FreshnessDot: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var vis: PopoverVisibility
    @State private var pulse = false
    var body: some View {
        Circle().fill(color).frame(width: 5, height: 5)
            .opacity(pulse ? 0.45 : 1).scaleEffect(pulse ? 0.82 : 1)
            .onAppear { apply(vis.isOpen) }
            .onChange(of: vis.isOpen) { _, open in apply(open) }
    }
    private func apply(_ open: Bool) {
        if open && !reduceMotion {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        } else {
            withAnimation(nil) { pulse = false }   // okamžitě zastav + reset
        }
    }
}
```

- [ ] **Step 5: Build** `swift build -c debug` → 0 errors, 0 warnings.

- [ ] **Step 6: Test** `swift test` → 174 PASS.

- [ ] **Step 7: Commit:**
```bash
git add Sources/StatusBarApp/PopoverVisibility.swift Sources/StatusBarApp/MenuBarController.swift Sources/StatusBarApp/PopoverView.swift
git commit -m "perf+a11y: pulzující tečka jen při otevřeném popoveru + respekt Reduce Motion"
```

**Pozn. reviewerovi:** `@EnvironmentObject PopoverVisibility` MUSÍ být injektován (`.environmentObject` v MenuBarController) — jinak runtime crash. Při zavření popoveru (`isOpen=false`) `apply(false)` → `pulse=false` bez animace → CA heartbeat ustane. Reduce Motion → statická plná tečka.

---

### Task 3: Finalizace — verze 0.14.0 + plný test + release build

**Files:**
- Modify: `Resources/Info.plist`

- [ ] **Step 1:** Bump verze:
```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.14.0" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 0.14.0" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist
```
Expected: `0.14.0`

- [ ] **Step 2:** Plný test `swift test` → 174 PASS.

- [ ] **Step 3:** Release build `swift build -c release` → 0 errors, 0 warnings.

- [ ] **Step 4:** Commit:
```bash
git add Resources/Info.plist
git commit -m "chore: verze 0.14.0 (baterie & výkon)"
```

**Pozn.:** Manuální verifikace (Monitor aktivity App Nap / energie, reduce-motion, spánek displeje) dělá uživatel po rebuildu — orchestrátor po finálním review.

---

## Self-Review (orchestrátor)
- **Spec coverage:** §2.1 scheduler (T1), §2.2 sleep/wake (T1), §2.3 FreshnessDot+PopoverVisibility (T2), verze (T3). ✓ (§2.4 vyhozeno — není v plánu, správně.)
- **Placeholdery:** žádné — kód doslovně. ✓
- **Type consistency:** `PopoverVisibility.isOpen` (T2 def) → `FreshnessDot` čte (T2); `refreshActivity`/`startRefreshScheduler` (T1). ✓
- **Risk R1 (concurrency): VYŘEŠENO** — plan-forge empiricky ověřil (Swift 6 + warnings-as-errors): observery přes `MainActor.assumeIsolated`, scheduler handler + NSPopoverDelegate čisté.
