# StatusBar v0.8b — Spolehlivá živá data (throttle/backoff/last-good) + refresh OAuth tokenu

- **Datum:** 2026-06-24
- **Stav:** Návrh (rozsah + hodnoty + dekompozice odsouhlaseny uživatelem)
- **Navazuje na:** v0.1–v0.8a.
- **Cyklus LIVE.** Obsahuje #3 (throttle/backoff/last-good — opravuje „Data stará 1283 min") i #1 (refresh tokenu + zápis zpět).

## 1. Přehled

- **#3 — zastaralá Claude data:** lišta volá živé usage API každých 60 s → endpoint vrací **HTTP 429** (rate_limit_error) → živý zdroj vrátí nil → fallback na 21h starou `.usage_cache.json` → „Data stará 1283 min". Oprava: **throttle** (síť max každých 5 min), **backoff** (po 429 pauza 15 min), **last-good cache** (drž poslední dobrý živý snapshot a vracej ho místo pádu na file cache).
- **#1 — refresh tokenu:** když živý usage call vrátí **401** (expirovaný token), obnov access_token přes refresh_token a **zapiš nový token zpět** do credential store (Keychain / `~/.codex/auth.json`), pak retry. Týká se Claude i Codexu.

### Cíle
- Claude (i Codex) ukazují čerstvá data bez „Data stará X min", endpoint se nepřetěžuje (žádné 429 z naší strany).
- Živá data fungují i když Claude Code/Codex zrovna neběží (token se obnoví).

### Ne-cíle (YAGNI)
- Zobrazovat stáří dat v UI (lastUpdated se nikde nezobrazuje — mimo rozsah).
- Proaktivní dekódování JWT exp (refresh je reaktivní na 401).
- Respektovat `retry-after` hlavičku (ověřeno `retry-after: 0` = nepoužitelné → fixní cooldown).

## 2. Diagnóza (ověřeno reálnými testy 2026-06-24)
- Claude token byl **platný** (~337 min do expirace), přesto `GET api.anthropic.com/api/oauth/usage` vrátil **429** `{type:"rate_limit_error"}`, `retry-after: 0`. → příčina = polling 60×/h, ne expirace.
- `lastUpdated` se **nikde nezobrazuje** (grep App/Formatting = 0) — jen interní staleness check v `ClaudeCodeCollector` produkuje „Data stará X min" **na cache-fallback cestě**. → s last-good cache (živý zdroj vrací snapshot, ne nil) je status `.ok`, hláška nevznikne. **Collector/payloady/protokoly se nemusí měnit, žádný `fetchedAt`.**
- Refresh endpointy ověřené (2× nezávislý grep binárek; NE live-testované — live test by spotřeboval refresh_token):
  - Claude: `POST https://platform.claude.com/v1/oauth/token`, `Content-Type: application/json`, `anthropic-beta: oauth-2025-04-20`, body `{grant_type:"refresh_token", refresh_token, client_id:"9d1c250a-e61b-44d9-88ed-5944d1962f5e"}` → `{access_token, expires_in(s), refresh_token?}`. Token v Keychainu `Claude Code-credentials`, blob `{claudeAiOauth:{accessToken, refreshToken, expiresAt(ms), …}}`.
  - Codex: `POST https://auth.openai.com/oauth/token`, `application/x-www-form-urlencoded`, body `grant_type=refresh_token&client_id=app_EMoamEEZ73f0CkXaXp7hrann&refresh_token=…` → `{access_token, token_type, expires_in, refresh_token?}`. Token v `~/.codex/auth.json` `{tokens:{access_token, refresh_token, …}, last_refresh, …}`.

## 3. Architektura

Těžiště rizikové logiky (throttle rozhodování + mutace credential blobu) je v **Kitu (pure, testovatelné)**. Síť, Keychain a souborové I/O jsou v App (build+smoke).

### 3a. Throttle/backoff policy (Kit, pure)
| Typ | Odpovědnost |
|---|---|
| `LiveUsagePolicy {minInterval: TimeInterval = 300, cooldown: TimeInterval = 900}` | konfigurace (5 min throttle, 15 min cooldown) |
| `LiveFetchSignal {success, rateLimited, failed}` | výsledek síťového pokusu |
| `LiveGateState {lastAttemptAt: Date?, cooldownUntil: Date?}` | `shouldFetch(now:policy:) -> Bool` (false v cooldownu nebo do `minInterval` od posl. pokusu); `after(signal:now:policy:) -> LiveGateState` (vždy `lastAttemptAt=now`; na `.rateLimited` `cooldownUntil=now+cooldown`, jinak `cooldownUntil=nil`) |

**Testy:** shouldFetch true iniciálně; false v rámci minInterval; false během cooldownu; after(.rateLimited) nastaví cooldown; after(.success/.failed) cooldown zruší; cooldown vyprší po čase.

### 3b. Refresh response parse + credential mutace (Kit, pure)
| Typ | Odpovědnost | Test |
|---|---|---|
| `ClaudeRefreshParse.parse(_ data: Data) -> (accessToken: String, expiresInSeconds: Double, refreshToken: String?)?` | parse Claude refresh odpovědi | unit |
| `ClaudeCredentialUpdate.updatedBlob(original: Data, accessToken: String, expiresAtMillis: Double, refreshToken: String?) -> Data?` | vrátí nový Keychain blob: změní jen `claudeAiOauth.accessToken/expiresAt/refreshToken`, **ostatní pole zachová**; nil když struktura nesedí | unit (round-trip: ověř nový token + zachovaná pole) |
| `CodexRefreshParse.parse(_ data: Data) -> (accessToken: String, refreshToken: String?)?` | parse Codex refresh odpovědi | unit |
| `CodexAuthUpdate.updatedAuthJSON(original: Data, accessToken: String, refreshToken: String?) -> Data?` | vrátí nový auth.json: změní jen `tokens.access_token` (+ `refresh_token` když dán), **vše ostatní vč. `last_refresh` zachová**; nil když struktura nesedí | unit |

Pozn.: `last_refresh` se ZÁMĚRNĚ nemění (vyhneme se riziku špatného formátu; Codex si token přečte tak jako tak — nanejvýš se obnoví o něco dřív, neškodné).

### 3c. App live sources (throttle + refresh-on-401 + write-back)
| Komponenta | Změna |
|---|---|
| `ClaudeKeychain` (změna) | `read()` rozšířit o `refreshToken` (`.ok(accessToken, refreshToken, subscriptionType)`); přidat `update(blob: Data) -> Bool` (`SecItemUpdate` `kSecValueData`, jen pokud item existuje) |
| `LiveClaudeUsageSource` (změna) | drží `gate: LiveGateState` + `lastGood: ClaudeLiveUsage?` + `policy`. `fetchFresh()`: pod zámkem zjisti `shouldFetch` + `lastGood`; když ne → vrať `lastGood`; jinak `doNetwork()`; pod zámkem `gate = gate.after(signal)` + ulož lastGood; vrať snapshot ?? lastGood. `doNetwork()`: usage call; **401 → refresh → ClaudeCredentialUpdate → Keychain.update → retry usage**; status 200→success, 429→rateLimited, jinak failed. F-PROMPT backoff (disabled) zachován. |
| `CodexAuth` (změna) | `read()` rozšířit o `refreshToken`; přidat `write(authJSON: Data) -> Bool` (atomicky: temp soubor + rename na `~/.codex/auth.json`) |
| `LiveCodexUsageSource` (změna: struct→final class) | stejný vzor: `gate` + `lastGood: CodexSnapshot?` + `policy`; `doNetwork()`: wham/usage; **401 → refresh → CodexAuthUpdate → CodexAuth.write → retry**; 200/429/jinak signal. |
| `AppDelegate` | beze změny (zdroje injektovány stejně) |

## 4. Datový tok (živý zdroj)
```
fetchFresh():
  now = Date()
  (doFetch, cached) = lock { (shouldFetch(now) && !disabled, lastGood) }
  if disabled: return nil
  if !doFetch: return cached                     // throttle/backoff → last-good (může být nil)
  let (signal, snap) = await doNetwork()
  lock { gate = gate.after(signal, now); if let s = snap { lastGood = s } }
  return snap ?? cached

doNetwork():                                     // app vrstva
  token = read credentials                       // nil → return (.failed, nil)
  resp = GET usage(token)
  if resp.status == 401:                          // expirovaný token
     refreshed = POST refresh(refreshToken)       // nil → return (.failed, nil)
     newBlob = <Kit>Update(original, refreshed)   // nil → return (.failed, nil) — NEzapisuj
     guard roundTripValid(newBlob) else return (.failed, nil)
     write(newBlob)                               // Keychain.update / CodexAuth.write
     resp = GET usage(refreshed.accessToken)
  switch resp.status { 200: parse → (.success, snap); 429: (.rateLimited, nil); else: (.failed, nil) }
```

## 5. Bezpečnost (kritické — zápis do credential store)
- **Zápis JEN při úspěšném refreshi a validním novém blobu.** Mutace blobu je čistá Kit funkce zachovávající strukturu; před zápisem **round-trip validace** (parse zpět, ověř `claudeAiOauth.accessToken == nový` resp. `tokens.access_token == nový`). Když cokoli nesedí → NEzapisovat.
- **Atomický zápis** auth.json (temp + `FileManager.replaceItem`/rename). Keychain `SecItemUpdate` (atomické).
- Tokeny (access/refresh) se NIKDY nelogují/neposílají jinam; jen in-memory + zápis do vlastního credential store.
- Refresh je **reaktivní** (jen na 401, tj. token už stejně neplatí) → zápisy jsou vzácné; když Claude Code/Codex běží, sami token drží fresh → 401 nastane zřídka → minimální riziko souběhu/rotace.
- **Graceful degradace:** refresh nebo zápis selže → `.failed` → vrať lastGood/nil → fallback na file cache. Nikdy pád, nikdy poškození (round-trip guard).
- **Caveat (důvěra):** refresh endpointy jsou ověřené z binárek, NE live-testované. Riziko: refresh nemusí projít (špatné hlavičky) → degraduje na fallback (neškodné). Zápis je jištěn round-trip validací proti korupci.

## 6. Verifikace a meze
- **Plně ověřitelné (auto):** unit testy `LiveGateState` (throttle/backoff matice), `ClaudeCredentialUpdate`/`CodexAuthUpdate` (round-trip + zachování polí + nil na špatné struktuře), `ClaudeRefreshParse`/`CodexRefreshParse`; `swift build` (Kit+App) čistý; `swift test`.
- **GAP (ověří uživatel / runtime):** že throttle reálně sníží 429 a Claude ukáže čerstvá data (po nasazení sleduj, že „Data stará X min" zmizí); reálný refresh na 401 (nastane až token vyprší a Claude Code neběží) — spike neproveden kvůli riziku, proto graceful degradace + round-trip guard.

## 7. Fázování (5 tasků)
1. **Kit throttle:** `LiveUsagePolicy` + `LiveFetchSignal` + `LiveGateState` + testy.
2. **Kit credential:** `ClaudeRefreshParse` + `ClaudeCredentialUpdate` + `CodexRefreshParse` + `CodexAuthUpdate` + testy (round-trip, zachování polí, nil-cesty).
3. **App Claude:** `ClaudeKeychain` (read +refreshToken, +update) + `LiveClaudeUsageSource` (throttle+429+refresh-on-401+write) + build/smoke.
4. **App Codex:** `CodexAuth` (read +refreshToken, +write atomicky) + `LiveCodexUsageSource` (struct→class, throttle+429+refresh+write) + build/smoke.
5. **Verze 0.8.0** + finální build/smoke.

## 8. Rizika
- **R1 (střední):** zápis poškodí credential store → Claude Code/Codex odhlášen. Mitigace: čistá Kit mutace zachovávající strukturu + round-trip validace před zápisem + atomický zápis + zápis jen při úspěchu. Nejvyšší pozornost plan-forge.
- **R2 (střední):** refresh endpoint nefunguje jak odhadnuto (hlavičky) → degradace na fallback (neškodné), ale refresh nepomůže. Mitigace: graceful, caveat.
- **R3 (nízké):** throttle 5 min stále nad rate-limitem → reziduální 429 → backoff 15 min to pohltí; data z last-good.
- **R4 (nízké):** concurrency v app live source (souběžné fetchFresh) → NSLock + claim lastAttemptAt; reálně 60s timer = sekvenční.
- **R5 (nízké):** token rotace (server vrátí nový refresh_token) — zapisujeme ho zpět (jeden zdroj pravdy); reaktivní refresh = vzácné.
