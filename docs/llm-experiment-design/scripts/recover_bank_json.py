#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从逐题日志还原结构化答案 JSON（reference/09-capability-bank.md）。

用途：run_bank.ps1 被中断时结果 JSON 尚未落盘，但逐题日志已经写全
（finish / prompt_n / gen / wall / tps / 思考链 / 正文）。**不要为了拿回数据重跑模型。**

用法：
  python recover_bank_json.py --logs "<WorkDir>/logs" --bank <bank.json> --out-dir "<WorkDir>/data" [--force]
  日志文件名约定：bank_<tier>_<model>_<qid>.txt
"""
import argparse
import glob
import json
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

HDR = re.compile(
    r"^=== (?P<model>\S+) (?P<qid>\S+) (?P<label>.*?) finish=(?P<finish>\S+) "
    r"prompt_n=(?P<p>-?\d+) gen=(?P<g>-?\d+) wall=(?P<w>[\d.]+)s tps=(?P<t>[\d.]+) ===")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--logs", required=True, help="逐题日志目录（run_bank.ps1 的 <WorkDir>\\logs）")
    ap.add_argument("--bank", required=True, help="题库 JSON（提供 qid -> axis/gtype/max_tokens）")
    ap.add_argument("--out-dir", required=True, help="答案 JSON 输出目录")
    ap.add_argument("--tier", default=None, help="题库档（日志/输出文件名里的 tier；默认由 bank 文件名推断）")
    ap.add_argument("--force", action="store_true", help="忽略已有答案 JSON，完全以日志为准")
    a = ap.parse_args()

    tier = a.tier or ("hard" if "hard" in os.path.basename(a.bank) else "base")
    bank = {i["qid"]: i for i in json.load(open(a.bank, encoding="utf-8"))["items"]}
    order = [i["qid"] for i in json.load(open(a.bank, encoding="utf-8"))["items"]]
    os.makedirs(a.out_dir, exist_ok=True)

    pat = os.path.join(a.logs, "bank_%s_*_*.txt" % tier)
    per_model = {}
    for f in sorted(glob.glob(pat)):
        txt = open(f, encoding="utf-8", errors="replace").read()
        first = txt.split("\n", 1)[0].strip()
        m = HDR.match(first)
        if not m:
            print("  !! 表头无法解析，跳过:", os.path.basename(f))
            continue
        d = m.groupdict()
        if d["qid"] not in bank:
            print("  !! 日志里的 qid 不在题库中，跳过:", d["qid"])
            continue
        body = txt.split("\n", 1)[1] if "\n" in txt else ""
        _, _, rest = body.partition("--- thinking ---\n")
        think, sep, content = rest.partition("\n--- content ---\n")
        if not sep:
            think, content = "", rest
        per_model.setdefault(d["model"], {})[d["qid"]] = {
            "qid": d["qid"], "axis": bank[d["qid"]]["axis"], "label": d["label"],
            "gtype": bank[d["qid"]]["gtype"], "max_tokens": bank[d["qid"]].get("max_tokens"),
            "finish": d["finish"], "prompt_tokens": int(d["p"]), "gen": int(d["g"]),
            "wall": float(d["w"]), "tps": float(d["t"]), "thinking": think, "content": content,
            "recovered_from_log": os.path.basename(f),
        }

    if not per_model:
        print("没有匹配到日志（模式 %s）" % pat)
        return 1

    for model, recs in per_model.items():
        out = os.path.join(a.out_dir, "bank_%s_answers_%s.json" % (tier, model))
        if os.path.exists(out) and not a.force:
            for r in json.load(open(out, encoding="utf-8")):
                recs.setdefault(r["qid"], r)
            print("  与已有 %s 合并" % out)
        rows = [recs[q] for q in order if q in recs]
        json.dump(rows, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        missing = [q for q in order if q not in recs]
        trunc = [r["qid"] for r in rows if r["finish"] == "length"]
        print("%-10s -> %s  items=%d  截断=%s  缺=%s" % (model, out, len(rows), trunc, missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
