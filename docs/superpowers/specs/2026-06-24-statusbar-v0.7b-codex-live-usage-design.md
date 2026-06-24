# StatusBar v0.7b — Živé Codex/OpenAI limity

- **Datum:** 2026-06-24
- **Stav:** Návrh (po úspěšném spike, rozsah odsouhlasen uživatelem)
- **Navazuje na:** v0.1–v0.7a.
- **Cyklus 2 ze 2 ve v0.7** (cyklus 1 = v0.7a styly lišty, hotový).

## 1. Přehled

Codex dnes bere limity ze session JSONL (`~/.codex/sessions/**`), které jsou čerstvé
jen když uživatel spustí `codex` — bývají dny až týdny staré (degraded). v0.7b bere
limity z **živého ChatGPT/Codex usage endpointu** (analogie Claude v0.6), s **fallbackem
na stávající JSONL** při jakémkoli selhání. Default chování (bez živého zdroje) beze změny.

### Cíle
- **Čerstvá %, správné resety:** Codex limity z `GET https://chatgpt.com/backend-api/wham/usage`.
- **Plán:** z `plan_type` v odpovědi (`"plus"` → „Plus"); žádné dekódování JWT.
- **Fallback:** jakékoli selhání (chybějící/expirovaný token, 4xx/5xx, offline, prázdná data) → stávající JSONL cesta (žádný pád, žádná regrese).

### Ne-cíle (YAGNI)
- Refresh OAuth tokenu (Codex ho obnovuje v `auth.json` na pozadí; my čteme aktuální).
- Zobrazení `credits`/`spend_control`/`code_review_rate_limit` (uživatel je Plus bez kreditů).
- Separátní OpenAI API-key větev — uživatel jede přes ChatGPT OAuth (`OPENAI_API_KEY: None`).
- Změna UI popoveru/lišty (Codex karta už `windows`+`planLabel` umí).

## 2. Spike — ověřená fakta (2026-06-24, HTTP 200)

- Endpoint: **`GET https://chatgpt.com/backend-api/wham/usage`** (pozn.: alias `/api/codex/usage` vrací 403 přes WAF → použít `wham/usage`). Hlavičky: `Authorization: Bearer <access_token>`, `chatgpt-account-id: <account_id>`, `User-Agent: codex_cli_rs/<ver>`, `Accept: application/json`.
- Auth: soubor `~/.codex/auth.json` (mód `chatgpt`), `tokens.access_token` (JWT, Bearer), `tokens.account_id` (UUID, hlavička `chatgpt-account-id`). `OPENAI_API_KEY: null` (ChatGPT OAuth, ne API klíč).
- Odpověď (ověřený tvar, redahováno):
```json
{
  "plan_type": "plus",
  "rate_limit": {
    "allowed": true,
    "limit_reached": false,
    "primary_window":   { "used_percent": 1,  "limit_window_seconds": 18000,  "reset_after_seconds": 18000,  "reset_at": 1782312918 },
    "secondary_window": { "used_percent": 12, "limit_window_seconds": 604800, "reset_after_seconds": 147918, "reset_at": 1782442836 }
  },
  "code_review_rate_limit": null,
  "additional_rate_limits": null,
  "credits": { "has_credits": false, "...": "..." }
}
```
- `primary_window` (`limit_window_seconds` 18000 = 5 h) → `.rolling5h`; `secondary_window` (604800 = 7 dní) → `.weekly(nil)`. `reset_at` = absolutní Unix epoch (Int). Token vyprší ~hodinově.

## 3. Architektura

Mirror v0.6. Těžiště v Kitu (pure, testovatelné); app vrstva jen čte soubor + síť.

| Komponenta | Vrstva | Odpovědnost | Test |
|---|---|---|---|
| `CodexUsageAPIParser` | Kit | Parse top-level `{plan_type, rate_limit:{primary_window, secondary_window}}` → `CodexSnapshot` (znovupoužívá existující `CodexSnapshot {windows, planType}`) | **unit** (fixtura) |
| `CodexPlan.label(forPlanType:)` | Kit | `"plus"`→„Plus", `"pro"`→„Pro", `"free"`→„Free", `"team"`→„Team", `"enterprise"`→„Enterprise"; prázdný/nil→nil; jinak kapitalizace | **unit** |
| `CodexUsageSource` (protokol) | Kit | `func fetchFresh() async -> CodexSnapshot?` (nil = nezdařilo se) | — |
| `CodexCollector` (změna) | Kit | Nejdřív `liveSource?.fetchFresh()` → `.ok` s čerstvými windows+plán+`lastUpdated=now`+today; jinak **fallback na JSONL** (stávající logika beze změny). `CodexPlan.label` aplikován na obou cestách (živé i JSONL) | **unit** (fake source) |
| `CodexAuth` | App | Přečte `~/.codex/auth.json` → `(accessToken, accountId)`; chyba→nil. Token JEN in-memory | build/smoke |
| `LiveCodexUsageSource` | App | auth→token+účet, `GET wham/usage` s hlavičkami, parse přes `CodexUsageAPIParser`; jakákoli chyba/≠200→nil | build/smoke |
| `AppDelegate` (změna) | App | `CodexCollector(liveSource: LiveCodexUsageSource())` | build/smoke |

### Mapování parseru
`CodexUsageAPIParser.parse(_ data: Data) -> CodexSnapshot?`:
- Dekóduj `{plan_type: String?, rate_limit: {primary_window: Window?, secondary_window: Window?}}`, `Window {used_percent: Double?, limit_window_seconds: Double?, reset_at: Double?}`.
- Pro každé okno (primary→nejdřív, secondary→pak): kind = `limit_window_seconds < 86400 ? .rolling5h : .weekly(scope: nil)`; `usedFraction = used_percent/100`; `resetAt = reset_at.map { Date(timeIntervalSince1970: $0) }`.
- `planType` = `plan_type` (raw; `CodexPlan.label` se aplikuje v collectoru).
- Když `rate_limit` chybí nebo obě okna nil/bez `used_percent` → vrať nil (žádná čerstvá data → fallback).

## 4. Datový tok (Codex limity)
1. `CodexCollector.fetch(includeToday:)`: spočti `today` (lazy, beze změny) — pozn.: today se počítá jen při `includeToday`.
2. `if let snap = await liveSource?.fetchFresh()` → vrať `ProviderUsage(.ok, displayName: "Codex", planLabel: CodexPlan.label(forPlanType: snap.planType), windows: snap.windows, lastUpdated: now, today: today)`.
3. Jinak (live=nil) → **stávající JSONL cesta** (beze změny chování v0.1–v0.7a; jen `planLabel` projde přes `CodexPlan.label` pro konzistentní „Plus" místo „plus").

`LiveCodexUsageSource.fetchFresh()`: `CodexAuth.read()` → není→nil; `GET wham/usage` s hlavičkami, `timeoutInterval` ~10 s → status≠200/chyba/timeout→nil; parse přes `CodexUsageAPIParser` → `windows.isEmpty`→nil; vrať `CodexSnapshot`. **Token jen in-memory, NIKDY nelogovat/neukládat/neposílat jinam.**

## 5. Bezpečnost
- Čteme **uživatelův vlastní** ChatGPT OAuth token ze souboru `~/.codex/auth.json` (read-only), jen v paměti, jen pro volání jeho vlastního usage endpointu. Token ani `account_id` se NIKDY nelogují, neukládají, neposílají jinam.
- **Žádný Keychain → žádný ACL prompt** (jednodušší než Claude v0.6; není potřeba F-PROMPT backoff).
- `auth.json` má práva `-rw-------` (jen uživatel) — čteme v kontextu uživatele.
- Endpoint je interní/nedokumentovaný → degradovat na JSONL gracefully; verzovat `User-Agent`.
- Při 401/expired → nil → fallback. Token Codex obnovuje sám při běhu; my ho refresh NEřešíme.

## 6. Verifikace a meze
- **Plně ověřitelné (automaticky):** unit testy parseru (fixtura wham/usage shape, edge: chybějící secondary, chybějící rate_limit), `CodexPlan.label`, `CodexCollector` s fake source (try-live→fallback); `swift build` (Kit+App) čistý; `swift test`; fallback (live=nil → JSONL, existující Codex testy zelené).
- **GAP (ověří uživatel):** reálný runtime request s živým tokenem + fresh číslo Codexu v liště. Spike prokázal endpoint+token (HTTP 200); `LiveCodexUsageSource`/`CodexAuth` jsou app-level (soubor+URLSession) → build+smoke.

## 7. Fázování (3 tasky)
1. `CodexUsageAPIParser` + `CodexPlan.label` (pure, Kit) + testy (fixtura).
2. `CodexUsageSource` protokol + `CodexCollector` integrace (try-live→fallback) + `CodexPlan.label` na obou cestách + testy (fake source).
3. `CodexAuth` + `LiveCodexUsageSource` (app: soubor+síť) + `AppDelegate` wiring + verze bundlu 0.7.1.

## 8. Rizika
- **R1 (střední):** endpoint/token nedostupné za běhu (expiry, offline, WAF) → mitigace: fallback na JSONL, nikdy pád; jasný caveat.
- **R2 (nízké):** WAF blokne i `wham/usage` jako u `api/codex/usage` → mitigace: na ≠200 fallback; `User-Agent` jako codex.
- **R3 (nízké):** `auth.json` schéma se změní (jiné pole tokenu) → `CodexAuth` vrátí nil → fallback.
- **R4 (nízké):** retrofit `CodexPlan.label` v collectoru (obě cesty) změní zobrazení „plus"→„Plus" — záměr (konzistence), ne regrese. Dopad na testy (ověřeno): `CodexRateLimitParserTests` testuje `snap.planType == "plus"` na PARSERU (ten zůstává raw, neměněn → zelený); `CodexCollectorTests:22` testuje `u.planLabel == "plus"` na COLLECTORU → **aktualizovat na `== "Plus"`** (záměrná změna, ne regrese). `CodexPlan.label` se aplikuje JEN v collectoru při stavbě `ProviderUsage`, ne v parserech.
