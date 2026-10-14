"""Check the Python replay against the Ruby engine, field by field.

    python verify.py sample  VIPDOC OUT_DIR [--per-code 40] [--stocks 400]
    bin/rails runner research/event_study/engine_truth.rb OUT_DIR/samples.csv OUT_DIR/truth.jsonl
    python verify.py compare OUT_DIR

Samples are stratified by signal code so rare codes (SEL3, WAT8, BUY4) are
covered, plus no-signal and no-model days.
"""
import argparse
import csv
import json
import os
import random

import numpy as np

import engine as E

START, END = 20210101, 20261013


def sample(args):
    rng = random.Random(args.seed)
    files = [(area, code, path) for area in ("sh", "sz", "bj")
             for code, path in E.stock_files(args.vipdoc, area) if E.is_a_share(code)]
    rng.shuffle(files)
    pools = {}
    for area, code, path in files[: args.stocks]:
        dates, closes = E.read_day_file(path)
        for window, years in E.WINDOWS.items():
            r = E.replay(dates, closes, years, START, END)
            if r is None:
                continue
            for i in range(r["date"].size):
                key = (window, E.SIGNALS[r["signal"][i]] if r["valid"][i] else "<invalid>")
                pools.setdefault(key, []).append((area, code, int(r["date"][i]), window,
                                                  E.SIGNALS[r["signal"][i]], int(r["stav"][i]),
                                                  int(r["boll_zone"][i]), bool(r["valid"][i])))
    chosen = []
    for key, rows in sorted(pools.items()):
        chosen += rng.sample(rows, min(args.per_code, len(rows)))
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "samples.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["area", "stock", "date", "window"])
        w.writerows(r[:4] for r in chosen)
    with open(os.path.join(args.out, "expected.jsonl"), "w") as f:
        for r in chosen:
            f.write(json.dumps(dict(zip(
                ["area", "stock", "date", "window", "signal", "stav", "boll", "valid"], r))) + "\n")
    print(f"{len(chosen)} samples over {len(pools)} (window, code) strata")
    for key in sorted(pools):
        print(f"  {key}: {len(pools[key])}")


def compare(args):
    def load(name):
        with open(os.path.join(args.out, name)) as f:
            return {(d["stock"], d["date"], d["window"]): d for d in map(json.loads, f)}
    exp, tru = load("expected.jsonl"), load("truth.jsonl")
    bad = 0
    for key, e in exp.items():
        t = tru.get(key)
        if t is None or not t["found"]:
            print("missing", key); bad += 1; continue
        fields = ["valid"] + (["signal", "stav", "boll"] if e["valid"] else [])
        diff = [f for f in fields if e[f] != t[f]]
        if diff:
            bad += 1
            print("MISMATCH", key, {f: (e[f], t[f]) for f in diff})
    print(f"{len(exp) - bad}/{len(exp)} samples agree")
    return bad


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sample")
    s.add_argument("vipdoc"); s.add_argument("out")
    s.add_argument("--per-code", type=int, default=40)
    s.add_argument("--stocks", type=int, default=400)
    s.add_argument("--seed", type=int, default=20261014)
    c = sub.add_parser("compare"); c.add_argument("out")
    a = p.parse_args()
    raise SystemExit(sample(a) if a.cmd == "sample" else (1 if compare(a) else 0))
