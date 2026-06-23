# StatusBar v0.3 — Upozornění na spotřebu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Volitelné (default vypnuté) macOS notifikace, když u některého `.ok` poskytovatele klesne zbývající % okna na/pod nastavený práh (default 10 %), s dedup per okno a konfigurovatelným prahem v popoveru.

**Architecture:** Čisté jádro v `StatusBarKit` (`AlertKey`/`AlertEvent`/`AlertEvaluator`, `PreferencesStore`/`PreferenceKeys`, `Hashable` na `WindowKind`). Tenká app vrstva v `StatusBarApp` (`NotificationService` nad `UNUserNotificationCenter`, wiring v `AppDelegate` přes nový `RefreshCoordinator.onRefreshed` callback, přepínač v `PopoverView`). Limit/today část z v0.1/v0.2 zůstává nedotčená.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing, AppKit/SwiftUI, UserNotifications. macOS 14+. Navazuje na v0.2 (`main` na `edcea44`; větev `feat/v0.3-notifications` z `eac194d`).

## Global Constraints

- macOS 14+, Swift 6 (`swift-tools-version: 6.0`), Swift Testing (`@Test`/`#expect`).
- Swift 6 strict concurrency: žádný non-`Sendable` `static let` (formáttery/dekodéry lokálně). `UserDefaults` NENÍ `Sendable` → `PreferencesStore` NEoznačovat `Sendable`.
- **`UNUserNotificationCenter` se smí dotknout JEN v app targetu (`StatusBarApp`), NIKDY v `StatusBarKit` ani v testech** — `swift test` běží bez bundlu a spadl by. `NotificationService.center` je `lazy` (vznikne až při prvním použití, tj. když uživatel zapne notifikace).
- **Default vypnuto:** `notificationsEnabled` default `false`. Dokud uživatel nezapne, nevolá se `AlertEvaluator`, ani se nežádá o povolení — spuštění appky nic nemění.
- Práh = „zbývající ≤ N %", `remaining = max(0, 100 − round(usedFraction*100))` — stejný vzorec jako v0.1 UI.
- Vyhodnocují se JEN okna poskytovatelů se `status == .ok` (čerstvá data); `degraded`/`unavailable` se ignorují.
- Dedup: stav (`Set<AlertKey>`) v paměti `AppDelegate`; klíč se přidá pro každé okno ≤ práh, znovu „nabije" (zmizí ze stavu) jakmile okno vystoupá nad práh.
- Sdílené klíče UserDefaults: konstanty `PreferenceKeys` v `StatusBarKit` (čte je i `@AppStorage` v UI i `PreferencesStore` v koordinátoru).
- Limit-část v0.1 a today-část v0.2 se NEMĚNÍ (kromě přidání `Hashable` na `WindowKind` a `onRefreshed` na `RefreshCoordinator`, oboje aditivní s defaultem).
- TDD stub-first (SwiftPM kompiluje celý cíl; „red" = selhaný `#expect`, ne compile error). Commit po každém tasku.

---

### Task 1: `Hashable` na `WindowKind` + `AlertKey`/`AlertEvent`/`AlertEvaluator`

**Files:**
- Modify: `Sources/StatusBarKit/Models/ProviderUsage.swift` (přidat `Hashable` na `WindowKind`)
- Create: `Sources/StatusBarKit/Alerts/AlertEvaluator.swift`
- Test: `Tests/StatusBarKitTests/AlertEvaluatorTests.swift`

**Interfaces:**
- Produces: `struct AlertKey: Hashable, Sendable { providerId: ProviderID; window: WindowKind }`; `struct AlertEvent: Equatable, Sendable { providerDisplayName: String; windowLabel: String; remainingPercent: Int; resetAt: Date? }`; `enum AlertEvaluator { static func evaluate(usages: [ProviderUsage], thresholdPercent: Int, alreadyAlerted: Set<AlertKey>) -> (toFire: [AlertEvent], newState: Set<AlertKey>) }`.

- [ ] **Step 1: Modify `ProviderUsage.swift` — `Hashable` na `WindowKind`.**

Najdi přesně (`old_string`):

```swift
public enum WindowKind: Sendable, Equatable {
    case rolling5h
    case weekly(scope: String?)
}
```

a nahraď (`new_string`):

```swift
public enum WindowKind: Sendable, Hashable {
    case rolling5h
    case weekly(scope: String?)
}
```

(`Hashable` rozšiřuje `Equatable`; `String?` je `Hashable` → syntéza projde. `ProviderID` je raw-`String` enum bez asociovaných hodnot → už `Hashable`.)

- [ ] **Step 2: Stub `Sources/StatusBarKit/Alerts/AlertEvaluator.swift`**

```swift
import Foundation

public struct AlertKey: Hashable, Sendable {
    public let providerId: ProviderID
    public let window: WindowKind
    public init(providerId: ProviderID, window: WindowKind) {
        self.providerId = providerId; self.window = window
    }
}

public struct AlertEvent: Equatable, Sendable {
    public let providerDisplayName: String
    public let windowLabel: String
    public let remainingPercent: Int
    public let resetAt: Date?
    public init(providerDisplayName: String, windowLabel: String, remainingPercent: Int, resetAt: Date?) {
        self.providerDisplayName = providerDisplayName; self.windowLabel = windowLabel
        self.remainingPercent = remainingPercent; self.resetAt = resetAt
    }
}

public enum AlertEvaluator {
    public static func evaluate(
        usages: [ProviderUsage],
        thresholdPercent: Int,
        alreadyAlerted: Set<AlertKey>
    ) -> (toFire: [AlertEvent], newState: Set<AlertKey>) {
        ([], [])   // STUB
    }
}
```

- [ ] **Step 3: Test `Tests/StatusBarKitTests/AlertEvaluatorTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

private func usage(_ id: ProviderID, _ name: String, _ status: ProviderStatus, _ used: [Double]) -> ProviderUsage {
    ProviderUsage(providerId: id, displayName: name, planLabel: nil,
        windows: used.map { UsageWindow(kind: .rolling5h, usedFraction: $0, resetAt: nil) },
        status: status, lastUpdated: Date())
}

@Test func přechodPodPrahPálíJednou() {
    let u = [usage(.claudeCode, "Claude Code", .ok, [0.92])]   // remaining 8 ≤ 10
    let (fire, state) = AlertEvaluator.evaluate(usages: u, thresholdPercent: 10, alreadyAlerted: [])
    #expect(fire.count == 1)
    #expect(fire[0].remainingPercent == 8)
    #expect(state.contains(AlertKey(providerId: .claudeCode, window: .rolling5h)))
    // setrvání pod prahem se stejným stavem → žádný re-fire
    let (fire2, state2) = AlertEvaluator.evaluate(usages: u, thresholdPercent: 10, alreadyAlerted: state)
    #expect(fire2.isEmpty)
    #expect(state2 == state)
}

@Test func zotaveníNadPrahRearm() {
    let key = AlertKey(providerId: .claudeCode, window: .rolling5h)
    let recovered = [usage(.claudeCode, "Claude Code", .ok, [0.50])]   // remaining 50 > 10
    let (fire, state) = AlertEvaluator.evaluate(usages: recovered, thresholdPercent: 10, alreadyAlerted: [key])
    #expect(fire.isEmpty)
    #expect(!state.contains(key))   // odbito → příště zase upozorní
    // opětovný přechod po rearmu → fire znovu
    let low = [usage(.claudeCode, "Claude Code", .ok, [0.95])]
    let (fire2, _) = AlertEvaluator.evaluate(usages: low, thresholdPercent: 10, alreadyAlerted: state)
    #expect(fire2.count == 1)
}

@Test func hraniceRovnostPálí() {
    let u = [usage(.codex, "Codex", .ok, [0.90])]   // remaining 10 == threshold → ≤ → fire
    let (fire, _) = AlertEvaluator.evaluate(usages: u, thresholdPercent: 10, alreadyAlerted: [])
    #expect(fire.count == 1)
    #expect(fire[0].remainingPercent == 10)
}

@Test func degradedAUnavailableSeIgnorují() {
    let u = [
        usage(.claudeCode, "Claude Code", .degraded("stará"), [0.99]),
        usage(.codex, "Codex", .unavailable("nic"), [0.99]),
    ]
    let (fire, state) = AlertEvaluator.evaluate(usages: u, thresholdPercent: 10, alreadyAlerted: [])
    #expect(fire.isEmpty)
    #expect(state.isEmpty)
}

@Test func víceOkenNezávisle() {
    var u = ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
        windows: [
            UsageWindow(kind: .rolling5h, usedFraction: 0.95, resetAt: nil),         // remaining 5 ≤ 10 → fire
            UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.40, resetAt: nil) // remaining 60 → ne
        ], status: .ok, lastUpdated: Date())
    let (fire, state) = AlertEvaluator.evaluate(usages: [u], thresholdPercent: 10, alreadyAlerted: [])
    #expect(fire.count == 1)
    #expect(state == [AlertKey(providerId: .claudeCode, window: .rolling5h)])
    _ = u
}
```

- [ ] **Step 4: Run → RED.** `swift test --filter AlertEvaluatorTests` → Expected: FAIL (stub vrací `([], [])`).
- [ ] **Step 5: Implementuj** — nahraď tělo `evaluate`:

```swift
        var toFire: [AlertEvent] = []
        var newState: Set<AlertKey> = []
        for u in usages {
            guard case .ok = u.status else { continue }      // jen čerstvá data
            for w in u.windows {
                let remaining = max(0, 100 - Int((w.usedFraction * 100).rounded()))
                guard remaining <= thresholdPercent else { continue }   // nad prahem → klíč se nepřidá (rearm)
                let key = AlertKey(providerId: u.providerId, window: w.kind)
                newState.insert(key)
                if !alreadyAlerted.contains(key) {
                    toFire.append(AlertEvent(
                        providerDisplayName: u.displayName,
                        windowLabel: WindowLabel.text(for: w.kind),
                        remainingPercent: remaining,
                        resetAt: w.resetAt))
                }
            }
        }
        return (toFire, newState)
```

- [ ] **Step 6: Run → GREEN.** `swift test --filter AlertEvaluatorTests` → Expected: 5 PASS.
- [ ] **Step 7: Run full + build.** `swift test` → Expected: vše PASS (v0.1/v0.2 + 5 nové). `swift build` čistý.
- [ ] **Step 8: Commit.**

```bash
git add Sources/StatusBarKit/Models/ProviderUsage.swift Sources/StatusBarKit/Alerts Tests/StatusBarKitTests
git commit -m "feat: AlertEvaluator — vyhodnocení prahových upozornění (čisté jádro)"
```

**Verify success (Task 1):** `swift test` vše PASS; `swift build` čistý.
**On failure:** `old_string` v Step 1 nesedí → přečti reálný `ProviderUsage.swift`, přidej `Hashable` na skutečnou deklaraci `WindowKind`. ZASTAV, neimprovizuj.

---

### Task 2: `PreferencesStore` + `PreferenceKeys`

**Files:**
- Create: `Sources/StatusBarKit/Preferences/PreferencesStore.swift`
- Test: `Tests/StatusBarKitTests/PreferencesStoreTests.swift`

**Interfaces:**
- Produces: `enum PreferenceKeys { static let notificationsEnabled: String; static let remainingThresholdPercent: String }`; `struct PreferencesStore { init(defaults: UserDefaults = .standard); var notificationsEnabled: Bool { get nonmutating set }; var remainingThresholdPercent: Int { get nonmutating set } }`.

- [ ] **Step 1: Stub `Sources/StatusBarKit/Preferences/PreferencesStore.swift`**

```swift
import Foundation

public enum PreferenceKeys {
    public static let notificationsEnabled = "notificationsEnabled"
    public static let remainingThresholdPercent = "remainingThresholdPercent"
}

public struct PreferencesStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var notificationsEnabled: Bool {
        get { false }                              // STUB
        nonmutating set { }                        // STUB
    }
    public var remainingThresholdPercent: Int {
        get { 0 }                                  // STUB
        nonmutating set { }                        // STUB
    }
}
```

- [ ] **Step 2: Test `Tests/StatusBarKitTests/PreferencesStoreTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

private func freshDefaults() -> (UserDefaults, String) {
    let suite = "test-prefs-\(UUID().uuidString)"
    return (UserDefaults(suiteName: suite)!, suite)
}

@Test func defaultyJsouVypnutoA10() {
    let (ud, suite) = freshDefaults()
    defer { ud.removePersistentDomain(forName: suite) }
    let store = PreferencesStore(defaults: ud)
    #expect(store.notificationsEnabled == false)
    #expect(store.remainingThresholdPercent == 10)
}

@Test func uloženíANačtení() {
    let (ud, suite) = freshDefaults()
    defer { ud.removePersistentDomain(forName: suite) }
    let store = PreferencesStore(defaults: ud)
    store.notificationsEnabled = true
    store.remainingThresholdPercent = 15
    // nová instance nad stejným UserDefaults vidí uložené hodnoty
    let reread = PreferencesStore(defaults: ud)
    #expect(reread.notificationsEnabled == true)
    #expect(reread.remainingThresholdPercent == 15)
}
```

- [ ] **Step 3: Run → RED.** `swift test --filter PreferencesStoreTests` → Expected: FAIL (`defaultyJsou…` čeká 10, stub vrací 0; `uložení…` neuloží).
- [ ] **Step 4: Implementuj** — nahraď čtyři STUB:

```swift
    public var notificationsEnabled: Bool {
        get { defaults.bool(forKey: PreferenceKeys.notificationsEnabled) }   // default false
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.notificationsEnabled) }
    }
    public var remainingThresholdPercent: Int {
        get {
            let v = defaults.integer(forKey: PreferenceKeys.remainingThresholdPercent)
            return v == 0 ? 10 : v   // 0 = neuloženo → default 10 (UI nabízí jen 5/10/15/20)
        }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.remainingThresholdPercent) }
    }
```

- [ ] **Step 5: Run → GREEN.** `swift test --filter PreferencesStoreTests` → Expected: 2 PASS.
- [ ] **Step 6: Run full + build.** `swift test` → Expected: vše PASS. `swift build` čistý.
- [ ] **Step 7: Commit.**

```bash
git add Sources/StatusBarKit/Preferences Tests/StatusBarKitTests
git commit -m "feat: PreferencesStore — perzistence zapnutí + prahu notifikací"
```

**Verify success (Task 2):** `swift test` vše PASS.

---

### Task 3: `NotificationService` + wiring (`RefreshCoordinator.onRefreshed` → `AppDelegate`)

**Files:**
- Modify: `Sources/StatusBarKit/Store/RefreshCoordinator.swift` (přidat `onRefreshed` callback)
- Create: `Sources/StatusBarApp/NotificationService.swift`
- Modify: `Sources/StatusBarApp/AppDelegate.swift` (prefs + notifier + lastAlerted + napojení callbacku)

**Interfaces:**
- Consumes: `AlertEvaluator`, `AlertKey`, `AlertEvent`, `PreferencesStore`, `ResetFormatter`.
- Produces: `RefreshCoordinator.onRefreshed: ([ProviderUsage]) -> Void`; `@MainActor final class NotificationService { func requestAuthorizationIfNeeded(); func post(_ events: [AlertEvent]) }`.

- [ ] **Step 1: Modify `RefreshCoordinator.swift` — přidat `onRefreshed` callback.**

Najdi přesně (`old_string`):

```swift
    public init(store: UsageStore, providers: [any UsageProvider]) { self.store = store; self.providers = providers }
    public func refreshNow() async {
        var results: [ProviderUsage] = []
        await withTaskGroup(of: ProviderUsage.self) { group in
            for p in providers { group.addTask { await p.fetch() } }
            for await u in group { results.append(u) }
        }
        store.replaceAll(results)
    }
```

a nahraď (`new_string`):

```swift
    /// Zavolá se po každém refreshi s novými daty (default no-op). App vrstva sem napojí vyhodnocení upozornění.
    public var onRefreshed: ([ProviderUsage]) -> Void = { _ in }
    public init(store: UsageStore, providers: [any UsageProvider]) { self.store = store; self.providers = providers }
    public func refreshNow() async {
        var results: [ProviderUsage] = []
        await withTaskGroup(of: ProviderUsage.self) { group in
            for p in providers { group.addTask { await p.fetch() } }
            for await u in group { results.append(u) }
        }
        store.replaceAll(results)
        onRefreshed(results)
    }
```

(Aditivní; default no-op → v0.1 `RefreshCoordinatorTests` dál procházejí.)

- [ ] **Step 2: Vytvoř `Sources/StatusBarApp/NotificationService.swift`**

```swift
import Foundation
import UserNotifications
import StatusBarKit

@MainActor
final class NotificationService {
    // lazy: UNUserNotificationCenter.current() se dotkneme až při prvním použití (po opt-inu),
    // nikdy ne při startu appky a nikdy v testech.
    private lazy var center = UNUserNotificationCenter.current()

    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            self.center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func post(_ events: [AlertEvent]) {
        guard !events.isEmpty else { return }
        for e in events {
            let content = UNMutableNotificationContent()
            content.title = "\(e.providerDisplayName) — \(e.windowLabel)"
            var body = "Zbývá \(e.remainingPercent) %"
            if let r = e.resetAt { body += " · reset za \(ResetFormatter.short(until: r, now: Date()))" }
            content.body = body
            content.sound = .default
            let id = "\(e.providerDisplayName)|\(e.windowLabel)"   // stabilní per okno → re-fire nahrazuje
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }
}
```

- [ ] **Step 3: Modify `AppDelegate.swift` — prefs + notifier + lastAlerted + callback.**

Najdi přesně (`old_string`):

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var coordinator: RefreshCoordinator!
    private var menuBar: MenuBarController!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = RefreshCoordinator(store: store, providers: [ClaudeCodeCollector(), CodexCollector()])
        menuBar = MenuBarController(store: store, onClick: { [weak self] in
            Task { await self?.coordinator.refreshNow() }
        })
        Task { await coordinator.refreshNow() }
```

a nahraď (`new_string`):

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private let prefs = PreferencesStore()
    private let notifier = NotificationService()
    private var lastAlerted: Set<AlertKey> = []
    private var coordinator: RefreshCoordinator!
    private var menuBar: MenuBarController!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = RefreshCoordinator(store: store, providers: [ClaudeCodeCollector(), CodexCollector()])
        coordinator.onRefreshed = { [weak self] usages in
            guard let self, self.prefs.notificationsEnabled else { return }
            let (toFire, newState) = AlertEvaluator.evaluate(
                usages: usages,
                thresholdPercent: self.prefs.remainingThresholdPercent,
                alreadyAlerted: self.lastAlerted)
            self.lastAlerted = newState
            self.notifier.post(toFire)
        }
        menuBar = MenuBarController(store: store, onClick: { [weak self] in
            Task { await self?.coordinator.refreshNow() }
        })
        Task { await coordinator.refreshNow() }
```

(Zbytek `applicationDidFinishLaunching` — Timer — zůstává beze změny.)

- [ ] **Step 4: Run + build.** `swift test` → Expected: vše PASS (žádný nový unit test — `NotificationService` je app-level, ověřuje se buildem; jádro pokryto Task 1/2). `swift build` čistý (app target kompiluje s `UserNotifications`).
- [ ] **Step 5: Commit.**

```bash
git add Sources/StatusBarKit/Store/RefreshCoordinator.swift Sources/StatusBarApp/NotificationService.swift Sources/StatusBarApp/AppDelegate.swift
git commit -m "feat: NotificationService + napojení vyhodnocení upozornění do refresh cyklu"
```

**Verify success (Task 3):** `swift build` čistý vč. app targetu; `swift test` vše PASS.
**On failure:** kterýkoli `old_string` nesedí → přečti reálný soubor a aplikuj princip. ZASTAV, neimprovizuj.

---

### Task 4: Popover UI — přepínač upozornění + výběr prahu + povolení; verze 0.3

**Files:**
- Modify: `Sources/StatusBarApp/PopoverView.swift` (sekce „Upozornění")
- Modify: `Sources/StatusBarApp/MenuBarController.swift` (předat closure pro povolení)
- Modify: `Sources/StatusBarApp/AppDelegate.swift` (dodat closure povolení do `MenuBarController`)
- Modify: `Resources/Info.plist` (verze 0.3)

**Interfaces:**
- Consumes: `PreferenceKeys`, `NotificationService`.
- UI: přepínač přes `@AppStorage(PreferenceKeys.notificationsEnabled)` + výběr prahu `@AppStorage(PreferenceKeys.remainingThresholdPercent)`; při zapnutí volá injektovaný `onRequestNotificationPermission`.

- [ ] **Step 1: Modify `PopoverView.swift` — přidat stored closure + import.**

Najdi přesně (`old_string`):

```swift
struct PopoverView: View {
    @ObservedObject var store: UsageStore
    let onRefresh: () -> Void
    let onQuit: () -> Void
```

a nahraď (`new_string`):

```swift
struct PopoverView: View {
    @ObservedObject var store: UsageStore
    let onRefresh: () -> Void
    let onQuit: () -> Void
    var onRequestNotificationPermission: () -> Void = {}

    @AppStorage(PreferenceKeys.notificationsEnabled) private var notifsEnabled = false
    @AppStorage(PreferenceKeys.remainingThresholdPercent) private var threshold = 10
```

- [ ] **Step 2: Modify `PopoverView.swift` — vložit sekci „Upozornění" před „Konec" řádek.**

Najdi přesně (`old_string`):

```swift
            HStack { Spacer(); Button("Konec", action: onQuit).buttonStyle(.borderless).font(.caption) }
                .padding(.horizontal, 14).padding(.vertical, 8)
        }.frame(width: 320)
```

a nahraď (`new_string`):

```swift
            Divider()
            HStack(spacing: 6) {
                Toggle(isOn: $notifsEnabled) {
                    Text("Upozornit při zbývajících ≤").font(.caption)
                }.toggleStyle(.switch).controlSize(.mini)
                Picker("", selection: $threshold) {
                    ForEach([5, 10, 15, 20], id: \.self) { Text("\($0) %").tag($0) }
                }.labelsHidden().frame(width: 72)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .onChange(of: notifsEnabled) { _, isOn in
                if isOn { onRequestNotificationPermission() }
            }
            HStack { Spacer(); Button("Konec", action: onQuit).buttonStyle(.borderless).font(.caption) }
                .padding(.horizontal, 14).padding(.vertical, 8)
        }.frame(width: 320)
```

- [ ] **Step 3: Modify `MenuBarController.swift` — přijmout a předat closure povolení.**

Najdi přesně (`old_string`):

```swift
    init(store: UsageStore, onClick: @escaping () -> Void) {
        self.store = store
        self.onRefresh = onClick
        render(store.orderedUsages)
```

a nahraď (`new_string`):

```swift
    private let onRequestNotificationPermission: () -> Void
    init(store: UsageStore, onClick: @escaping () -> Void,
         onRequestNotificationPermission: @escaping () -> Void = {}) {
        self.store = store
        self.onRefresh = onClick
        self.onRequestNotificationPermission = onRequestNotificationPermission
        render(store.orderedUsages)
```

- [ ] **Step 4: Modify `MenuBarController.swift` — předat closure do `PopoverView`.**

Najdi přesně (`old_string`):

```swift
        let hosting = NSHostingController(rootView:
            PopoverView(store: store, onRefresh: onClick, onQuit: { NSApp.terminate(nil) }))
```

a nahraď (`new_string`):

```swift
        let hosting = NSHostingController(rootView:
            PopoverView(store: store, onRefresh: onClick, onQuit: { NSApp.terminate(nil) },
                        onRequestNotificationPermission: onRequestNotificationPermission))
```

- [ ] **Step 5: Modify `AppDelegate.swift` — dodat closure povolení do `MenuBarController`.**

Najdi přesně (`old_string`):

```swift
        menuBar = MenuBarController(store: store, onClick: { [weak self] in
            Task { await self?.coordinator.refreshNow() }
        })
```

a nahraď (`new_string`):

```swift
        menuBar = MenuBarController(store: store, onClick: { [weak self] in
            Task { await self?.coordinator.refreshNow() }
        }, onRequestNotificationPermission: { [weak self] in
            self?.notifier.requestAuthorizationIfNeeded()
        })
```

- [ ] **Step 6: Modify `Resources/Info.plist` — verze 0.3.**

Najdi přesně (`old_string`):

```
  <key>CFBundleVersion</key><string>0.1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
```

a nahraď (`new_string`):

```
  <key>CFBundleVersion</key><string>0.3</string>
  <key>CFBundleShortVersionString</key><string>0.3</string>
```

- [ ] **Step 7: Build + smoke.** `swift test` → Expected: vše PASS (jádro). `swift build` čistý (app target s `@AppStorage`/`@AppStorage`). `./scripts/make-app.sh debug && open StatusBar.app` → v popoveru dole je přepínač „Upozornit při zbývajících ≤ [10 %]"; default vypnutý; zapnutí vyvolá systémový dialog o povolení notifikací (jednorázově). Lišta i zbytek beze změny.
- [ ] **Step 8: Commit.**

```bash
git add Sources/StatusBarApp/PopoverView.swift Sources/StatusBarApp/MenuBarController.swift Sources/StatusBarApp/AppDelegate.swift Resources/Info.plist
git commit -m "feat: popover přepínač upozornění + výběr prahu + verze 0.3"
```

**Verify success (Task 4):** `swift build` čistý; app se spustí; popover ukazuje přepínač upozornění (default off).
**On failure:** kterýkoli `old_string` nesedí → přečti reálný soubor a aplikuj princip. ZASTAV, neimprovizuj.

---

## Hotová definice v0.3
- Popover má přepínač „Upozornit při zbývajících ≤ N %" (default vypnuto) + výběr prahu (5/10/15/20).
- Po zapnutí + povolení OS appka zobrazí notifikaci, když u `.ok` poskytovatele klesne zbývající % okna na/pod práh — jednou za cyklus, znovu až po zotavení (rearm).
- Jádro (AlertEvaluator, PreferencesStore) plně pokryté `swift test`; vyhodnocení jen na čerstvých datech.
- Limit-část v0.1 + today-část v0.2 nezměněné; default-off = žádná změna chování při startu.

## Mimo v0.3 (další fáze)
- **v0.4:** přepínatelné styly lišty (B/C/D), plné okno Nastavení, spouštět při přihlášení (SMAppService), líný sken today; OpenAI API útrata (až bude Admin klíč).
- Drobnosti z review v0.2: `gpt-5.x` větve v `PricingTable` jsou dead code (komentář), Codex scanner negativní test.
