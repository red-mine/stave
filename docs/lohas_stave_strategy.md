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
into a single code. The assignments are sequential `if`s (not `elsif`), so whenever two
codes shared an identical condition, whichever was listed last always won and the earlier
one was permanently dead code:

| Reachable | Dead (unreachable) | Shared condition |
|---|---|---|
| `SEL7` | `SEL3`, `SEL6` | `up1_up2 && mup_boll` |
| `WAT8` | `BUY4` | `dn1_dn2 && mup_boll` |
| `CHP0` | ~~`WAT9`~~ (fixed, see below) | ~~`dn2_bot && mdn_bot`~~ |
| `SAF1`, `SOX2`, `BUY5` | — | (unique conditions, unaffected) |

`_good_model` ([lib/stock/stock.rb](../lib/stock/stock.rb), `return {} if good_coef < 1.0/STAVE`)
already filters out any stock with a non-positive/near-zero slope before it reaches
`_good_price`. Web research (see Sources below) confirms this matches 薛兆亨's actual
methodology — the five-line method assumes a stock in a confirmed uptrend, and multiple
independent sources describe negative slope as undermining the whole mean-reversion
premise, with no indication that negative-slope stocks are meant to still generate
distinct signals in this system. **So the upstream filter is correct by design, not a bug.**

### Resolved: `WAT9` vs `CHP0`

This was **not** a slope distinction — it's a LOHAS-channel-recovery distinction. Sourced
directly from 薛兆亨/Tivo168's own case studies (CMoney) and a Smart自学网 explainer,
which both state the rule verbatim and give dated examples (e.g. "2016/1/22 五線譜在
TL-2SD，且樂活通道由跌破下沿回到正常區間" → buy):

> 「若股價跌破樂活五線譜的悲觀區，且股價跌破樂活通道下沿時，先不要買進，等到股價回到
> 樂活通道以後再買進。」

i.e. still below the channel's lower edge → **wait** (don't catch the falling knife);
channel has recovered back into normal range while price is still in the extreme
pessimistic five-line zone → **buy**. Fixed in code:

```ruby
good_stave = "WAT9" if good_dn2_bot && good_mdn_bot   # unchanged: still below channel
good_stave = "CHP0" if good_dn2_bot && good_mdn_boll  # fixed: was good_mdn_bot (dup of WAT9)
```

**Caveat:** every dated example in the sources describes a *breakout-then-reversion
event* (price broke through the channel edge and has *since* returned to normal range) as
the actual trigger — not merely "currently sitting in the normal range." `_good_price`
only evaluates the current day's snapshot, with no memory of whether the channel was
recently breached, so this fix is a reasonable static approximation of the real rule, not
a fully faithful implementation of it. A fully faithful version would need to track the
channel's recent state transition over time.

### Still open: `SEL3`/`SEL6`/`SEL7` and `BUY4`/`WAT8`

No source found gives an explicit rule distinguishing these. The sell-side examples
follow the same breakout-then-reversion pattern (symmetric to the buy case), consistent
with `SEL7`'s condition, but nothing explains why `SEL3`/`SEL6` exist as separate codes.
Likewise nothing confirms what should distinguish `BUY4` ("boll up?") from `WAT8` ("boll
dn?") beyond the comment text itself hinting `WAT8` should test a different channel
condition than `mup_boll` — nothing found says which one. Likely the exact decision table
lives only in 薛兆亨/Tivo168's paid CMoney tool, not in free public sources. Left
untouched pending further verification.

### Sources

- [樂活五線譜結合樂活通道的實證 (CMoney)](https://cmnews.com.tw/article/xuezhaohengtivo168-b374d808-d8c8-11ef-9bed-da1b84cd5fce) — dated buy/sell case studies showing the channel-recovery trigger
- [ETF投資術：先用樂活五線譜找買點 (Smart自学网)](https://smart.businessweekly.com.tw/Reading/IndepArticle.aspx?id=6001781) — states the "wait for channel recovery" rule verbatim
- [薛兆亨&Tivo168 | 樂活五線譜 x 投資儀表板 (CMoney)](https://www.cmoney.tw/app/expert/tivostaff) — tool overview
- [樂活五線譜-薛兆亨Tivo App (App Store)](https://apps.apple.com/tw/app/%E6%A8%82%E6%B4%BB%E4%BA%94%E7%B7%9A%E8%AD%9C-%E8%96%9B%E5%85%86%E4%BA%A8tivo/id1624433798) — confirms authorship/branding

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
