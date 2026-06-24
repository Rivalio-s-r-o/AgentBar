# StatusBar v0.10 — Burn-rate odhad + kontrola aktualizací

- **Datum:** 2026-06-25
- **Stav:** Návrh (rozsah a rozhodnutí učiněna AUTONOMNĚ — uživatel deleguje celý cyklus přes noc; rozhodnutí níže v §7).
- **Navazuje na:** v0.1–v0.9d (0.9.1).
- **Verze:** 0.10.0. Větev `feat/v0.10-burnrate-and-updates`.
- **Motivace (uživatel):** (1) „nikde v baru nevidím burning odhad? dělali jsme to?" → máme jen **Pace** (napřed/pozadu vůči lineárnímu tempu), ale **ne** projekci/odhad „tímhle tempem dojdeš za X h / skončíš na Y %". (2) „chtěl bych přidat možnost aktualizace, abych mohl bar aktualizovat, až se bude vyvíjet."

## 1. Přehled

Dvě nezávislé featury, jeden cyklus, verze 0.10.0:

1. **Burn-rate odhad (projekce okna).** Pro každé limitní okno (Session 5h, Weekly): pokud tímhle tempem dojde limit **před resetem** → „limit ~za X" (zvýrazněno), jinak „→ ~Y % do resetu" (odhad využití k resetu). Sloučeno do existujícího Pace řádku jako druhá klauzule (žádný nový řádek navíc). Čistá logika v Kitu (`BurnRateCalculator`/`BurnProjection`/`BurnRateLabel`), testovatelná.
2. **Kontrola aktualizací (GitHub Releases).** Anonymní GET `api.github.com/repos/Rivalio-s-r-o/StatusBar/releases/latest`, porovnání `tag_name` s verzí běžící app (semver). Při novější verzi: banner v popoveru („Nová verze X →" otevře release page) + manuální „Zkontrolovat aktualizace" v Nastavení s výsledkem. Auto-check default ZAPNUTO, throttle 24 h, přepínač v Nastavení. **Notify-only — žádná auto-instalace** (app je nepodepsaná, ad-hoc; auto-download/replace = Gatekeeper riziko, YAGNI). Privátní repo dnes → 404 → graceful degradace (tiše, žádné otravování); featura „se rozsvítí", až repo bude veřejné + bude mít tag release (viz §6 RELEASING.md).

### Cíle
- Uživatel **vidí** burn odhad u oken (to, co postrádá).
- Uživatel má v app cestu, jak zjistit, že vyšla novější verze, a kam pro ni jít.
- Nulová regrese: Pace zůstává; default-on auto-check throttlovaný a vypínatelný; vše read-only vůči systému.

### Ne-cíle (YAGNI)
- Auto-download + auto-instalace nové verze (Sparkle-style). Riziko u nepodepsané app; budoucí krok.
- Znovuzavedení 30denní cenové **projekce** (×30,4) — záměrně zahozená v v0.9b (CP2 F5, matoucí). Burn-rate se týká **limitních oken**, ne 30denní ceny.
- Self-update přes lokální git checkout + rebuild (fragilní: mutace working tree, PATH ke `swift` z GUI app, relaunch).
- Login-item / jiné systémové zápisy.

## 2. Bezpečnost (dodržení stálých omezení)
- Update check = **read-only anonymní HTTPS GET** na veřejné `api.github.com`. Žádný token, žádná autentizace, žádné hlavičky s tajemstvím.
- **Žádná auto-instalace, žádné spouštění shellu/buildů, žádná mutace working tree.** Jediný zápis = `UserDefaults` (náš prefs): přepínač auto-check + timestamp posledního checku. To je naše prefs doména (jako stávající klíče) — povolené.
- Nelogovat nic citlivého (jen verze/timestamp — neutrální).
- `~/.claude`/`~/.codex` netknuté. OAuth tokeny netknuté. Repo se **NEzveřejňuje autonomně** (to je nevratné rozhodnutí uživatele).

## 3. Architektura

| Komponenta | Vrstva | Změna | Test |
|---|---|---|---|
| `BurnProjection` (nový) | Kit | `struct { projectedFractionAtReset: Double; timeToExhaustion: TimeInterval? }` | — |
| `BurnRateCalculator` (nový) | Kit | `project(window:now:) -> BurnProjection?` | **unit** |
| `BurnRateLabel` (nový) | Kit | `text(_ p: BurnProjection, bundle:) -> String` (lokalizováno) | **unit (en+cs)** |
| `PopoverView.windowsList` | App | sloučit Pace + Burn do jednoho řádku; oranžová při exhausting | build/smoke |
| `SemanticVersion` (nový) | Kit | `parse(_:) -> SemanticVersion?` (strip „v"), `Comparable` | **unit** |
| `UpdateStatus` (nový) | Kit | `enum { upToDate(SemanticVersion); updateAvailable(version:SemanticVersion, url:String); unknown }` | — |
| `UpdateChecker` (nový) | Kit | `evaluate(current:latestTag:latestURL:) -> UpdateStatus` (pure; síť injektovaná zvenčí) | **unit** |
| `PreferencesStore.autoUpdateCheck` (+`lastUpdateCheckAt`) | Kit | klíče `autoUpdateCheck` (default true), `lastUpdateCheckAt` (Double epoch) | unit |
| `AppVersion` (nový) | App | `current() -> SemanticVersion?` z `Bundle.main` CFBundleShortVersionString | — |
| `GitHubReleaseChecker` (nový) | App | `async fetchLatest() -> (tag:String, url:String)?` (URLSession GET, 404/chyba→nil) | (síť; ověřeno empiricky, ne unit) |
| `UpdateCoordinator` (nový) | App | `@MainActor ObservableObject`: drží `status`, `checkIfDue()` (throttle 24h), `checkNow()` | (smoke) |
| `PopoverView` banner | App | nahoře pod headerem: když `updateAvailable`, řádek „Nová verze X →" (NSWorkspace.open) | smoke |
| `SettingsView` | App | sekce „Aktualizace": přepínač auto-check + „Zkontrolovat nyní" + stavový text | smoke |
| `AppDelegate` | App | postavit `UpdateCoordinator`, `checkIfDue()` při startu + při popover-open | smoke |
| `Resources/Info.plist` | App | verze 0.10.0 | — |
| `RELEASING.md` (nový) | repo | jak vydat release, aby se updater rozsvítil | — |

### 3.1 Burn-rate matematika (Kit, pure)
`BurnRateCalculator.project(window: UsageWindow, now: Date) -> BurnProjection?`:
- `guard let reset = window.resetAt, reset > now else { return nil }`
- `duration = window.kind == .rolling5h ? 5*3600 : 7*24*3600`
- `start = reset - duration`; `elapsed = now - start`
- **Guard proti dělení skoro nulou:** `let elapsedFraction = elapsed / duration; guard elapsedFraction >= 0.02 else { return nil }` (5h okno: ~6 min; weekly: ~3,4 h — dřív je tempo statisticky bezcenné).
- `U = max(0, window.usedFraction)`
- `projectedFractionAtReset = U / elapsedFraction`
- **timeToExhaustion:** pokud `U >= 1.0` → `0` (limit už dosažen). Jinak pokud `projectedFractionAtReset > 1.0`: `rate = U / elapsed`; `tte = (1.0 - U) / rate`; vrať `tte` (matematicky `tte < (reset - now)`, tj. před resetem). Jinak `nil`.
- Vrať `BurnProjection(projectedFractionAtReset, timeToExhaustion)`.

**Důsledky (k ověření plan-forge empiricky na živých datech):** `projectedFractionAtReset > 1.0 ⟺ timeToExhaustion != nil`; `tte` nikdy nepřesáhne čas do resetu; `U >= 1.0 ⟹ tte == 0`.

### 3.2 Burn label (Kit, lokalizováno)
`BurnRateLabel.text(_ p: BurnProjection, bundle: Bundle? = nil) -> String`:
- `if let tte = p.timeToExhaustion`:
  - `tte <= 0` → `NSLocalizedString("burn.reached")` („limit vyčerpán" / „limit reached").
  - jinak → `String(format: NSLocalizedString("burn.exhaust"), durationString(tte))` („limit ~za %@" / „limit in ~%@").
- jinak → `String(format: NSLocalizedString("burn.projected"), Int((p.projectedFractionAtReset*100).rounded()))` („→ ~%lld %% do resetu" / „→ ~%lld%% by reset").
- `durationString(_ s: TimeInterval)`: numerický, nelokalizovaný (jako ResetFormatter, ale s dny): `d = s/86400`, `h = (s%86400)/3600`, `m = (s%3600)/60`; `d>0 → "Xd Yh"`, `h>0 → "Xh Ym"`, jinak `"Ym"`. Privátní helper v `BurnRateLabel`.

Pravidlo %/%% (z v0.9c): `burn.projected` obsahuje literální % → `%%` (jde přes `String(format:)`); `burn.exhaust` má jen `%@`; `burn.reached` přímý NSLocalizedString → bez formátu.

### 3.3 Popover integrace (sloučený řádek)
V `windowsList`, místo samostatného Pace řádku:
```
let pace = PaceCalculator.pace(window: w, now: Date()).map { PaceLabel.text(deltaPercent: $0) }
let burn = BurnRateCalculator.project(window: w, now: Date())
let exhausting = burn?.timeToExhaustion != nil
let clauses = [pace, burn.map { BurnRateLabel.text($0) }].compactMap { $0 }
if !clauses.isEmpty {
    Text(String(format: NSLocalizedString("popover.pace", ...), clauses.joined(separator: " · ")))
        .font(.caption2)
        .foregroundStyle(exhausting ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
}
```
Tj. „Tempo: napřed o 12 % · → ~85 % do resetu", nebo při exhausting „Tempo: napřed o 40 % · limit ~za 1h 20m" (oranžově). Žádný řádek navíc — jen obohacení stávajícího. Klíč `popover.pace` se recykluje (= „Tempo: %@").

### 3.4 Update check (App síť + koordinace)
`GitHubReleaseChecker` (mirror `LiveCodexUsageSource` patternu, ale triviální — bez tokenů/stavu):
```
struct GitHubReleaseChecker {
    let owner = "Rivalio-s-r-o", repo = "StatusBar"
    func fetchLatest() async -> (tag: String, url: String)? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("StatusBar-app", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        guard let pair = try? await URLSession.shared.data(for: req),
              (pair.1 as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: pair.0) as? [String: Any],
              let tag = obj["tag_name"] as? String else { return nil }
        let url = (obj["html_url"] as? String) ?? "https://github.com/\(owner)/\(repo)/releases"
        return (tag, url)
    }
}
```
`releases/latest` automaticky vynechává drafty a prereleases (chování GitHub API) → nemusíme filtrovat.

`UpdateCoordinator` (`@MainActor ObservableObject`):
- `@Published private(set) var status: UpdateStatus = .unknown`
- `checkNow() async`: `guard let cur = AppVersion.current() else { return }`; nastav „checking" stav (volitelný `isChecking` flag); `let latest = await GitHubReleaseChecker().fetchLatest()`; `status = UpdateChecker.evaluate(current: cur, latestTag: latest?.tag, latestURL: latest?.url)`; ulož `prefs.lastUpdateCheckAt = Date().timeIntervalSince1970`.
- `checkIfDue() async`: pokud `prefs.autoUpdateCheck` a (teď − lastUpdateCheckAt) ≥ 24 h → `await checkNow()`.

`UpdateChecker.evaluate` (Kit, pure):
- `latestTag == nil` → `.unknown`.
- `parse(latestTag)` selže → `.unknown`.
- `latest > current` → `.updateAvailable(latest, url)`.
- jinak → `.upToDate(current)`.

### 3.5 SemanticVersion (Kit, pure)
```
struct SemanticVersion: Comparable, Equatable {
    let major, minor, patch: Int
    static func parse(_ s: String) -> SemanticVersion?   // strip leading "v"/"V", split "."; tolerate "0.10" (patch=0); ignore "-beta" suffix on patch
}
```
Parsování: trim, strip leading `v`/`V`, vezmi část před prvním `-`/`+` (prerelease/build metadata pryč), split `.`, ber max 3 složky, chybějící = 0, každá musí být nezáporné celé číslo (jinak nil). Compare lexikograficky major→minor→patch. **POZOR na `0.10` vs `0.9`:** numericky 10 > 9 (správně), NE string compare.

## 4. Lokalizace (nové klíče, en base / cs)
Kit (`Resources/{en,cs}.lproj`):
- `burn.projected` = en „→ ~%lld%% by reset" / cs „→ ~%lld %% do resetu"
- `burn.exhaust` = en „limit in ~%@" / cs „limit ~za %@"
- `burn.reached` = en „limit reached" / cs „limit vyčerpán"

App (`Resources/{en,cs}.lproj`):
- `popover.update` = en „New version %@ →" / cs „Nová verze %@ →" (banner; %@ = verze)
- `settings.updates` = en „Updates" / cs „Aktualizace"
- `settings.autoUpdate` = en „Check for updates automatically" / cs „Kontrolovat aktualizace automaticky"
- `settings.checkNow` = en „Check now" / cs „Zkontrolovat nyní"
- `settings.update.checking` = en „Checking…" / cs „Kontroluji…"
- `settings.update.upToDate` = en „Latest version (%@)" / cs „Nejnovější verze (%@)"
- `settings.update.available` = en „New version %@ available" / cs „Nová verze %@ je k dispozici"
- `settings.update.unknown` = en „Couldn't check" / cs „Nelze ověřit"

Pravidlo %/%% a `bundle: Bundle? = nil`. Test úplnosti `kit klíče en==cs` + App varianta musí dál platit (rozšířit fixture).

## 5. Verifikace a meze
- **Auto (Kit):** `BurnRateCalculator.project` (nil guardy: reset nil/minulý, elapsedFraction<0.02, U≤0; projektovaná hodnota; tte když projected>1; tte==0 když U≥1; tte==nil když projected≤1), `BurnRateLabel` (3 větve en+cs, durationString d/h/m), `SemanticVersion.parse` (čisté „1.2.3", „v0.10.0", „0.9", nesmysl→nil, prerelease suffix) + Comparable (0.10>0.9, 1.0.0>0.9.9, rovnost), `UpdateChecker.evaluate` (nil tag→unknown, parse fail→unknown, novější→available, stejná/starší→upToDate), klíče en==cs (Kit+App). `swift build` + `swift test`.
- **R-GAP (plan-forge empiricky):** (1) burn matematika korektní na ŽIVÝCH datech (vzít reálné okno z app, ověřit projected/tte konzistenci a že tte<čas-do-resetu); (2) `SemanticVersion` Comparable empiricky (0.10 vs 0.9 atd. ve scratch testu); (3) `GitHubReleaseChecker` parse — ověřit tvar JSON reálným anonymním GET (private→404→nil; public→tag/url) — JIŽ OVĚŘENO v intake (404 private, public má tag_name/html_url); (4) Swift 6 strict-concurrency compile nového App síťového kódu + `UpdateCoordinator` `@MainActor ObservableObject`.
- **GAP (ověří uživatel ráno):** vizuál burn řádku (Session/Weekly, oranžová při exhausting), banner aktualizace se neukáže (private repo → unknown → tiše), sekce Aktualizace v Nastavení + „Zkontrolovat nyní" ukáže „Nelze ověřit" nebo „Nejnovější verze" (mechanismus běží end-to-end). Reálné „Nová verze dostupná" až po zveřejnění repa + tagu (viz RELEASING.md).

## 6. RELEASING.md (doc, repo)
Krátký návod: jak vydat verzi, aby se in-app updater rozsvítil:
1. Bump `Resources/Info.plist` (CFBundleShortVersionString + CFBundleVersion).
2. Commit + tag `vX.Y.Z`, push tagu.
3. Na GitHubu vytvořit Release z tagu (`gh release create vX.Y.Z`), volitelně přiložit zazipovanou `.app`.
4. **Aby anonymní in-app check fungoval, repo musí být veřejné** (privátní repo → anonymní `releases/latest` = 404). Dokud je privátní, updater tiše hlásí „Nelze ověřit / aktuální".

## 7. Rozhodnutí učiněná AUTONOMNĚ (uživatel spí; revize ráno)
- **D1 — dvě featury v jednom cyklu / verze 0.10.0.** Nezávislé, ale jeden rebuild k ranní verifikaci.
- **D2 — burn = projekce limitního okna, ne 30d cena.** „Burning" se v kontextu lišty/oken týká vyčerpání limitu; 30d projekce byla zahozena jako matoucí.
- **D3 — sloučit Pace+Burn do jednoho řádku.** Méně clutteru než nový řádek; obohacení stávajícího Pace.
- **D4 — update = notify-only přes GitHub Releases.** Bezpečné, standardní; auto-instalace nepodepsané app = riziko (budoucí krok). NE lokální git self-update (fragilní).
- **D5 — auto-check default ZAPNUTO, throttle 24 h, vypínatelné.** Odpovídá explicitnímu přání „mít aktuální"; respektuje kontrolu uživatele přepínačem.
- **D6 — repo se NEzveřejňuje.** Nevratné; updater degraduje, dokud to uživatel neudělá (+ RELEASING.md).

## 8. Rizika
- **R1 (střední) — burn matematika špatná/divná na hraně** (just-po-resetu, U≥1, weekly dny). **Mitigace:** elapsedFraction≥0.02 guard; tte==0 pro U≥1; plan-forge empiricky na živých datech + unit edge testy.
- **R2 (nízké) — SemanticVersion string vs numerická 0.10/0.9.** **Mitigace:** Int compare + explicitní test 0.10>0.9; plan-forge empiricky.
- **R3 (nízké) — update featura dnes „nedemonstrovatelná" (private 404).** **Mitigace:** unit testy dokazují logiku; manuální check ukáže běh end-to-end; RELEASING.md + ranní shrnutí honest o gap.
- **R4 (nízké) — auto-check phone-home bez explicitního souhlasu per-launch.** **Mitigace:** throttle 24 h, vypínatelné, anonymní, je to přesně žádaná featura.
- **R5 (nízké) — Swift 6 concurrency u `UpdateCoordinator`/síť.** **Mitigace:** mirror existujícího `LiveCodexUsageSource`/`CostHistoryStore` patternu; plan-forge compile check.
