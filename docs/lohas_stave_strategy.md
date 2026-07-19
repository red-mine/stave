# 乐活五线谱 (LOHAS Stave) Strategy

This app implements a technical-analysis method created by Prof. 薛兆亨 (Taiwan),
adapted from Dr. 曾渊沧's "曾氏通道" (Hong Kong). It is **not** a musical staff —
"Stave" here is the literal English translation of 五线谱 (wǔxiànpǔ), the term for
a musical staff, borrowed for its "five lines" visual.

## Core assumptions

1. **Mean reversion** — price deviating from its long-run average tends to correct back.
2. **Normal distribution** — price is assumed to be normally distributed around the trend.

A linear-regression trend line is fit over a window (typically **3.5 years**, half an
economic cycle), then four more lines are drawn at ±1 and ±2 standard deviations from
that trend line, for five lines total.

## The five lines

| Line | Name | Meaning |
|---|---|---|
| Top | 乐观线 (+2SD) | Extremely optimistic zone — ~2.5% chance price is this high |
| Upper-mid | 相对乐观线 (+1SD) | Relatively optimistic zone — ~16% chance price is this high |
| Middle | 趋势线/价值线 (TL) | Long-run average trend price |
| Lower-mid | 相对悲观线 (-1SD) | Relatively pessimistic zone — ~16% chance price is this low |
| Bottom | 悲观线 (-2SD) | Extremely pessimistic zone — ~2.5% chance price is this low |

~95% of observations fall within these five lines.

## Why "乐活" (LOHAS)?

乐活 = "Lifestyles of Health and Sustainability" — the strategy is meant for
long-term, low-maintenance investing (no daily monitoring needed), hence the
"relaxed/healthy lifestyle" branding.

## Strategy rules

- Price breaks below the (relatively) pessimistic line → consider **buying**.
- Price breaks above the (relatively) optimistic line → consider **selling**.
- **Slope of the trend line matters**: positive slope (uptrend) → higher win rate for
  "buy low, sell high"; negative slope (downtrend) → lower win rate, can lose money —
  the strategy is meant to be applied only to confirmed uptrends.
- The four bands between the five lines can be treated as grid-trading zones.
- Pair with the **乐活通道 (LOHAS Channel)** — built from past-high average, 20-week MA,
  past-low average — to avoid over-trading in extreme zones during black-swan/fat-tail moves.
- Precondition: only apply to fundamentally sound companies; if fundamentals deteriorate,
  the mean-reversion assumption can break down.

## Mapping to this codebase

| Strategy concept | Code |
|---|---|
| 3.5-year window | `LOHAS = 3 * YEARS + YEARS / 2` ([lib/stock.rb](../lib/stock.rb)) |
| 20-week MA (LOHAS Channel) | `STAVE = 20 * WEEKS` ([lib/stock.rb](../lib/stock.rb)) |
| Trend line (TL/价值线) | `Stock::Stock#good_trend` ([lib/stock/stock.rb](../lib/stock/stock.rb)) |
| ±1SD / ±2SD lines | `Stock::Stock#good_stave(stock, up/down, 1 or 2)` |
| LOHAS Channel (MA + bands) | `Stock::Stock#good_aver` / `#good_boll` |
| Combined stave+channel signal | `Stock::Stock#_good_price` (private) |
| Per-stock five-line series | `StocksStaveLoha` / `StocksStaveYear` tables |
| Per-stock channel series | `StocksBollsLoha` / `StocksBollsYear` tables |
| Combined LOHAS+Year signal | `StocksCoefsStav` table (`loha`/`year` = slope, `lohas`/`years` = signal code, `boll3`/`stav3`/`boll1`/`stav1` = zone codes) |

## Signal codes (`_good_price`) — current status

`_good_price` combines "position vs. five-line stave" with "position vs. LOHAS channel"
into a single code. **As currently written, only 6 of the 10 defined codes can ever be
the final output**, because the assignments are sequential `if`s (not `elsif`), and three
pairs/triples of codes share an identical condition — whichever is listed last always wins:

| Reachable | Dead (unreachable) | Shared condition |
|---|---|---|
| `SEL7` | `SEL3`, `SEL6` | `up1_up2 && mup_boll` |
| `WAT8` | `BUY4` | `dn1_dn2 && mup_boll` |
| `CHP0` | `WAT9` | `dn2_bot && mdn_bot` |
| `SAF1`, `SOX2`, `BUY5` | — | (unique conditions, unaffected) |

Additionally, `_good_model` ([lib/stock/stock.rb](../lib/stock/stock.rb), `return {} if good_coef < 1.0/STAVE`)
already filters out any stock with a non-positive/near-zero slope before it reaches
`_good_price`, consistent with the strategy's "only trade confirmed uptrends" rule. This
means the dead codes above (`SEL3`/`SEL6`/`BUY4`/`WAT9`) look like they were meant to
handle a negative-slope case that structurally cannot occur at this call site.

**Open question, pending verification against the original source before changing
behavior:** whether `SEL6`/`WAT8`/`WAT9` were always meant to be unreachable (by design,
since negative-slope stocks are filtered upstream — in which case the fix is deleting
them and merging the `SEL3`/`SEL7` duplicate), or whether the upstream filter in
`_good_model` was itself supposed to let negative-slope stocks through so these branches
could actually fire.

## Known limitations

Ways the current implementation falls short of the strategy as described, beyond the
signal-code bug above:

1. **Chart legend label collision.** In `_stave_data` ([lib/stock/stave.rb](../lib/stock/stave.rb)),
   both the trend line (趋势线) and the +2SD "top" band (乐观线) are labeled `"T"` in the
   chart series fed to Chartkick:
   ```ruby
   { name: "T", data: stave_trend },  # 趋势线
   ...
   { name: "T", data: stave_top   },  # 乐观线 (+2SD) — same label
   ```
   The chart legend can't visually distinguish these two of the five lines. Purely a
   display issue — the underlying data/computation is correct.

2. **No fundamentals screen.** The strategy explicitly requires the underlying company to
   be fundamentally sound ("股票背后的公司必须为良好体质的公司") — mean reversion is
   assumed to fail otherwise. The app has no fundamentals data source or company-quality
   check anywhere; it applies the statistical method to any stock that has enough price
   history and a positive regression slope. This is the largest gap between the
   documented strategy and the implementation, since the strategy's own stated failure
   mode (deteriorating company fundamentals) isn't guarded against at all.

3. **No grid-trading execution.** The strategy mentions treating the four bands between
   the five lines as grid-trading zones for capital allocation. The app is a
   classification/charting tool only — no position sizing or execution logic exists. This
   is likely acceptable as scope (decision support vs. auto-trading), not a bug, but is
   listed here for completeness.
