"""Is the engine's trend filter a negative selection, and why?

    python trend_filter.py OUT_DIR VIPDOC

The engine only models a stock whose linear regression slope over the window
is at least 0.01 yuan a day and whose last close is at most 100 yuan. A slope
in yuan is a price-level test as much as a trend test: 0.01 yuan a day is a
25% yearly trend for a 10-yuan stock and 2.5% for a 100-yuan one. This
script separates the two by comparing, against the all-A-share market:

1. the engine's universe;
2. a size-matched universe chosen by log-price slope (a trend in percent);
3. 5x5 double sorts on log slope and price level;
4. daily cross-sectional regressions of excess return on both
   (Fama-MacBeth, Newey-West errors).

Slopes use the engine's raw TDX closes, as the engine does; returns use the
adjusted closes from fetch_xdxr.py.
"""
import sys

import numpy as np
import pandas as pd

import analyze as A
import engine as E

H = 60
START, END = 20210101, 20261013


def rolling_slopes(dates, closes, window):
    """Linear (yuan/day) and log (per day) OLS slopes over each trailing window."""
    n = closes.size
    ends = np.nonzero((dates >= START) & (dates <= END))[0]
    ends = ends[ends >= window]           # engine: needs a record before the window
    if ends.size == 0:
        return None
    x = np.arange(n, dtype=np.float64)
    out = {}
    for name, y in (("lin", closes), ("log", np.log(closes))):
        cy = np.concatenate([[0.0], np.cumsum(y)])
        cxy = np.concatenate([[0.0], np.cumsum(x * y)])
        s = ends - window + 1
        sy = cy[ends + 1] - cy[s]
        sxy = cxy[ends + 1] - cxy[s] - s * sy          # x relative to window start
        sx = window * (window - 1) / 2
        sxx = (window - 1) * window * (2 * window - 1) / 6
        out[name] = (window * sxy - sx * sy) / (window * sxx - sx * sx)
    return pd.DataFrame({"date": dates[ends].astype(np.int32), "price": closes[ends],
                         "lin": out["lin"], "log_annual": out["log"] * E.YEARS})


def build(vipdoc, window):
    aliases = E.bj_aliases(vipdoc)
    frames = []
    for area in ("sh", "sz", "bj"):
        for code, path in E.stock_files(vipdoc, area):
            if not E.is_a_share(code) or code in aliases:
                continue
            dates, closes = E.read_day_file(path)
            ok = closes > 0
            df = rolling_slopes(dates[ok], closes[ok], window)
            if df is not None:
                df.insert(0, "stock", code)
                frames.append(df)
    df = pd.concat(frames, ignore_index=True)
    df["engine"] = (df["lin"] >= 1.0 / E.STAVE) & (df["price"] <= E.MAX_PRICE)
    return df


def nw(series, lag=H):
    m, se, t = A.newey_west(series.dropna().values, lag)
    return m, t


def report(name, df):
    col = f"r{H}"
    d = df.dropna(subset=[col])
    mkt = d.groupby("date")[col].mean()

    def excess(mask):
        g = d[mask].groupby("date")[col].agg(["mean", "size"])
        g = g[g["size"] >= 20]
        return g["mean"] - mkt.reindex(g.index)

    print(f"\n===== {name} window: {H}-day excess over the all-A-share mean =====")
    eng = d["engine"]
    m, t = nw(excess(eng))
    print(f"engine universe (lin >= 0.01, price <= 100): {m*100:+.2f}%  t={t:.1f}  "
          f"avg size {d[eng].groupby('date').size().mean():.0f}")

    # size-matched by log slope: each day the top-N by percent trend, N = engine size
    n_by_date = d[eng].groupby("date").size()
    d = d.assign(rank_log=d.groupby("date")["log_annual"].rank(ascending=False, method="first"))
    matched = d["rank_log"] <= d["date"].map(n_by_date).fillna(0)
    m, t = nw(excess(matched))
    print(f"top-N by log slope (same size each day):     {m*100:+.2f}%  t={t:.1f}")
    overlap = (matched & eng).sum() / max(eng.sum(), 1)
    print(f"  overlap with engine universe: {overlap:.0%}")
    for label, mask in (("log slope > 0, any price", d["log_annual"] > 0),
                        ("engine universe without the 100-yuan cap", d["lin"] >= 1.0 / E.STAVE)):
        m, t = nw(excess(mask))
        print(f"{label:44s} {m*100:+.2f}%  t={t:.1f}")

    # price level inside the engine universe vs outside
    print("\nengine universe by price quintile (quintiles of the whole market that day):")
    d = d.assign(pq=d.groupby("date")["price"].transform(lambda s: pd.qcut(s.rank(method="first"), 5, labels=False)),
                 sq=d.groupby("date")["log_annual"].transform(lambda s: pd.qcut(s.rank(method="first"), 5, labels=False)))
    share = d[eng].groupby("pq").size() / eng.sum()
    print("  share of engine universe:", " ".join(f"Q{int(k)+1}={v:.0%}" for k, v in share.items()))

    print("\n5x5 double sort, mean 60-day excess (rows: log-slope quintile, cols: price quintile):")
    tab = {}
    for (sq, pq), g in d.groupby(["sq", "pq"]):
        tab[(int(sq) + 1, int(pq) + 1)] = (g.groupby("date")[col].mean() - mkt).mean() * 100
    grid = pd.Series(tab).unstack()
    grid.index.name, grid.columns.name = "slope Q", "price Q"
    print(grid.round(2).to_string())
    print("  row means:", (grid.mean(axis=1)).round(2).to_dict())
    print("  col means:", (grid.mean(axis=0)).round(2).to_dict())

    # Fama-MacBeth: excess on z(log slope), z(log price)
    coefs = []
    for date, g in d.groupby("date"):
        if len(g) < 100:
            continue
        y = g[col] - g[col].mean()
        X = np.column_stack([np.ones(len(g)),
                             (g["log_annual"] - g["log_annual"].mean()) / g["log_annual"].std(),
                             (np.log(g["price"]) - np.log(g["price"]).mean()) / np.log(g["price"]).std()])
        b, *_ = np.linalg.lstsq(X, y.values, rcond=None)
        coefs.append((date, b[1], b[2]))
    fm = pd.DataFrame(coefs, columns=["date", "slope", "price"]).set_index("date").sort_index()
    for c in ("slope", "price"):
        m, t = nw(fm[c])
        print(f"Fama-MacBeth, 1 sd of {c:5s}: {m*100:+.2f}% per {H} days  t={t:.1f}")


def main():
    out_dir, vipdoc = sys.argv[1], sys.argv[2]
    prices = pd.read_parquet(f"{out_dir}/adjusted.parquet")
    fwd = A.forward_returns(prices)[["stock", "date", f"r{H}"]]
    for name, years in E.WINDOWS.items():
        df = build(vipdoc, years + E.STAVE)
        df = df.merge(fwd, on=["stock", "date"], how="left")
        report(name, df)


if __name__ == "__main__":
    main()
