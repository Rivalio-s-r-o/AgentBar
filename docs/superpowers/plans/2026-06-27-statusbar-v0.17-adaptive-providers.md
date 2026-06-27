# Adaptivní providery + onboarding (v0.17) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Když uživatel nemá připojený jeden (nebo žádný) nástroj, AgentBar ho neukáže jako „chybu", ale jako malý ztlumený „ghost" řádek (awareness + „Připojit"), a při 0 připojených zobrazí uvítací onboarding místo prázdna.

**Architecture:** Kit-pure detekce připojení přes existenci domovské složky providera (`~/.claude`/`~/.codex`, žádný Keychain → žádný ACL prompt) + čistá funkce `isGhost(status,isConfigured)`. App vrstva (PopoverView, MenuBarController, SettingsView) z toho odvodí: ghost řádek / uvítací stav / neutrální ikonu lišty. „Připojit" recykluje existující `onOpenSettings`.

**Tech Stack:** Swift 6 (strict concurrency, 0 warnings), SwiftPM (`StatusBarKit` pure + `StatusBarApp`), Swift Testing (`@Test`/`#expect`), SwiftUI/AppKit.

## Global Constraints

- Bundle id `cz.rivalio.statusbar` ZACHOVÁN; interní targety StatusBarApp/StatusBarKit beze změny.
- `swift build` 0 warningů; `swift test` celý suite (`--filter` nematchne volné `@Test func` → vždy plný `swift test`).
- Parity en==cs: Kit `kitKlíčeEnACsShodné`, App `appKlíčeEnACsShodné` — každý nový string PŘIDAT do en i cs v TÉŽE commitu.
- Lokalizace: App view stringy přes `String(localized:"key", bundle: .module)` / `NSLocalizedString("key", bundle: .module, comment:"")`. Pravidlo %/%% (literální % → %% jen u `String(format:)`).
- Detekce připojení NESMÍ sahat na Keychain (žádný ACL prompt) — jen `FileManager`.
- Nulová regrese při 2 připojených (oba dir existují → 0 ghostů → dnešní render lišty i popoveru).
- Verze 0.17.0. Agent NIKDY nespouští GUI `.app` (jen `swift build` + `scripts/make-app.sh`).
- Provider id: `ProviderID.claudeCode` / `.codex`. Status: `ProviderStatus.ok` / `.degraded(String)` / `.unavailable(String)`.

---

### Task 1: Kit `ProviderConnectivity` (detekce + ghost logika)

**Files:**
- Create: `Sources/StatusBarKit/Providers/ProviderConnectivity.swift`
- Test: `Tests/StatusBarKitTests/ConnectivityTests.swift`

**Interfaces:**
- Consumes: `ProviderID` (`.claudeCode`/`.codex`), `ProviderStatus` (`.ok`/`.degraded`/`.unavailable`).
- Produces:
  - `ProviderConnectivity.isConfigured(_ id: ProviderID, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool`
  - `ProviderConnectivity.isGhost(status: ProviderStatus, isConfigured: Bool) -> Bool`

- [ ] **Step 1: Write the failing tests**

`Tests/StatusBarKitTests/ConnectivityTests.swift`:
```swift
import Foundation
import Testing
@testable import StatusBarKit

@Test func isConfiguredTrueKdyžSložkaExistuje() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    #expect(ProviderConnectivity.isConfigured(.claudeCode, home: tmp) == true)
    #expect(ProviderConnectivity.isConfigured(.codex, home: tmp) == false)
    try? FileManager.default.removeItem(at: tmp)
}

@Test func isConfiguredFalseKdyžChybí() {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    #expect(ProviderConnectivity.isConfigured(.claudeCode, home: tmp) == false)
    #expect(ProviderConnectivity.isConfigured(.codex, home: tmp) == false)
}

@Test func isGhostMatice() {
    #expect(ProviderConnectivity.isGhost(status: .ok, isConfigured: false) == false)
    #expect(ProviderConnectivity.isGhost(status: .degraded("x"), isConfigured: false) == false)
    #expect(ProviderConnectivity.isGhost(status: .unavailable("x"), isConfigured: true) == false)
    #expect(ProviderConnectivity.isGhost(status: .unavailable("x"), isConfigured: false) == true)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -5`
Expected: FAIL (cannot find `ProviderConnectivity` in scope).

- [ ] **Step 3: Implement `ProviderConnectivity`**

`Sources/StatusBarKit/Providers/ProviderConnectivity.swift`:
```swift
import Foundation

/// Zjišťuje, zda je provider na tomto stroji „připojený" (nakonfigurovaný). Čistě filesystem —
/// NEsahá na Keychain (žádný ACL prompt). Připojený = domovská složka providera existuje
/// (`~/.claude` resp. `~/.codex`; obě CLI je vytvoří při nastavení/přihlášení).
public enum ProviderConnectivity {
    public static func isConfigured(_ id: ProviderID,
                                    home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let dir = (id == .claudeCode) ? ".claude" : ".codex"
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: home.appendingPathComponent(dir).path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// Ghost = nepřipojený (žádná data ANI footprint). „Připojený ale dočasně nedostupný" NENÍ ghost.
    public static func isGhost(status: ProviderStatus, isConfigured: Bool) -> Bool {
        if case .unavailable = status { return !isConfigured }
        return false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: PASS, `... tests passed` (177 = 174 + 3).

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusBarKit/Providers/ProviderConnectivity.swift Tests/StatusBarKitTests/ConnectivityTests.swift
git commit -m "feat: ProviderConnectivity (isConfigured filesystem + isGhost)"
```

---

### Task 2: App `GhostRow` + `WelcomeView` + stringy

**Files:**
- Create: `Sources/StatusBarApp/GhostRow.swift`
- Create: `Sources/StatusBarApp/WelcomeView.swift`
- Modify: `Sources/StatusBarApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/StatusBarApp/Resources/cs.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `ProviderBadge(providerId:)` (existující, v0.12), `ProviderID`.
- Produces:
  - `GhostRow(providerId: ProviderID, displayName: String, onConnect: () -> Void = {})`
  - `WelcomeView()`

- [ ] **Step 1: Add strings (en) — do `Sources/StatusBarApp/Resources/en.lproj/Localizable.strings`**

```
"provider.notconnected" = "not connected";
"provider.connect" = "Connect";
"popover.welcome.title" = "Welcome to AgentBar";
"popover.welcome.body" = "Tracks Claude Code & Codex usage. Connect a tool by signing in to its CLI:";
```

- [ ] **Step 2: Add strings (cs) — do `Sources/StatusBarApp/Resources/cs.lproj/Localizable.strings`**

```
"provider.notconnected" = "nepřipojeno";
"provider.connect" = "Připojit";
"popover.welcome.title" = "Vítej v AgentBaru";
"popover.welcome.body" = "Sleduje spotřebu Claude Code a Codexu. Připoj nástroj přihlášením do jeho CLI:";
```

- [ ] **Step 3: Create `GhostRow.swift`**

```swift
import SwiftUI
import StatusBarKit

/// Malý ztlumený řádek nepřipojeného providera (awareness, že je podporovaný, + „Připojit").
struct GhostRow: View {
    let providerId: ProviderID
    let displayName: String
    var onConnect: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            ProviderBadge(providerId: providerId).opacity(0.4).grayscale(1).accessibilityHidden(true)
            Text(displayName).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text("· \(String(localized: "provider.notconnected", bundle: .module))")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
            Spacer()
            Button(String(localized: "provider.connect", bundle: .module), action: onConnect)
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(.tint)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 4: Create `WelcomeView.swift`**

```swift
import SwiftUI

/// Uvítací stav popoveru, když není připojený žádný provider (místo prázdna / dvou chyb).
struct WelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(localized: "popover.welcome.title", bundle: .module))
                .font(.system(size: 13, weight: .semibold))
            Text(String(localized: "popover.welcome.body", bundle: .module))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 4)
    }
}
```

- [ ] **Step 5: Build + parity test**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | grep -E "appKlíčeEnACsShodné|tests passed"`
Expected: Build complete (0 warnings); `appKlíčeEnACsShodné` passed; suite passes.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusBarApp/GhostRow.swift Sources/StatusBarApp/WelcomeView.swift Sources/StatusBarApp/Resources/en.lproj/Localizable.strings Sources/StatusBarApp/Resources/cs.lproj/Localizable.strings
git commit -m "feat: GhostRow + WelcomeView + onboarding strings"
```

---

### Task 3: PopoverView — ghost/welcome zapojení

**Files:**
- Modify: `Sources/StatusBarApp/PopoverView.swift:45-55` (větev `else` ve `body`)

**Interfaces:**
- Consumes: `ProviderConnectivity.isGhost`/`isConfigured` (Task 1), `GhostRow`/`WelcomeView` (Task 2), existující `onOpenSettings` (už v PopoverView).
- Produces: —

- [ ] **Step 1: Přidej ghost helper do `PopoverView` (do struct `PopoverView`, vedle `dnesCelkem`)**

```swift
    private func isGhost(_ u: ProviderUsage) -> Bool {
        ProviderConnectivity.isGhost(status: u.status,
                                     isConfigured: ProviderConnectivity.isConfigured(u.providerId))
    }
```

- [ ] **Step 2: Nahraď `else` větev (dnešní `ForEach(store.orderedUsages…)`) rozdělením na connected/ghost**

Z:
```swift
            } else {
                ForEach(store.orderedUsages, id: \.providerId) {
                    Divider()
                    ProviderCard(usage: $0,
                                 period: costHistory.history[$0.providerId],
                                 isComputingPeriod: costHistory.isComputing)
                }
            }
```
Na:
```swift
            } else {
                let connected = store.orderedUsages.filter { !isGhost($0) }
                let ghosts = store.orderedUsages.filter { isGhost($0) }
                if connected.isEmpty {
                    Divider()
                    WelcomeView()
                }
                ForEach(connected, id: \.providerId) { u in
                    Divider()
                    ProviderCard(usage: u,
                                 period: costHistory.history[u.providerId],
                                 isComputingPeriod: costHistory.isComputing)
                }
                ForEach(ghosts, id: \.providerId) { u in
                    Divider()
                    GhostRow(providerId: u.providerId, displayName: u.displayName, onConnect: onOpenSettings)
                }
            }
```

- [ ] **Step 3: Build + full test**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: Build complete (0 warnings); suite passes (177).

- [ ] **Step 4: Commit**

```bash
git add Sources/StatusBarApp/PopoverView.swift
git commit -m "feat: popover ukazuje ghost řádky + welcome stav místo chybové karty"
```

---

### Task 4: MenuBarController — ghost filtr + neutrální ikona

**Files:**
- Modify: `Sources/StatusBarApp/MenuBarController.swift:72-102` (`render`)
- Modify: `Sources/StatusBarApp/Resources/{en,cs}.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `ProviderConnectivity.isGhost`/`isConfigured` (Task 1).
- Produces: —

- [ ] **Step 1: Přidej string `menubar.tooltip.empty` (en + cs)**

en (`Sources/StatusBarApp/Resources/en.lproj/Localizable.strings`):
```
"menubar.tooltip.empty" = "AgentBar — connect Claude Code or Codex";
```
cs (`Sources/StatusBarApp/Resources/cs.lproj/Localizable.strings`):
```
"menubar.tooltip.empty" = "AgentBar — připoj Claude Code nebo Codex";
```

- [ ] **Step 2: Uprav `render` — neutrální ikona při 0 připojených + ghost filtr před barProviders**

Nahraď začátek `render(_ allUsages:)` (řádky od `let usages = allUsages.filter { prefs.barProviders.includes…` po `if prefs.barStyle == .burnBar { renderBurnBar(usages); return }`) tímto:
```swift
    private func render(_ allUsages: [ProviderUsage]) {
        // 0 připojených (vše ghost) → neutrální onboarding ikona místo dat.
        let anyConnected = allUsages.contains {
            !ProviderConnectivity.isGhost(status: $0.status,
                                          isConfigured: ProviderConnectivity.isConfigured($0.providerId))
        }
        if !anyConnected && !allUsages.isEmpty {
            let img = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "AgentBar")
            img?.isTemplate = true
            statusItem.button?.attributedTitle = NSAttributedString(string: img == nil ? "AgentBar" : "")
            statusItem.button?.image = img
            let tip = NSLocalizedString("menubar.tooltip.empty", bundle: .module, comment: "")
            statusItem.button?.toolTip = tip
            statusItem.button?.setAccessibilityLabel(tip)
            return
        }
        // Ghosty se v liště nikdy nezobrazí; pak teprve volba uživatele (Oba/Claude/Codex).
        let connected = allUsages.filter {
            !ProviderConnectivity.isGhost(status: $0.status,
                                          isConfigured: ProviderConnectivity.isConfigured($0.providerId))
        }
        let usages = connected.filter { prefs.barProviders.includes($0.providerId) }
        if prefs.barStyle == .burnBar { renderBurnBar(usages); return }
        statusItem.button?.image = nil   // jiný styl → zruš případný obrázek
```
(zbytek `render` — `segs`/title/tooltip — beze změny.)

- [ ] **Step 3: Build + parity test**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | grep -E "appKlíčeEnACsShodné|tests passed"`
Expected: Build complete (0 warnings); `appKlíčeEnACsShodné` passed.

- [ ] **Step 4: Commit**

```bash
git add Sources/StatusBarApp/MenuBarController.swift Sources/StatusBarApp/Resources/en.lproj/Localizable.strings Sources/StatusBarApp/Resources/cs.lproj/Localizable.strings
git commit -m "feat: lišta skrývá nepřipojené providery; 0 připojených → neutrální ikona"
```

---

### Task 5: SettingsView — sekce „Připojení"

**Files:**
- Modify: `Sources/StatusBarApp/SettingsView.swift`
- Modify: `Sources/StatusBarApp/Resources/{en,cs}.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `ProviderConnectivity.isConfigured` (Task 1), existující `SettingsSection`/`SettingsRow` helpery + `ProviderBadge`.
- Produces: —

- [ ] **Step 1: Přidej stringy (en + cs)**

en:
```
"settings.connections" = "Connections";
"settings.connected" = "Connected";
"settings.notconnected" = "Not connected";
"settings.connect.claude" = "Install Claude Code, sign in, then run /usage.";
"settings.connect.codex" = "Install Codex CLI and run `codex` (sign in once).";
```
cs:
```
"settings.connections" = "Připojení";
"settings.connected" = "Připojeno";
"settings.notconnected" = "Nepřipojeno";
"settings.connect.claude" = "Nainstaluj Claude Code, přihlas se a spusť /usage.";
"settings.connect.codex" = "Nainstaluj Codex CLI a spusť `codex` (jednou se přihlas).";
```

- [ ] **Step 2: Přidej helper `connectionRow` a sekci do `SettingsView` body (jako PRVNÍ sekci)**

Do `SettingsView` přidej metodu:
```swift
    @ViewBuilder private func connectionRow(_ id: ProviderID, name: String, howtoKey: String) -> some View {
        let configured = ProviderConnectivity.isConfigured(id)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                ProviderBadge(providerId: id, size: 18)
                Text(name).font(.system(size: 12.5))
                Spacer()
                Text(String(localized: configured ? "settings.connected" : "settings.notconnected", bundle: .module))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(configured ? Color.green : Color.secondary)
            }
            if !configured {
                Text(String(localized: String.LocalizationValue(howtoKey), bundle: .module))
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
```
A do `body` jako první sekci (nad existující sekce „Lišta"/„Obecné"):
```swift
            SettingsSection(String(localized: "settings.connections", bundle: .module)) {
                connectionRow(.claudeCode, name: "Claude Code", howtoKey: "settings.connect.claude")
                rowDivider
                connectionRow(.codex, name: "Codex", howtoKey: "settings.connect.codex")
            }
```
(Ověřeno: `SettingsSection(_ title: String)` = pozicový titul, caption nepovinný (call sites bez captionu kompilují); `rowDivider` je property v `SettingsView`; `ProviderBadge(providerId:size:)`. Vlož jako PRVNÍ sekci v `body` VStacku, nad `settings.preview`.)

- [ ] **Step 3: Build + parity test**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | grep -E "appKlíčeEnACsShodné|tests passed"`
Expected: Build complete (0 warnings); `appKlíčeEnACsShodné` passed.

- [ ] **Step 4: Commit**

```bash
git add Sources/StatusBarApp/SettingsView.swift Sources/StatusBarApp/Resources/en.lproj/Localizable.strings Sources/StatusBarApp/Resources/cs.lproj/Localizable.strings
git commit -m "feat: Nastavení — sekce Připojení (stav + návod jak připojit)"
```

---

### Task 6: Verze 0.17.0 + finální ověření + build app

**Files:**
- Modify: `Resources/Info.plist:16,18`

- [ ] **Step 1: Bump verze na 0.17.0**

V `Resources/Info.plist` nahraď obě `<string>0.16.0</string>` → `<string>0.17.0</string>` (`CFBundleShortVersionString` + `CFBundleVersion`).

- [ ] **Step 2: Plný test + build (0 warningů)**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: Build complete (0 warnings); 177 tests passed.

- [ ] **Step 3: Build `.app`**

Run: `./scripts/make-app.sh release 2>&1 | tail -3`
Expected: `Hotovo: AgentBar.app (podepsáno: StatusBar Dev)`; `/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" AgentBar.app/Contents/Info.plist` → `0.17.0`.

- [ ] **Step 4: Commit**

```bash
git add Resources/Info.plist
git commit -m "chore: verze 0.17.0 (adaptivní providery)"
```

---

## Self-Review

**Spec coverage:**
- Ghost indikátor (0/1 připojený) → Task 1 (logika) + Task 2 (view) + Task 3 (popover). ✅
- Uvítací stav (0 připojených) → Task 2 (WelcomeView) + Task 3 (zobrazení). ✅
- Lišta: ghost se neukáže, 0 připojených → neutrální ikona → Task 4. ✅
- Nastavení „Připojení" + návod → Task 5. ✅
- Detekce bez Keychainu → Task 1 (jen FileManager). ✅
- Nulová regrese při 2 připojených → ghost filtr je no-op když oba configured (Task 3/4); ověřeno full testem. ✅
- Verze 0.17.0 → Task 6. ✅

**Placeholder scan:** Task 5 Step 2 obsahuje poznámku „ověř API SettingsSection" — to NENÍ placeholder kódu, ale pokyn k dodržení existujícího vzoru (přesné API je v souboru); kód je kompletní pro očekávaný tvar.

**Type consistency:** `isGhost(status:isConfigured:)` / `isConfigured(_:home:)` konzistentní napříč Task 1/3/4/5. `GhostRow(providerId:displayName:onConnect:)` shodný v Task 2 a Task 3. `ProviderID.claudeCode/.codex`, `ProviderStatus.ok/.degraded/.unavailable` dle Global Constraints.
