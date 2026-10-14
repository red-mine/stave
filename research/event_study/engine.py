"""Vectorised replay of the Ruby signal engine (lib/stock/stock.rb).

For one stock and one window it evaluates, for every eligible end-of-day
record, exactly what `Stock::Stock.new(area, years, trim: t)` would compute
when the file ended on that record: the regression model, the stave and
channel bands, and the `_signal` classification.

The numerics follow Ruby's, not numpy's defaults, because signal codes
flip on comparisons against bands rounded to the cent:

* `Float#round(2)` is round-half-up with Ruby's correction step
  (`round_half_up` in numeric.c), not banker's rounding.
* `Array#sum` over floats is Kahan-Babuska compensated summation.
* `reduce(&:+)` (used by `_move`) is a plain left-to-right sum.
"""
import os
import struct

import numpy as np

WEEKS = 5
YEARS = 250
STAVE = 20 * WEEKS                 # 100
LOHAS = 3 * YEARS + YEARS // 2     # 875
WINDOWS = {"lohas": LOHAS, "year": YEARS}
MAX_PRICE = STAVE                  # Stock::Stock default max_price
PRICE_SCALE = 100

SIGNALS = ["", "SAF1", "SOX2", "BUY5", "SEL3", "SEL6", "SEL7",
           "WAT8", "BUY4", "WAT9", "CHP0"]
CODE = {s: i for i, s in enumerate(SIGNALS)}
FAMILY = {"SAF1": "BUY", "BUY4": "BUY", "BUY5": "BUY", "CHP0": "BUY",
          "SEL3": "SELL", "SEL6": "SELL", "SEL7": "SELL",
          "SOX2": "SOAR", "WAT8": "WAT", "WAT9": "WAT", "": "NONE"}

A_SHARE_PREFIXES = {
    "sz": ("sz00", "sz30"),
    "sh": ("sh60", "sh68"),
    "bj": ("bj43", "bj83", "bj87", "bj88", "bj92"),
}


def read_day_file(path):
    """Return (dates int32 yyyymmdd, closes float64) for a TDX .day file."""
    raw = np.fromfile(path, dtype="<u4")
    if raw.size == 0:
        return np.zeros(0, np.int64), np.zeros(0)
    rec = raw[: raw.size // 8 * 8].reshape(-1, 8)
    return rec[:, 0].astype(np.int64), rec[:, 4] / PRICE_SCALE


def is_a_share(code):
    return code.startswith(A_SHARE_PREFIXES[code[:2]])


# --- Ruby numerics -------------------------------------------------------

def rround2(x):
    """Ruby Float#round(2) (round_half_up in numeric.c), elementwise."""
    x = np.asarray(x, dtype=np.float64)
    s = 100.0
    xs = x * s
    t = np.trunc(xs)
    f = np.where(np.abs(xs - t) >= 0.5, t + np.sign(xs), t)  # C round()
    pos = x > 0
    neg = x < 0
    f = np.where(pos & ((f + 0.5) / s <= x), f + 1, f)
    f = np.where(neg & ((f - 0.5) / s >= x), f - 1, f)
    out = f / s
    return np.where(x == 0.0, x, out)


class KB:
    """Kahan-Babuska accumulator vectorised over many independent sums."""

    def __init__(self, n):
        self.f = np.zeros(n)
        self.c = np.zeros(n)

    def add(self, x):
        f = self.f
        t = f + x
        self.c += np.where(np.abs(f) >= np.abs(x), (f - t) + x, (x - t) + f)
        self.f = t

    def value(self):
        return self.f + self.c


def kb_window_sum(values, starts, length):
    """Ruby `values[s, length].sum` for every s in starts."""
    acc = KB(len(starts))
    for k in range(length):
        acc.add(values[starts + k])
    return acc.value()


def seq_moving_avg(p, n):
    """Ruby `_move`: each_cons(n).map { reduce(&:+).fdiv(n).round(2) }."""
    m = p.size - n + 1
    if m <= 0:
        return np.zeros(0)
    s = p[0:m].copy()
    for k in range(1, n):
        s = s + p[k:k + m]
    return rround2(s / n)


# --- Replay --------------------------------------------------------------

def replay(dates, closes, years, start_date, end_date):
    """Evaluate the engine for each record whose date is in [start, end].

    Returns a dict of arrays, one entry per evaluated record:
      idx, date, valid (has model), coef, price, signal (code), stav, boll_zone
    Records where the Ruby engine would not produce a model get valid=False.
    """
    days = years + STAVE
    n = dates.size
    # Ruby _files: File.size > (days + trim) * 32  =>  end index e >= days.
    cand = np.nonzero((dates >= start_date) & (dates <= end_date))[0]
    cand = cand[cand >= days]
    if cand.size == 0:
        return None
    E = cand
    S = E - days + 1                          # window start index
    last = closes[E]

    valid = last <= MAX_PRICE                 # _model_data price cap

    # ---- regression (_model) ----
    idx = np.arange(days, dtype=np.float64)
    count = days
    sum_x = days * (days - 1) // 2
    sum_xx = (days - 1) * days * (2 * days - 1) // 6
    acc_y = KB(E.size)
    acc_xy = KB(E.size)
    nuniq_ok = np.zeros(E.size, dtype=bool)
    first = closes[S]
    for k in range(days):
        y = closes[S + k]
        acc_y.add(y)
        acc_xy.add(idx[k] * y)
        nuniq_ok |= y != first
    sum_y = acc_y.value()
    sum_xy = acc_xy.value()
    div = float(count * sum_xx - sum_x * sum_x)
    coef = (count * sum_xy - sum_x * sum_y) / div
    inter = (sum_y - coef * sum_x) / count
    valid &= nuniq_ok & np.isfinite(coef) & (coef >= 1.0 / STAVE) & np.isfinite(inter)

    # ---- moving averages over the whole file, reused by every window ----
    avg = seq_moving_avg(closes, STAVE)       # avg[j] = mean(closes[j..j+99])
    # distance for the average ending at record r: (closes[r] - avg[r-99])^2
    dist = np.full(n, np.nan)
    dist[STAVE - 1:] = (closes[STAVE - 1:] - avg) ** 2

    def bands(end, n_prices):
        """_signal_bands for prices = closes[S .. end] (n_prices long)."""
        boll = rround2(kb_window_sum(closes, end - STAVE + 1, STAVE) / STAVE)
        dsum = kb_window_sum(dist, end - STAVE + 1, STAVE)
        deviation = rround2(np.sqrt(rround2(dsum / STAVE)))
        last_index = n_prices - 1
        trend = rround2(coef * last_index + inter)
        return boll, deviation, trend

    # residual sums: indices STAVE-1 .. days-1 (current) and .. days-2 (previous)
    acc_r = KB(E.size)
    prev_rsum = None
    for k in range(STAVE - 1, days):
        if k == days - 1:
            prev_rsum = acc_r.value()
        expected = rround2(coef * k + inter)
        acc_r.add((closes[S + k] - expected) ** 2)
    cur_rsum = acc_r.value()
    cur_sqrt = np.sqrt(cur_rsum / (days - (STAVE - 1)))
    prev_sqrt = np.sqrt(prev_rsum / (days - 1 - (STAVE - 1)))

    def full_bands(end, n_prices, sqrt):
        boll, dev, trend = bands(end, n_prices)
        return dict(
            boll=boll,
            mup=rround2(boll + dev * 2), mdn=rround2(boll - dev * 2),
            trend=trend,
            up1=rround2(trend + sqrt), dn1=rround2(trend - sqrt),
            up2=rround2(trend + sqrt * 2), dn2=rround2(trend - sqrt * 2),
        )

    cur = full_bands(E, days, cur_sqrt)
    prv = full_bands(E - 1, days - 1, prev_sqrt)   # prices.length > STAVE always
    prev_price = closes[E - 1]

    # ---- _falling_averages? ----
    falling = np.ones(E.size, dtype=bool)
    for w in (5, 10, 20, 40):
        cur_avg = kb_window_sum(closes, E - w + 1, w) / w
        prev_avg = kb_window_sum(closes, E - 20 - w + 1, w) / w
        falling &= cur_avg < prev_avg

    sig, stav, bzone = classify(last, cur, prev_price, prv, falling)
    return dict(idx=E, date=dates[E], valid=valid, coef=coef, price=last,
                signal=np.where(valid, sig, 0), stav=stav, boll_zone=bzone)


def classify(last, b, prev_price, pb, falling):
    """Ruby `_signal`, elementwise. Returns (signal code, stav, boll zone)."""
    trend, boll = b["trend"], b["boll"]
    up1_trend = (last < b["up1"]) & (last > trend)
    up1_up2 = (last > b["up1"]) & (last < b["up2"])
    up2_top = last > b["up2"]
    dn1_trend = (last > b["dn1"]) & (last < trend)
    dn1_dn2 = (last < b["dn1"]) & (last > b["dn2"])
    dn2_bot = last < b["dn2"]
    mup_boll = (last < b["mup"]) & (last > boll)
    mup_top = last > b["mup"]
    mdn_boll = (last > b["mdn"]) & (last < boll)
    mdn_bot = last < b["mdn"]
    crossed_stave_top = (prev_price > pb["up2"]) & (last < b["up2"])
    crossed_channel_top = (prev_price > pb["mup"]) & (last < b["mup"])

    s = np.zeros(last.size, dtype=np.int8)
    s = np.where(dn1_dn2 & mdn_boll, CODE["SAF1"], s)
    s = np.where(up1_up2 & mup_top, CODE["SOX2"], s)
    s = np.where(up1_trend & mup_boll, CODE["BUY5"], s)
    sell = np.where(crossed_stave_top & crossed_channel_top, CODE["SEL3"],
                    np.where(crossed_channel_top, CODE["SEL6"], CODE["SEL7"]))
    s = np.where(up1_up2 & mup_boll, sell, s)
    s = np.where(dn1_dn2 & mup_boll, np.where(falling, CODE["WAT8"], CODE["BUY4"]), s)
    s = np.where(dn2_bot & mdn_bot, CODE["WAT9"], s)
    s = np.where(dn2_bot & mdn_boll, CODE["CHP0"], s)

    z = np.zeros(last.size, dtype=np.int8)   # 0 = Ruby leaves the float midline
    z = np.where(mup_boll, 1, z)
    z = np.where(mup_top, 2, z)
    z = np.where(mdn_boll, -1, z)
    z = np.where(mdn_bot, -2, z)

    v = np.zeros(last.size, dtype=np.int8)   # 0 = Ruby nil
    v = np.where(up1_trend, 1, v)
    v = np.where(up1_up2, 2, v)
    v = np.where(up2_top, 3, v)
    v = np.where(dn1_trend, -1, v)
    v = np.where(dn1_dn2, -2, v)
    v = np.where(dn2_bot, -3, v)
    return s.astype(np.int8), v, z


def stock_files(vipdoc, area):
    d = os.path.join(vipdoc, area, "lday")
    for fn in sorted(os.listdir(d)):
        if fn.endswith(".day"):
            yield fn[:8], os.path.join(d, fn)


def bj_aliases(vipdoc):
    """Map pre-2025 BJ codes to the 92xxxx code that continues them.

    After the Beijing exchange moved listings to 92xxxx codes TDX keeps both
    files: the old one stops at the switch, the new one carries the whole
    history. A pair is recognised by identical closes on the old file's last
    20 records.
    """
    files = {code: path for code, path in stock_files(vipdoc, "bj") if is_a_share(code)}
    new = {}
    for code, path in files.items():
        if code.startswith("bj92"):
            d, c = read_day_file(path)
            new[code] = dict(zip(d.tolist(), c.tolist()))
    aliases = {}
    for code, path in files.items():
        if code.startswith("bj92"):
            continue
        d, c = read_day_file(path)
        if d.size < 20:
            continue
        tail = list(zip(d[-20:].tolist(), c[-20:].tolist()))
        guess = "bj92" + code[4:]
        candidates = [guess] + [k for k in new if k != guess]
        for k in candidates:
            series = new.get(k)
            if series and all(series.get(dd) == cc for dd, cc in tail):
                aliases[code] = k
                break
    return aliases
