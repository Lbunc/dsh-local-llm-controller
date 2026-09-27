#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""能力题库判分器（reference/09-capability-bank.md）——两档冻结题库通用。

题型（题库 JSON 里的 gtype 字段）：
  mc       多选，取「最后一次显式结论」优先，退回最后 (X)、最后独立字母
  yesno    是/否，取最后一个 yes/no
  int      整数，取最后一个 \\boxed{} 内整数，退回最后一个整数
  words    目标词按序出现在回答词序列中
  sym      括号串，取最后一段
  grid     网格逐行精确匹配
  code     编程题：拆代码块 → 每块单独判分取最高（避免多块拼接互相覆盖）
  lcb_ref  竞赛编程：抽出代码块 → 逐条跑官方/参考用例比对 stdin/stdout → 全过才算对

状态：ok / truncated（finish=length 且判分不通过 → 记「未产出」，**不进球数分母、不得判 0**）/ error / not-run

用法：
  python grade_bank.py --bank <bank.json> --answers "<glob>" [--out <grading.json>] [--models a b]
  python grade_bank.py                       # 默认判困难库（skill 内 bank/10q_hard.json）
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
import tempfile

try:                       # Windows 控制台常为 GBK，emoji/中文会 UnicodeEncodeError
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

LETTERS = "ABCDEFGHIJ"
SKILL_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BANK_DIR = os.path.join(SKILL_ROOT, "bank")


def norm(s):
    return re.sub(r"\s+", " ", (s or "")).strip()


# ------------------------------------------------------------------ extractors
def ex_int(text):
    t = text or ""
    for cand in reversed(re.findall(r"\\boxed\s*\{\s*([^}]*?)\s*\}", t)):
        m = re.search(r"-?\d+", cand.replace(",", ""))
        if m:
            return int(m.group()), "boxed(%s)" % cand.strip()[:24]
    m = list(re.finditer(r"(?:final\s+answer|answer)\s*(?:is|:|=)?\s*\$?\s*(-?\d[\d,]*)", t, re.I))
    if m:
        return int(m[-1].group(1).replace(",", "")), "answer-phrase"
    nums = re.findall(r"-?\d[\d,]*", t)
    return (int(nums[-1].replace(",", "")), "last-int") if nums else (None, "no-integer")


def ex_mc(text):
    t = text or ""
    pats = [
        (r"(?:correct answer is|the answer is|答案)\s*[:：]?\s*\**\(?\s*([A-Ja-j])\s*\)?", "answer-is-(X)"),
        (r"answer\s*(?:is|:|=)\s*\(?\s*([A-J])\b", "answer: X"),
        (r"\\boxed\s*\{\s*\(?\s*([A-J])\s*\)?\s*\}", "boxed(X)"),
        (r"\(([A-J])\)", "(X)"),
    ]
    for pat, how in pats:
        m = list(re.finditer(pat, t, re.I))
        if m:
            return m[-1].group(1).upper(), how
    m = list(re.finditer(r"\b([A-J])\b", t))
    return (m[-1].group(1).upper(), "last-standalone-letter") if m else (None, "no-letter")


def ex_code_blocks(text):
    t = text or ""
    blocks = re.findall(r"```(?:python|py|python3)?\s*\n(.*?)```", t, re.S)
    if not blocks:
        blocks = re.findall(r"```\s*\n(.*?)```", t, re.S)
    return [b for b in (blocks or [t]) if b.strip()]


# ------------------------------------------------------------------ graders
def g_mc(ans, target):
    got, how = ex_mc(ans)
    return got, (got is not None and got == str(target).strip("()").upper()), how


def g_yesno(ans, target):
    m = re.findall(r"\b(yes|no)\b", (ans or "").lower())
    got = m[-1] if m else ""
    return got, got == str(target).strip().lower(), "last-yes/no"


def g_int(ans, target):
    got, how = ex_int(ans)
    try:
        ok = got is not None and int(got) == int(target)
    except Exception:
        ok = False
    return got, ok, how


def g_words(ans, target):
    toks = re.findall(r"[a-z]+", (ans or "").lower())
    want = [w.lower() for w in str(target).split()]
    i = 0
    for t in toks:
        if i < len(want) and t == want[i]:
            i += 1
    return "%d/%d 词按序命中" % (i, len(want)), i == len(want), "ordered-subsequence"


def g_sym(ans, target):
    runs = re.findall(r"[()\[\]{}]{1,}", ans or "")
    got = runs[-1] if runs else ""
    return got, got.replace(" ", "") == str(target).replace(" ", ""), "last-bracket-run"


def g_grid(ans, target):
    rows = [l.strip() for l in (ans or "").splitlines() if re.fullmatch(r"\d+", l.strip())]
    want = [l.strip() for l in str(target).splitlines() if l.strip()]
    return "%d 行(期望 %d)" % (len(rows), len(want)), rows == want, "digit-row-match"


def g_code(ans, item):
    """拆 python 代码块 → 每块单独 exec 官方测试 → 取最高分"""
    blocks = ex_code_blocks(ans)
    tried, best = [], 0
    for b in blocks:
        src = item.get("prompt", "") + "\n" + b
        try:
            ns = {}
            exec(compile(src, "<model>", "exec"), ns)
            fn = ns.get(item.get("entry"))
            if fn is None:
                tried.append("no-entry")
                continue
            exec(compile(item.get("test", ""), "<test>", "exec"), ns)
            ns["check"](fn)
            best, _ = 1, tried.append("pass")
            break
        except Exception as e:
            tried.append(type(e).__name__)
    return "blocks=%d %s" % (len(blocks), ",".join(tried[:4])), best == 1, "official-test"


def _run_prog(code, stdin_data, timeout=15):
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "sol.py")
        open(p, "w", encoding="utf-8").write(code)
        try:
            r = subprocess.run([sys.executable, p], input=stdin_data, capture_output=True,
                               text=True, timeout=timeout, encoding="utf-8", errors="replace")
        except subprocess.TimeoutExpired:
            return None, "timeout"
        except Exception as e:
            return None, "exec-err:%s" % type(e).__name__
        if r.returncode != 0:
            tail = (r.stderr or "").strip().splitlines()
            return None, "re:%d:%s" % (r.returncode, tail[-1][:50] if tail else "")
        return r.stdout, "ok"


def g_lcb(ans, item):
    """竞赛编程：每块单独跑全部用例，取通过数最高的块"""
    tests = item.get("tests", [])
    blocks = ex_code_blocks(ans)
    best = {"passed": 0, "total": len(tests), "blocks": len(blocks), "detail": []}
    for i, b in enumerate(blocks):
        det, passed = [], 0
        for t in tests:
            got, how = _run_prog(b, t["input"])
            ok = how == "ok" and _norm_out(got) == _norm_out(t["output"])
            passed += 1 if ok else 0
            det.append({"src": t.get("src", "official"), "ok": ok, "how": how})
        if passed > best["passed"]:
            best = {"passed": passed, "total": len(tests), "blocks": len(blocks),
                    "detail": det, "block_index": i}
    return "%d/%d" % (best["passed"], best["total"]), best["passed"] == best["total"] and best["total"] > 0, best


def _norm_out(s):
    return "\n".join(l.strip() for l in (s or "").strip().splitlines() if l.strip())


PLAIN = {"mc": g_mc, "yesno": g_yesno, "int": g_int, "words": g_words, "sym": g_sym, "grid": g_grid}


def grade_item(item, rec):
    """→ (correct, extracted, how, test_detail)"""
    content = (rec or {}).get("content") or ""
    gt = item["gtype"]
    if gt == "code":
        d, ok, how = g_code(content, item)
        return ok, d, how, None
    if gt == "lcb_ref":
        d, ok, detail = g_lcb(content, item)
        return ok, d, "runs official+reference tests", detail
    if gt in PLAIN:
        d, ok, how = PLAIN[gt](content, item["answer"])
        return ok, d, how, None
    return False, None, "unknown-gtype:%s" % gt, None


def main():
    ap = argparse.ArgumentParser(description="Grade a frozen capability bank run.")
    ap.add_argument("--bank", default=os.path.join(BANK_DIR, "10q_hard.json"))
    ap.add_argument("--answers", default=None, help="答案 JSON 的 glob（默认按 bank 名推导）")
    ap.add_argument("--out", default=None)
    ap.add_argument("--models", nargs="*", default=None)
    ap.add_argument("--label", default="")
    a = ap.parse_args()

    tier = "hard" if "hard" in os.path.basename(a.bank) else "base"
    if not a.answers:
        a.answers = os.path.join(os.path.dirname(os.path.abspath(a.bank)),
                                 "..", "data", "bank_%s_answers_*.json" % tier)
    if not a.out:
        a.out = os.path.join(os.getcwd(), "data", "bank_%s_grading.json" % tier)

    bank = json.load(open(a.bank, encoding="utf-8"))
    items = bank["items"]
    meta = {i["qid"]: i for i in items}
    order = [i["qid"] for i in items]

    files = sorted(glob.glob(a.answers))
    if a.models:
        files = [f for f in files if any(("_%s.json" % m) in f for m in a.models)]
    if not files:
        print("没有找到答案 JSON：%s" % a.answers)
        return 1

    all_models = {}
    for f in files:
        m = re.search(r"_answers_(.+)\.json$", f)
        name = m.group(1) if m else os.path.basename(f)
        rows = {r["qid"]: r for r in json.load(open(f, encoding="utf-8"))}
        res = {}
        for q in order:
            it = meta[q]
            rec = rows.get(q)
            cell = {"qid": q, "axis": it["axis"], "label": it.get("label"), "gtype": it["gtype"],
                    "key": it["answer"], "official_key": it.get("official_key")}
            if rec is None:
                cell.update(state="not-run", correct=False, extracted=None, how="未跑")
            elif rec.get("error"):
                cell.update(state="error", correct=False, extracted=None,
                            how="request-error: %s" % str(rec["error"])[:70])
            else:
                ok, got, how, detail = grade_item(it, rec)
                cell.update(correct=ok, extracted=got, how=how,
                            finish=rec.get("finish"), gen=rec.get("gen"), wall=rec.get("wall"),
                            tps=rec.get("tps"), prompt_tokens=rec.get("prompt_tokens"))
                if detail:
                    cell["test_detail"] = detail
                # 截断：判分不通过才算「未产出」；判分通过说明答案已完整
                cell["state"] = "truncated" if (not ok and rec.get("finish") == "length") else "ok"
            res[q] = cell
        all_models[name] = res

    # ---------------- 报告 ----------------
    if a.label:
        print("### %s" % a.label)
    hdr = "%-5s %-12s %-8s " % ("qid", "gtype", "key") + " ".join("%-12s" % m[:12] for m in all_models)
    print(hdr)
    print("-" * len(hdr))
    for q in order:
        cells = []
        for m in all_models:
            r = all_models[m][q]
            mark = "OK" if r["correct"] else ("TR" if r["state"] == "truncated" else "x")
            cells.append("%-12s" % ("%s:%s" % (mark, str(r["extracted"])[:7])))
        print("%-5s %-12s %-8s " % (q, meta[q]["gtype"], str(meta[q]["answer"])[:8]) + " ".join(cells))

    print()
    summary = {}
    for m, res in all_models.items():
        graded = [r for r in res.values() if r["state"] not in ("error", "not-run")]
        eff = [r for r in graded if r["state"] != "truncated"]
        ncorr = sum(1 for r in eff if r["correct"])
        summary[m] = {"total_items": len(res), "correct": ncorr, "effective": len(eff),
                      "truncated": sum(1 for r in graded if r["state"] == "truncated"),
                      "error": sum(1 for r in res.values() if r["state"] == "error"),
                      "not_run": sum(1 for r in res.values() if r["state"] == "not-run"),
                      "score_all": "%d/%d" % (ncorr, len(res)),
                      "score_effective": "%d/%d" % (ncorr, len(eff))}
        print("%-10s 全对 %d/%d  有效 %s  截断 %d  错误 %d  未跑 %d"
              % (m, ncorr, len(res), summary[m]["score_effective"], summary[m]["truncated"],
                 summary[m]["error"], summary[m]["not_run"]))
        for r in res.values():
            if not r["correct"] and r["state"] not in ("not-run",):
                print("    %s [%s] key=%s extracted=%s via %s"
                      % (r["qid"], r["state"], r["key"], r["extracted"], r["how"]))

    # ---------------- 区分度门 ----------------
    print("\n--- 区分度门 ---")
    if len(all_models) == 2:
        a1, b1 = list(all_models)
        sa = summary[a1]["correct"] / max(1, summary[a1]["effective"])
        sb = summary[b1]["correct"] / max(1, summary[b1]["effective"])
        diff = [q for q in order if all_models[a1][q]["correct"] != all_models[b1][q]["correct"]]
        both_ok = [q for q in order if all_models[a1][q]["correct"] and all_models[b1][q]["correct"]]
        both_bad = [q for q in order if not all_models[a1][q]["correct"] and not all_models[b1][q]["correct"]]
        print("  %s=%.2f  %s=%.2f  分差=%.2f" % (a1, sa, b1, sb, abs(sa - sb)))
        print("  同对=%s  同错=%s  仅一方对=%s" % (both_ok, both_bad, diff))
        if not diff:
            print("  => 本库对该两模型无区分度：结论只能写「测不出差异」，不得排名次")
        elif len(diff) == 1:
            print("  => 只有 1 道差异题（n=1，不足以排名次）→ 按 reference/09 做「区分度轴复现检验」再下结论")
        else:
            print("  => 有区分度（%d 题）" % len(diff))
    else:
        print("  只有 %d 个模型结果，跳过（需要 2 个才能判区分度）" % len(all_models))

    json.dump({"summary": summary, "models": all_models}, open(a.out, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("\nwrote %s" % a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
