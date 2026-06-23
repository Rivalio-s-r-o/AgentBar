# StatusBar v0.2 — Dnešní tokeny & odhady cen (Claude + Codex)

- **Datum:** 2026-06-23
- **Stav:** Návrh odsouhlasen, připraveno k tvorbě implementačního plánu
- **Navazuje na:** v0.1 (limity v liště + popover panel A). Celkový produktový spec: `2026-06-23-statusbar-usage-monitor-design.md`.

## 1. Přehled

v0.2 přidává do rozkliknutého panelu **dnešní spotřebu tokenů a odhad ceny** pro
Claude Code a Codex, plus souhrn **„Dnes celkem ≈ $X"** v hlavičce. Vychází
z mockupu panelu A z v0.1, který tyto řádky sliboval (ve v0.1 byly vědomě
odložené). **Lišta se nemění** (zůstává zbývající %). **OpenAI API útrata je
odložená** (vyžaduje Admin klíč, který teď není k dispozici) — dodá se později.

### Cíle
- U každé karty (Claude, Codex) řádek **„Dnes"**: počet tokenů + odhad ceny.
- U Claude karty navíc **rozpad podle modelu** (Opus / Sonnet / …).
- V hlavičce popoveru **„Dnes celkem ≈ $X"** (součet odhadů Claude + Codex).
- Vše lokálně, žádný cloud.

### Ne-cíle (mimo rozsah v0.2)
- OpenAI API útrata (odložena — samostatná fáze, až bude Admin klíč).
- Změny v liště.
- Notifikace, přepínatelné styly, Nastavení (to je v0.3).
- Historie / grafy útraty (jen „dnes" + případně „tento týden" později).

## 2. Klíčová rozhodnutí (odsouhlaseno)

- **„Dnes" = kalendářní den v lokální časové zóně** (reset o půlnoci lokálně).
- U předplatného je cena **odhad v API cenách** (`≈ $`) — reálně se platí paušál;
  v UI vizuálně/textově odlišené od reálné útraty (jako ve v0.1 legendě).
- **Souhrn „Dnes celkem"** počítá jen z Claude + Codex (bez OpenAI).
- **Rozpad modelů** se zobrazuje na Claude kartě.

## 3. Architektura

Nové jednotky jsou čisté a samostatně testovatelné, žijí v `StatusBarKit`.
Limit-část z v0.1 (parsery, collectory, store, lišta) zůstává **nedotčená**;
v0.2 jen rozšiřuje model a doplňuje data v `fetch()`.

| Komponenta | Odpovědnost | Závisí na |
|---|---|---|
| `TokenUsage` (model) | Rozpad tokenů: `input`, `output`, `cacheWrite`, `cacheRead` (UInt). Sčitatelný (`+`). | — |
| `ModelTokens` (model) | `modelName: String` + `TokenUsage` (pro per-model rozpad). | `TokenUsage` |
| `TodayUsage` (model) | `perModel: [ModelTokens]`, `total: TokenUsage` (computed), `estimatedCost: Decimal`. | `TokenUsage` |
| `ClaudeTokenScanner` | Sečte dnešní tokeny z `~/.claude/projects/**/*.jsonl` (řádky `type=="assistant"` s dnešním `timestamp`), seskupí podle `message.model`. Čte **jen soubory s dnešním mtime** (výkon). | Claude JSONL |
| `CodexTokenScanner` | Sečte dnešní tokeny ze `~/.codex/sessions` — z dnešních sessionů vezme finální `info.total_token_usage`. Codex nerozlišuje model v `info`, takže jeden „model" (název z `turn_context`/`session_meta`, jinak „codex"). | Codex sessions |
| `PricingTable` | Datovaná tabulka cen modelů ($/1M tokenů: `input`, `output`, `cacheWrite`, `cacheRead`), s datem platnosti. | — |
| `PricingEstimator` | Čistá funkce `estimate(TokenUsage, model) -> Decimal` (cache-aware). Neznámý model → 0 + příznak (degraduje). | `PricingTable` |

### Rozšíření existujícího modelu
`ProviderUsage` dostane volitelné `today: TodayUsage?` (nil = nemáme/nepočítáme).
Limit-pole zůstávají. `ClaudeCodeCollector`/`CodexCollector.fetch()` po načtení
limitů zavolají příslušný scanner + estimator a vyplní `today`. Selhání scanneru
nesmí shodit limit-část — `today` prostě zůstane `nil`.

## 4. Datový model — detail

```
TokenUsage { input, output, cacheWrite, cacheRead: UInt }   // + operátor sčítání
  var totalTokens: UInt { input + output + cacheWrite + cacheRead }

ModelTokens { modelName: String; tokens: TokenUsage }

TodayUsage {
  perModel: [ModelTokens]            // u Codexu typicky 1 prvek
  estimatedCost: Decimal
  var total: TokenUsage              // součet perModel
}

ProviderUsage { … (v0.1 beze změny) …; today: TodayUsage? }
```

## 5. Datový tok

1. Collector načte limity (v0.1, beze změny).
2. Scanner sečte dnešní tokeny per model (jen dnešní soubory/sessiony).
3. `PricingEstimator` spočte `estimatedCost` (součet přes modely, cache-aware).
4. Collector vrátí `ProviderUsage` s vyplněným `today`.
5. Popover hlavička sečte `today.estimatedCost` přes poskytovatele → „Dnes celkem".

Vše lokálně, jen čtení. Žádné nové síťové volání.

## 6. Pricing & přesnost

- `PricingTable` drží sazby per model (input / output / cache-write / cache-read
  za 1M tokenů). Cache-write je u Anthropic dráž než input, cache-read výrazně
  levnější — estimator to musí rozlišit.
- **Ceny ověřit při psaní plánu (spike):** od znalostního cutoffu se mohly změnit;
  plán bude obsahovat konkrétní ověřené sazby s datem.
- Neznámý model (chybí v tabulce) → cena 0 pro daný model, ostatní se počítají;
  v UI to nemá tvrdě selhat (degradace), volitelně drobný náznak „(odhad neúplný)".
- `≈` jasně komunikovat jako odhad; u Codexu i Claude jde o ekvivalent API cen.

## 7. Výkon

- **Claude:** `~/.claude/projects` má desítky projektů a může obsahovat GB historie.
  Scanner čte **jen soubory s `contentModificationDate` v dnešním kalendářním dni**
  (dnešní session musela být dnes zapisována), a v nich filtruje řádky podle
  `timestamp`. Tím se sken omezí na hrstku souborů.
- **Codex:** podobně — jen sessiony s dnešním mtime; z každé poslední
  `token_count.info.total_token_usage`.
- Žádné celé-stromové čtení každých 60 s; pre-filtr řádků jako u v0.1 Codex parseru.

## 8. UI (popover, panel A)

- **Karta Claude:** pod okny řádek **„Dnes: <tok> ≈ $<odhad>"** + pod ním drobný
  **rozpad modelů** (`Opus <tok> · Sonnet <tok>`).
- **Karta Codex:** řádek **„Dnes: <tok> ≈ $<odhad>"** (bez rozpadu modelů).
- **Hlavička:** vpravo **„Dnes celkem ≈ $<součet>"**.
- Formátování tokenů: kompaktně (např. `1.24M`, `820K`). Pokud `today == nil`
  (scan selhal), řádek „Dnes" se prostě nezobrazí (karta jinak funguje).
- Lišta beze změny.

## 9. Ošetření chyb a hraniční stavy
- Scanner selže / žádná dnešní data → `today = nil`; karta ukáže jen limity.
- Neznámý model v cenách → částečný odhad, bez pádu.
- Prázdný den (0 tokenů) → „Dnes: 0 tok. ≈ $0.00" (nebo skrýt — rozhodne plán; default: zobrazit 0).
- Žádné modály, žádné pády.

## 10. Testování
- **Unit (jádro):** `ClaudeTokenScanner` (fixtura JSONL: dnešní vs včerejší řádky,
  2 modely → správné sumy a rozpad), `CodexTokenScanner` (dnešní vs starší session,
  kumulativní `total_token_usage`), `PricingEstimator` (cache-aware výpočet na
  známém modelu; neznámý model → 0), `TokenUsage` sčítání, agregace „Dnes celkem".
- Testy proti **fixturám s řízeným mtime/timestampem** (deterministické, bez
  závislosti na reálných datech).
- **Manuální/smoke:** popover ukazuje řádky „Dnes" + rozpad + hlavičkový souhrn.

## 11. Fázování v rámci v0.2
1. Model (`TokenUsage`/`ModelTokens`/`TodayUsage`) + `PricingTable`/`PricingEstimator`.
2. `ClaudeTokenScanner` + napojení do `ClaudeCodeCollector`.
3. `CodexTokenScanner` + napojení do `CodexCollector`.
4. UI: řádky „Dnes" + rozpad modelů + hlavičkový souhrn „Dnes celkem".

## 12. Rizika
- **R1 (střední):** Aktuální ceny modelů — ověřit ve spike; tabulku verzovat a
  jasně značit `≈` jako odhad.
- **R2 (nízké):** Výkon skenu Claude JSONL — mitigace: jen dnešní-mtime soubory.
- **R3 (nízké):** Codex `info` nemusí být v každé session (starší/jiná verze) —
  scanner to toleruje (chybí → 0 pro tu session).
- **R4 (nízké):** Mapování názvu Claude modelu (`claude-opus-4-8`) na čitelný
  „Opus" pro rozpad i na řádek v `PricingTable` — vyřešit normalizací názvu.
