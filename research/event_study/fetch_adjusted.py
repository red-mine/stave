"""Build split- and dividend-adjusted closes: TDX raw closes x Sina hfq factors.

    python fetch_adjusted.py VIPDOC OUT_DIR [--beg 20201201] [--end 20261013]

The TDX .day files are the engine's own (unadjusted) data, so only the
adjustment factors are downloaded: Sina's hfq.js lists multiplicative
backward-adjustment factors, each in force from its date onward. Factor
files are cached under OUT_DIR/hfq/ (re-runs skip finished stocks).

Writes OUT_DIR/adjusted.parquet with columns stock, date, close (raw x hfq).
Old Beijing codes are folded into their 92xxxx successor, whose TDX file and
Sina factors both carry the full history.
"""
import argparse
import json
import os
import re
import time
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import pandas as pd
import requests

import engine as E

URL = "http://finance.sina.com.cn/realstock/company/{code}/hfq.js"
PAYLOAD = re.compile(r"=\s*(\{.*?\})\s*(?:/\*|$)", re.S)


def fetch(code, session, patience=3600):
    """Return [(yyyymmdd, factor)] ascending, [] if Sina has no file, None on failure.

    Sina answers 502 for a while after a burst; back off (up to 5 minutes
    between tries) for up to `patience` seconds instead of giving up.
    """
    waited, pause = 0, 15
    while waited <= patience:
        try:
            r = session.get(URL.format(code=code), timeout=15)
            if r.status_code == 404:
                return []
            r.raise_for_status()
            m = PAYLOAD.search(r.text)
            data = json.loads(m.group(1))["data"]
            return sorted((int(x["d"].replace("-", "")), float(x["f"])) for x in data)
        except Exception:
            time.sleep(pause)
            waited += pause
            pause = min(pause * 2, 300)
    return None


def adjust(dates, closes, factors):
    """Multiply each close by the factor in force on its date."""
    if not factors:
        return closes.copy()
    fd = np.array([d for d, _ in factors])
    ff = np.array([f for _, f in factors])
    i = np.searchsorted(fd, dates, side="right") - 1
    return closes * np.where(i >= 0, ff[np.clip(i, 0, None)], 1.0)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("vipdoc"); p.add_argument("out")
    p.add_argument("--beg", type=int, default=20201201)
    p.add_argument("--end", type=int, default=20261013)
    p.add_argument("--workers", type=int, default=1)
    p.add_argument("--delay", type=float, default=2.0,
                   help="seconds between requests per worker; Sina returns 502s when pushed")
    p.add_argument("--only-missing-from", metavar="DIR",
                   help="fetch only stocks without a non-empty <code>.csv in DIR")
    a = p.parse_args()

    aliases = E.bj_aliases(a.vipdoc)
    paths = {}
    for area in ("sh", "sz", "bj"):
        for c, path in E.stock_files(a.vipdoc, area):
            if E.is_a_share(c) and c not in aliases:
                dates, _ = E.read_day_file(path)
                if dates.size and dates[-1] >= a.beg:   # skip long-delisted stocks
                    paths[c] = path
    if a.only_missing_from:
        def have(c):
            f = os.path.join(a.only_missing_from, c + ".csv")
            return os.path.exists(f) and os.path.getsize(f) > len("date,close\n")
        paths = {c: p for c, p in paths.items() if not have(c)}
    cache = os.path.join(a.out, "hfq")
    os.makedirs(cache, exist_ok=True)
    todo = [c for c in paths if not os.path.exists(os.path.join(cache, c + ".json"))]
    print(f"{len(paths)} stocks, {len(todo)} factor files to fetch", flush=True)

    session = requests.Session()
    session.headers["User-Agent"] = "Mozilla/5.0"

    def job(code):
        rows = fetch(code, session)
        if rows is not None:
            with open(os.path.join(cache, code + ".json"), "w") as f:
                json.dump(rows, f)
        time.sleep(a.delay)
        return code, rows

    failed, missing = [], []
    with ThreadPoolExecutor(a.workers) as ex:
        for i, (code, rows) in enumerate(ex.map(job, todo), 1):
            if rows is None:
                failed.append(code)
            if i % 500 == 0:
                print(f"  {i}/{len(todo)} ({len(failed)} failed)", flush=True)
    if failed:
        raise SystemExit(f"{len(failed)} failed (re-run to resume): {failed[:20]}")

    frames = []
    for code, path in paths.items():
        with open(os.path.join(cache, code + ".json")) as f:
            factors = json.load(f)
        if not factors:
            missing.append(code)
            continue
        dates, closes = E.read_day_file(path)
        keep = (dates >= a.beg) & (dates <= a.end) & (closes > 0)
        frames.append(pd.DataFrame({"stock": code, "date": dates[keep].astype("int32"),
                                    "close": adjust(dates[keep], closes[keep], factors)}))
    out = pd.concat(frames, ignore_index=True)
    out.to_parquet(os.path.join(a.out, "adjusted.parquet"), index=False)
    print(f"{out.stock.nunique()} stocks adjusted, {len(out)} rows; "
          f"{len(missing)} without a Sina factor file: {missing[:15]}")


if __name__ == "__main__":
    main()
