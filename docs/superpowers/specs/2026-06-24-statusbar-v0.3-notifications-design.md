# StatusBar v0.3 — Upozornění na spotřebu (threshold alerts)

- **Datum:** 2026-06-24
- **Stav:** Návrh (designová rozhodnutí učiněna autonomně dle delegace uživatele — uživatel si výsledek zkontroluje)
- **Navazuje na:** v0.1 (limity v liště + popover) a v0.2 (dnešní tokeny + odhady). Celkový produktový spec: `2026-06-23-statusbar-usage-monitor-design.md`.

## 1. Přehled

v0.3 přidává **volitelné macOS notifikace**, které uživatele upozorní, když u některého
poskytovatele (Claude / Codex) klesne **zbývající procento** některého okna na/pod
nastavený práh (default 10 %). Cílem je hlavní smysl monitoru: dozvědět se *včas*, že
docházejí limity, místo aby člověk narazil nečekaně.

### Cíle
- Opt-in notifikace (default **vypnuto**) — žádná změna chování ani žádost o povolení, dokud to uživatel nezapne.
- Konfigurovatelný **práh zbývajících %** (default 10; volby 5 / 10 / 15 / 20).
- **Dedup**: pro totéž okno upozornit jen jednou za cyklus; znovu „nabít" až když se okno zotaví nad práh (typicky po resetu).
- Upozorňovat jen na **čerstvá data** (`.ok`) — ne na `degraded`/`unavailable`, aby nevznikaly falešné poplachy ze zastaralých čísel.
- Vše lokálně; notifikace přes systémové `UNUserNotificationCenter`.

### Ne-cíle (mimo rozsah v0.3)
- OpenAI API útrata (stále odloženo — chybí Admin klíč).
- Přepínatelné styly lišty (B/C/D), plné okno Nastavení, spouštět při přihlášení — samostatné fáze (v0.4+).
- Zvuky/akce notifikací, doruč-do-historie, e-mail/Slack.
- Změny limit-části v0.1 a today-části v0.2 (kromě přidání `Hashable` na enumy).

## 2. Klíčová rozhodnutí (autonomní, zdokumentovaná)

1. **Default vypnuto.** Spuštění appky přes noc tedy nic nemění a nevyvolá systémový dialog o povolení. Povolení se vyžádá až při prvním zapnutí přepínače.
2. **Práh = „zbývající ≤ N %"** (remaining = 100 − vyčerpáno), per okno. Default N = 10. Konzistentní s v0.1 UI, které ukazuje zbývající %.
3. **Jen `.ok` poskytovatelé.** `degraded` (stará data) ani `unavailable` se nevyhodnocují — zastaralé číslo by mohlo dát falešný poplach i falešné ticho; raději konzervativně.
4. **Dedup klíč = (providerId, WindowKind).** Upozorní se při přechodu pod práh; klíč se „odbije" (rearm) jakmile okno znovu vystoupá nad práh. Stav držíme v paměti koordinátoru (po restartu se přehodnotí — přijatelné).
5. **Práh i zapnutí jsou perzistované** v `UserDefaults` (sdílené klíče mezi UI a koordinátorem).
6. **Jádro je čistá funkce** (`AlertEvaluator`) — plně jednotkově testovatelné bez UI a bez systémových notifikací.

## 3. Architektura

Nové čisté jednotky žijí v `StatusBarKit` a jsou samostatně testovatelné. Doručení
notifikací a UI přepínač jsou tenká vrstva v `StatusBarApp`.

| Komponenta | Vrstva | Odpovědnost | Testovatelnost |
|---|---|---|---|
| `AlertKey` | StatusBarKit | `(providerId: ProviderID, window: WindowKind)` — identita okna pro dedup. `Hashable`. | trivial |
| `AlertEvent` | StatusBarKit | Data pro jednu notifikaci: `providerDisplayName`, `windowLabel`, `remainingPercent`, `resetAt`. | trivial |
| `AlertEvaluator` | StatusBarKit | Čistá funkce: `evaluate(usages, thresholdPercent, alreadyAlerted) -> (toFire: [AlertEvent], newState: Set<AlertKey>)`. Per `.ok` okno: pokud `remaining ≤ threshold` a klíč není v `alreadyAlerted` → fire + přidat; pokud `remaining > threshold` → odebrat (rearm). | **plně unit** |
| `PreferencesStore` | StatusBarKit | `UserDefaults`-backed: `notificationsEnabled: Bool` (def. false), `remainingThresholdPercent: Int` (def. 10). Injektovatelný `UserDefaults`. | **plně unit** (suiteName) |
| `NotificationService` | StatusBarApp | Obal nad `UNUserNotificationCenter`: `requestAuthorizationIfNeeded()`, `post(_ events:)`. Stabilní identifier per `AlertKey` (re-fire nahrazuje). | build + manuál |
| Popover UI | StatusBarApp | Sekce „Upozornění": `Toggle` (zapnout, přes `@AppStorage`) + výběr prahu (5/10/15/20). Zapnutí spustí žádost o povolení. | build + manuál |
| Wiring | StatusBarApp | Po každém refreshi: je-li zapnuto, spustit `AlertEvaluator` (s perzistovaným prahem + in-memory stavem), poslat nové eventy přes `NotificationService`, aktualizovat stav. | build + manuál |

### Drobná rozšíření existujícího modelu
- `ProviderID` a `WindowKind` dostanou `Hashable` (kvůli `AlertKey` v `Set`). Aditivní, bezpečné.

## 4. Datový model a logika

```
AlertKey { providerId: ProviderID; window: WindowKind }            // Hashable
AlertEvent { providerDisplayName: String; windowLabel: String; remainingPercent: Int; resetAt: Date? }

AlertEvaluator.evaluate(
    usages: [ProviderUsage],
    thresholdPercent: Int,
    alreadyAlerted: Set<AlertKey>
) -> (toFire: [AlertEvent], newState: Set<AlertKey>)
```

Pravidla (per okno jen u poskytovatelů se `status == .ok`):
- `remaining = 100 − round(usedFraction*100)`.
- `remaining ≤ thresholdPercent` a klíč **není** v `alreadyAlerted` → přidat `AlertEvent` do `toFire`, klíč do `newState`.
- `remaining ≤ thresholdPercent` a klíč **je** v `alreadyAlerted` → neopakovat (klíč zůstává ve `newState`).
- `remaining > thresholdPercent` → klíč **není** ve `newState` (rearm pro příští přechod).
- Okna `degraded`/`unavailable` poskytovatelů se ignorují (klíče se z nich neodvozují; jejich případné staré klíče ve `newState` nepřežijí, protože se počítá jen z `.ok`).

Text notifikace: titulek `"<provider> — <windowLabel>"`, tělo `"Zbývá <remaining> %"` + (je-li `resetAt`) `" · reset za <ResetFormatter.short>"`. Využívá existující `WindowLabel` a `ResetFormatter` z v0.1.

## 5. Datový tok

1. `RefreshCoordinator.refreshNow()` doplní store (v0.1/v0.2, beze změny).
2. Je-li `notificationsEnabled`, koordinátor zavolá `AlertEvaluator.evaluate(store.orderedUsages, threshold, lastAlerted)`.
3. `lastAlerted` se přepíše na `newState`; `toFire` se předá `NotificationService.post(_:)`.
4. `NotificationService` (po jednorázové autorizaci) zobrazí notifikace; identifier per `AlertKey` → opakovaný stav nevytváří duplikáty.

Žádné nové síťové volání. Vyhodnocení je čisté a levné (běží po existujícím 60s refreshi).

## 6. UI (popover)

- Nová nenápadná sekce nad „Konec": `Toggle("Upozornit při zbývajících ≤ N %", isOn: …)` napojený na `@AppStorage(PreferenceKeys.notificationsEnabled)`.
- Vedle přepínače malý výběr prahu (Menu/Picker 5 / 10 / 15 / 20) přes `@AppStorage(PreferenceKeys.remainingThresholdPercent)`.
- Při prvním zapnutí přepínače appka zavolá `NotificationService.requestAuthorizationIfNeeded()` (systémový dialog). Když uživatel povolení odmítne, přepínač zůstane zapnutý, ale notifikace OS nezobrazí — to je mimo kontrolu appky (žádný pád).
- Lišta i ostatní popover beze změny.

## 7. Ošetření chyb a hraniční stavy
- Notifikace vypnuté → `AlertEvaluator` se vůbec nevolá; nulová režie, žádné povolení.
- Žádná `.ok` data (vše degraded/unavailable) → `toFire` prázdné, `newState` prázdné.
- Autorizace zamítnuta / neurčena → `post` tiše neudělá nic (žádný pád).
- Restart appky → `lastAlerted` prázdné; při prvním vyhodnocení se pro aktuálně-pod-prahem okna upozorní jednou (přijatelné; uživatel chce vědět, že je nízko).
- Práh mimo rozsah (manipulace UserDefaults) → vyhodnocení je čistě číselné porovnání, neprůstřelné; default 10 když chybí.

## 8. Testování
- **Unit (jádro, deterministicky):**
  - `AlertEvaluator`: (a) přechod pod práh → fire jednou; (b) setrvání pod prahem se stejným stavem → žádný re-fire; (c) zotavení nad práh → klíč odbit (rearm); (d) opětovný přechod po rearmu → fire znovu; (e) `degraded`/`unavailable` poskytovatel → žádný alert; (f) více oken/poskytovatelů nezávisle; (g) přesná hranice `remaining == threshold` → fire (≤).
  - `PreferencesStore`: defaulty (false / 10), uložení a načtení přes injektovaný `UserDefaults(suiteName:)`.
  - `Hashable` na `AlertKey` (různá okna ≠, stejné =).
- **Build/launch:** `swift build` čistý (vč. app target), `swift test` zelený, app se spustí bez pádu; s vypnutými notifikacemi žádná změna chování.
- **Manuální (mimo autonomní ověření — gap):** skutečné *doručení* notifikace vyžaduje, aby uživatel přepínač zapnul a v systému povolil notifikace. To autonomně neověřitelné; jádro rozhodování (kdy/zda pálit) je ale plně pokryté testy.

## 9. Fázování (TDD tasky)
1. `Hashable` na `ProviderID`/`WindowKind`; `AlertKey` + `AlertEvent` + `AlertEvaluator` (čisté jádro + testy).
2. `PreferencesStore` (UserDefaults, injektovatelný) + testy.
3. `NotificationService` (UNUserNotificationCenter obal) + napojení do `AppDelegate`/`RefreshCoordinator` (in-memory `lastAlerted`, je-li zapnuto).
4. Popover UI: sekce „Upozornění" (toggle + výběr prahu) + spuštění žádosti o povolení.

## 10. Rizika
- **R1 (střední):** Doručení notifikace nelze autonomně ověřit (potřeba povolení) → mitigace: jádro plně unit-testované; default-off; jasně označený verifikační gap; manuální ověření uživatelem.
- **R2 (nízké):** Falešné poplachy ze zastaralých dat → mitigace: jen `.ok` poskytovatelé.
- **R3 (nízké):** Spam při každém refreshi → mitigace: dedup per okno + rearm až po zotavení.
- **R4 (nízké):** `@AppStorage` vs. `PreferencesStore` rozjede klíče → mitigace: sdílené konstanty `PreferenceKeys` v `StatusBarKit`.
- **R5 (nízké):** Restart appky re-upozorní → přijatelné a zdokumentované.
