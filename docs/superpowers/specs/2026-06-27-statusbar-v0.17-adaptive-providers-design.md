# StatusBar v0.17 — Adaptivní providery + onboarding

- **Datum:** 2026-06-27
- **Stav:** Návrh odsouhlasen uživatelem (mockup ImageRenderer ověřen, „souhlasím můžeš to tak udělat").
- **Motivace:** Uživatel: „jak to funguje, když má jen Claude nebo jen Codex? A jak se uživatel přihlásí?" Dnes app VŽDY ukazuje oba providery — chybějící se zobrazí jako trvalá `.unavailable` „chybová" karta. Pro single-provider uživatele to není přehledné. Zároveň AgentBar nemá vlastní login (čte data z Claude Code / Codex CLI) → nový uživatel netuší, jak „připojit".
- **Verze:** 0.17.0. Větev `feat/v0.17-adaptive-providers`. Baseline 174 testů.

## 1. Rozhodnutí (odsouhlasena)
**Ghost indikátor** nepřipojeného providera (ne tvrdé skrytí): malý ztlumený řádek (odbarvený badge + „nepřipojeno" + odkaz „Připojit") — uživatel ví, že nástroj je podporovaný, a jak ho připojit. Ukáže se jen když je nepřipojený **0 nebo 1** nástroj.

### Chování podle počtu připojených

| Připojeno | Lišta | Popover |
|---|---|---|
| **2** | oba reálně (dnešní chování) | obě karty (dnešní chování) |
| **1** (např. Claude) | jen Claude reálně (čistá lišta, ghost NENÍ v liště) | karta Claude + **malý ghost řádek** druhého |
| **0** | **neutrální ikona AgentBaru** (SF Symbol, tooltip „Připoj Claude/Codex") | **uvítací řádek** + 2 ghost řádky |
| **připojený, ale dočasně bez dat / chyba** | `.unavailable` jako dnes (NEskrývá se) | `.unavailable` karta jako dnes |

**Klíčové rozlišení** — „nepřipojený" (ghost) vs. „připojený, ale teď nedostupný" (unavailable karta jako dnes):
- **isConfigured** = domovská složka providera existuje (`~/.claude`, resp. `~/.codex`) — čistě filesystem, **žádný Keychain → žádný ACL prompt** (footprint na stroji ověřen: oba dir existují, Claude má i `.credentials.json`).
- **Ghost** ⇔ `status == .unavailable && !isConfigured`. Když status `.ok`/`.degraded` (máme data), je vždy „připojený" bez ohledu na FS.

**Bez uloženého stavu:** ghost je čistě funkce „existuje footprint?". Když uživatel později připojí druhý nástroj (přihlásí se do CLI), při dalším refreshi se sám objeví jako plná karta — žádné „dismissed" flagy.

### Onboarding (řeší „jak se přihlásit")
- **Odkaz „Připojit"** v ghost řádku i ve welcome stavu → otevře **Nastavení → nová sekce „Připojení"**.
- **Sekce „Připojení" v Nastavení:** per-provider stav (Připojeno / Nepřipojeno) + u nepřipojeného krátký návod („Nainstaluj a přihlas se do Claude Code / Codex CLI"). Toto je místo, kde se skrytý/nepřipojený provider „znovuobjeví".
- AgentBar nemá vlastní login — jen navedení na oficiální CLI (čte jejich data, nikdy se neptá na heslo, neloguje tokeny).

### Ne-cíle (YAGNI)
- Vlastní OAuth login. README/dokumentace (= proud C; tady jen in-app texty). Změna `BarProviders` (Oba/Claude/Codex) sémantiky — zůstává; ghost-filtr se aplikuje PŘED ním (nepřipojený nikdy v liště). Persistentní „dismissed" stav. Změna chování při 2 připojených (nulová regrese).

## 2. Architektura (dotčené soubory)

| Soubor | Změna | Test |
|---|---|---|
| `Sources/StatusBarKit/Providers/ProviderConnectivity.swift` (nový) | `isConfigured(_ id: ProviderID, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool` (dir `~/.claude`/`~/.codex` existuje) + `isGhost(status: ProviderStatus, isConfigured: Bool) -> Bool` (`.unavailable && !isConfigured`) | nový ConnectivityTests (inject temp home) |
| `Sources/StatusBarApp/PopoverView.swift` | rozdělí `orderedUsages` na connected (ProviderCard) a ghost (nový `GhostRow`); 0 connected → `WelcomeView`; ghost řádky pod kartami | build/smoke |
| `Sources/StatusBarApp/GhostRow.swift` (nový) | malý ztlumený řádek: badge `.opacity(0.4).grayscale(1)` + název + „· nepřipojeno" + „Připojit" (→ onConnect) | build/smoke |
| `Sources/StatusBarApp/WelcomeView.swift` (nový) | „Vítej v AgentBaru" + popis + (ghost řádky renderuje PopoverView) | build/smoke |
| `Sources/StatusBarApp/MenuBarController.swift` | `render`: nejdřív vyřaď ghosty (`!isGhost`), pak existující `barProviders` filtr; 0 connected → neutrální ikona (SF Symbol `gauge.with.dots.needle.bottom.50percent` template, tooltip) místo `menubar.fallback` textu | build/smoke |
| `Sources/StatusBarApp/SettingsView.swift` | nová sekce „Připojení": per-provider stav + návod; `onConnect`/connectivity injektováno | build/smoke |
| `Sources/StatusBarApp/AppDelegate.swift` + `SettingsWindowController` | protáhnout otevření sekce „Připojení" (popover „Připojit" → `settings.show()` + scroll/focus); connectivity je Kit volání (bez stavu) | build/smoke |
| `Sources/StatusBarKit/Resources/{en,cs}.lproj/Localizable.strings` | `provider.notconnected`, `provider.connect`, `popover.welcome.title`, `popover.welcome.body`, `settings.connections`, `settings.connect.claude`, `settings.connect.codex`, `menubar.tooltip.empty` | parity |
| `Resources/Info.plist` | verze 0.17.0 | — |

### 2.1 Connectivity (Kit, pure)
```swift
public enum ProviderConnectivity {
    public static func isConfigured(_ id: ProviderID,
        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let dir: String = (id == .claudeCode) ? ".claude" : ".codex"
        var isDir: ObjCBool = false
        let p = home.appendingPathComponent(dir).path
        return FileManager.default.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue
    }
    /// Ghost = nepřipojený (žádná data ANI footprint). Připojený-ale-nedostupný NENÍ ghost.
    public static func isGhost(status: ProviderStatus, isConfigured: Bool) -> Bool {
        if case .unavailable = status { return !isConfigured }
        return false
    }
}
```

### 2.2 Popover (rozhodovací logika)
- Pro každý `usage`: `ghost = ProviderConnectivity.isGhost(status: usage.status, isConfigured: isConfigured(usage.providerId))`.
- `connected = usages.filter { !ghost }`, `ghosts = usages.filter { ghost }`.
- `if connected.isEmpty { WelcomeView() }` (uvítací text).
- `ForEach(connected) { ProviderCard($0) }` (beze změny; `.unavailable`-but-configured se renderuje jako dnes).
- `ForEach(ghosts) { GhostRow(...) }`.

### 2.3 Menu bar
- `render(allUsages)`: `let connected = allUsages.filter { !ProviderConnectivity.isGhost(status:$0.status, isConfigured: isConfigured($0.providerId)) }` → pak existující `prefs.barProviders.includes` filtr.
- `connected.isEmpty` → `statusItem.button?.image = NSImage(systemSymbolName:…)` (template) + `attributedTitle = ""` + tooltip `menubar.tooltip.empty`. Jinak dnešní render (text/burnBar) nad `connected`.

### 2.4 Onboarding text (in-app, en base / cs)
- welcome.title: „Welcome to AgentBar" / „Vítej v AgentBaru".
- welcome.body: „Tracks Claude Code & Codex usage. Connect a tool by signing in to its CLI:" / „Sleduje spotřebu Claude Code a Codexu. Připoj nástroj přihlášením do jeho CLI:".
- settings.connect.claude: „Install Claude Code, sign in, then run /usage." / „Nainstaluj Claude Code, přihlas se a spusť /usage.".
- settings.connect.codex: „Install Codex CLI and run `codex` (sign in once)." / „Nainstaluj Codex CLI a spusť `codex` (jednou se přihlas).".

## 3. Verifikace a meze
- **Auto (TDD):** `ConnectivityTests` — isConfigured true/false dle injektnutého home (temp dir s/bez `.claude`/`.codex`); isGhost matice (`.ok`→false, `.degraded`→false, `.unavailable`+configured→false, `.unavailable`+!configured→true). `swift build` 0 warningů, `swift test` (174 + nové). Parity en==cs (Kit+App).
- **Empiricky (plan-forge):** (1) isConfigured je čistě `FileManager.fileExists` → NEsahá na Keychain → žádný ACL prompt (ověřit, že žádná cesta nevolá Security framework). (2) Nulová regrese při 2 připojených (oba dir existují → 0 ghostů → dnešní render).
- **Vizuál (ImageRenderer PNG předem):** ghost řádek + welcome stav (už ověřen mockupem, uživatel „souhlasím"); finální ověření na reálných komponentách.
- **GAP (uživatel):** dočasně přejmenovat `~/.codex` → ghost Codexu v popoveru + čistá lišta jen s Claude + sekce „Připojení" v Nastavení; vrátit zpět → Codex se objeví. (0 připojených nelze snadno bez odpojení obou — ověří se vizuálně z mockupu.)

## 4. Rizika
- **R1 (nízké) — falešný ghost u připojeného providera:** mitigace — `status==.ok` NIKDY není ghost (jen `.unavailable`); navíc isConfigured kontroluje dir, který připojený nástroj vždy má. plan-forge ověří matici.
- **R2 (nízké) — leftover prázdná složka po odinstalaci → falešně „připojený":** ukáže se `.unavailable` karta (dnešní chování), ne pád; přijatelné. Volitelně zpřísnit na „dir neprázdný".
- **R3 (nízké) — Keychain prompt z detekce:** vyloučeno — žádný přístup ke Keychainu (jen FileManager). plan-forge potvrdí.
- **R4 (nízké) — neutrální ikona lišty:** SF Symbol jako template `NSImage`; ověřit, že se vykreslí a tooltip sedí (build/smoke). Fallback: text „AgentBar".
- **R5 (nízké) — `BarProviders` × ghost:** když uživatel ručně zvolí „jen Codex" a Codex je ghost → lišta prázdná → neutrální ikona. Edge, přijatelné (uživatel si zvolil nepřipojeného).
