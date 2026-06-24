# StatusBar v0.6 — Živé Claude usage API + cost fix

- **Datum:** 2026-06-24
- **Stav:** Návrh (po úspěšném spike, rozsah odsouhlasen uživatelem)
- **Navazuje na:** v0.1–v0.5.

## 1. Přehled

v0.6 řeší zastaralá Claude data tím, že **limity bere z živého Anthropic usage API** místo
(jen) ze zastaralé lokální cache, a ukazuje **plán předplatného**. Plus **cost-display fix**:
počet „tokenů" se rozdělí na reálné (input+output) vs. cache, ať číslo dává smysl.

### Cíle (řeší body z uživatelova hlášení)
- **① čerstvá %, ⑤ aktuálnost:** limity z `GET https://api.anthropic.com/api/oauth/usage` (token z Keychainu), s **fallbackem na `.usage_cache.json`** při jakémkoli selhání.
- **③ reset 5h okna:** s čerstvými daty je `resets_at` v budoucnu → zobrazí se správně (žádná změna ve formátteru).
- **④ plán:** Claude plán z Keychain `subscriptionType` (`"max"` → „Max") — zobrazí se na kartě (ProviderCard už `planLabel` umí).
- **② cena:** výpočet beze změny (je správný), ale UI rozliší reálné (input+output) tokeny od cache (cacheWrite+cacheRead), ať „tok." nemate.

### Ne-cíle
- OpenAI/Codex živé API (Codex bere limity ze session JSONL; OpenAI odloženo — Admin klíč).
- Refresh OAuth tokenu (spoléháme, že Claude Code ho na pozadí obnovuje; my čteme aktuální).
- Změna výpočtu ceny (je správný; měníme jen zobrazení).

## 2. Spike — ověřená fakta (2026-06-24, HTTP 200)
- Endpoint: `GET https://api.anthropic.com/api/oauth/usage`, hlavičky `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `anthropic-version: 2023-06-01`.
- Odpověď: **top-level** `{five_hour, seven_day, …, limits:[…], spend}` (BEZ `data`/`timestamp` wrapperu). `limits[]` položka = `{kind, group, percent, severity, resets_at, scope, is_active}` — **stejný tvar jako cache `data.limits[]`**.
- Token: macOS Keychain, service `Claude Code-credentials`, blob JSON `{claudeAiOauth:{accessToken, refreshToken, expiresAt(ms), scopes, subscriptionType, rateLimitTier}}`. `subscriptionType="max"`. Token vyprší ~hodinově (Claude Code obnovuje).
- Claude session JSONL limity NEOBSAHUJÍ.

## 3. Architektura

| Komponenta | Vrstva | Odpovědnost | Test |
|---|---|---|---|
| `ClaudeUsageAPIParser` | Kit | Parse top-level `{limits:[…]}` → `[UsageWindow]` (sdílí mapování s cache parserem) | **unit** (fixtura API JSON) |
| `ClaudePlan.label(forSubscriptionType:)` | Kit | `"max"`→„Max", `"pro"`→„Pro", `"free"`→„Free", `"team"`→„Team", jinak kapitalizace; nil→nil | **unit** |
| `ClaudeUsageSource` (protokol) + `ClaudeLiveUsage` | Kit | `func fetchFresh() async -> ClaudeLiveUsage?` (`{windows, planLabel}`); nil = nezdařilo se | — |
| `ClaudeCodeCollector` (změna) | Kit | Nejdřív zkusí `liveSource?.fetchFresh()` → `.ok` s čerstvými windows+plán+`lastUpdated=now`; jinak **fallback na cache** (stávající logika) | **unit** (fake source) |
| `ClaudeKeychain` | App | Přečte `Claude Code-credentials` blob → `(accessToken, subscriptionType)`; chyba→nil | build/smoke |
| `LiveClaudeUsageSource` | App | Keychain→token, `GET /api/oauth/usage`, parse přes `ClaudeUsageAPIParser`+`ClaudePlan`; jakákoli chyba→nil | build/smoke |
| `AppDelegate` (změna) | App | `ClaudeCodeCollector(liveSource: LiveClaudeUsageSource())` | build/smoke |
| `TokenUsage.realTokens`/`cacheTokens` + UI | Kit/App | `realTokens=input+output`, `cacheTokens=cacheWrite+cacheRead`; popover „Dnes" ukáže reálné tok. + cache zvlášť | **unit** + build |

## 4. Datový tok (Claude limity)
1. `ClaudeCodeCollector.fetch(includeToday:)`: spočti `today` (v0.5 lazy beze změny).
2. `if let fresh = await liveSource?.fetchFresh()` → vrať `ProviderUsage(.ok, windows: fresh.windows, planLabel: fresh.planLabel, lastUpdated: now, today: today)`.
3. Jinak (live=nil) → **stávající cache cesta** (parse `.usage_cache.json`; stale→degraded; today přiložit). Beze změny chování v0.1–v0.5 při fallbacku.

`LiveClaudeUsageSource.fetchFresh()`: přečti token+subscriptionType z Keychainu → není→nil; `GET` s hlavičkami → status≠200/chyba/timeout→nil; parse JSON→windows; plán z subscriptionType; vrať `ClaudeLiveUsage`. **Token jen in-memory, NIKDY nelogovat/neukládat.**

## 5. Bezpečnost (klíčové — obrací dosavadní „žádný Keychain")
- Čteme **uživatelův vlastní** Claude OAuth token z Keychainu (`Claude Code-credentials`), jen v paměti, jen pro volání jeho vlastního usage endpointu. Nikdy se neloguje, neukládá, neposílá jinam.
- macOS jednou vyskočí s ACL dotazem „StatusBar chce přístup ke Claude Code-credentials" → uživatel povolí. Odmítnutí → `fetchFresh()` vrátí nil → fallback na cache (žádný pád).
- **Caveat (jako launch-at-login):** ad-hoc podpis se mění při každém rebuildu, takže „Always Allow" se u dev buildu může znovu ptát; u podepsané app v `/Applications` přetrvá.
- Endpoint je interní/OAuth (nedokumentovaný) → degradovat na cache gracefully; verzovat hlavičky.

## 6. Cost fix (②)
Výpočet ceny je správný (API-ekvivalent, ověřeno). Mění se jen zobrazení „Dnes":
- `TokenUsage.realTokens = input + output`, `cacheTokens = cacheWrite + cacheRead`.
- Popover: „Dnes: `<real>` tok (+`<cache>` cache) ≈ $`<cena>`"; per-model rozpad ukáže reálné tokeny.
- Cena zůstává `≈ $` (API-ekvivalent; paušál se platí tak jako tak).

## 7. Verifikace a meze
- **Plně ověřitelné:** unit testy parseru/plánu/collectoru(fake source)/realTokens; `swift build` čistý vč. app; `swift test`; app naběhne; fallback funguje (live=nil → cache, existující testy zelené).
- **GAP (ověří uživatel):** reálné Keychain povolení + skutečné fresh číslo v liště (spike prokázal, že endpoint+token fungují; runtime prompt je na uživateli). `LiveClaudeUsageSource`/`ClaudeKeychain` jsou app-level (Security/URLSession) → build+smoke.

## 8. Fázování (4 tasky)
1. `ClaudeUsageAPIParser` + `ClaudePlan.label` (pure, Kit) + testy.
2. `ClaudeUsageSource` protokol + `ClaudeCodeCollector` integrace (try live → fallback cache) + testy (fake source).
3. `ClaudeKeychain` + `LiveClaudeUsageSource` (app: Keychain+síť) + AppDelegate wiring.
4. Cost fix: `TokenUsage.realTokens/cacheTokens` + popover „Dnes" zobrazení + testy.

## 9. Rizika
- **R1 (střední):** endpoint/token nedostupné za běhu (expiry, ACL odmítnutí, offline) → mitigace: fallback na cache, nikdy pád; jasný caveat.
- **R2 (nízké):** síť každých 60s + Keychain čtení → malý GET, Keychain po povolení tiché; běží off-main (neblokuje UI).
- **R3 (nízké):** ad-hoc podpis re-prompt u dev buildu → zdokumentováno; release do `/Applications`.
- **R4 (nízké):** interní endpoint se změní → degradace na cache.
