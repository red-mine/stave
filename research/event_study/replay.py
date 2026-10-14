"""Replay the engine for every A-share, every trading day, both windows.

    python replay.py VIPDOC OUT_DIR [--start 20210101] [--end 20261013]

Writes OUT_DIR/signals.parquet with one row per (stock, date, window) on
which the engine produces a model (valid stock-days only): the universe the
analysis uses for its cross-sectional baseline.
"""
import argparse
import os
from multiprocessing import Pool

import numpy as np
import pandas as pd

import engine as E


def run_one(job):
    area, code, path, start, end = job
    dates, closes = E.read_day_file(path)
    frames = []
    for window, years in E.WINDOWS.items():
        r = E.replay(dates, closes, years, start, end)
        if r is None:
            continue
        keep = r["valid"]
        if not keep.any():
            continue
        frames.append(pd.DataFrame({
            "stock": code, "area": area, "window": window,
            "date": r["date"][keep].astype(np.int32),
            "signal": np.array(E.SIGNALS, dtype=object)[r["signal"][keep]],
            "stav": r["stav"][keep], "boll_zone": r["boll_zone"][keep],
            "coef": r["coef"][keep], "price": r["price"][keep],
        }))
    return pd.concat(frames) if frames else None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("vipdoc"); p.add_argument("out")
    p.add_argument("--start", type=int, default=20210101)
    p.add_argument("--end", type=int, default=20261013)
    p.add_argument("--workers", type=int, default=max(1, os.cpu_count() - 1))
    a = p.parse_args()
    jobs = [(area, code, path, a.start, a.end) for area in ("sh", "sz", "bj")
            for code, path in E.stock_files(a.vipdoc, area) if E.is_a_share(code)]
    print(f"{len(jobs)} A-share files")
    with Pool(a.workers) as pool:
        parts = [f for f in pool.imap_unordered(run_one, jobs, chunksize=8) if f is not None]
    df = pd.concat(parts, ignore_index=True)
    df["window"] = df["window"].astype("category")
    df["area"] = df["area"].astype("category")
    os.makedirs(a.out, exist_ok=True)
    df.to_parquet(os.path.join(a.out, "signals.parquet"), index=False)
    print(df.groupby(["window", "signal"], observed=True).size().unstack(0))
    print(f"{df.stock.nunique()} stocks with a model at least once; {len(df)} rows")


if __name__ == "__main__":
    main()
