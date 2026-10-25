#!/usr/bin/env python3
"""Tag-loss report from tests/sql/fn_snapshot.sh outputs: python3 tools/tag_loss.py <dir> 103 104 105 ...
For every stage: functions whose body changed, bosNN tags LOST / added; then functions touched by more than one stage and the net result vs the first stage."""
import sys
d, stages = sys.argv[1], sys.argv[2:]
S = {}
for s in stages:
    S[s] = {}
    for l in open(f"{d}/s{s}.tsv"):
        f, h, t = l.rstrip("\n").split("\t")
        S[s][f] = (h, set(filter(None, t.split(","))))
touched = {}
lost_any = False
for a, b in zip(stages, stages[1:]):
    ch = [f for f in S[b] if f in S[a] and S[a][f][0] != S[b][f][0]]
    new = [f for f in S[b] if f not in S[a]]
    print(f"--- phase{b}: {len(ch)} functions changed, {len(new)} new")
    for f in ch:
        touched.setdefault(f, []).append(b)
        lost = S[a][f][1] - S[b][f][1]
        if lost: lost_any = True
        print(f"   {f}  lost={sorted(lost) or '-'} added={sorted(S[b][f][1]-S[a][f][1]) or '-'}")
    for f in new: touched.setdefault(f, []).append(b + "(new)")
print("\n=== functions touched by more than one stage ===")
for f, st in sorted(touched.items()):
    if len(st) > 1:
        print(f"   {f}: {st}  tags {sorted(S[stages[0]].get(f, (0, set()))[1])} -> {sorted(S[stages[-1]][f][1])}")
print("\n=== net lost tags, first stage -> last stage ===")
n = 0
for f in S[stages[0]]:
    if f in S[stages[-1]]:
        l = S[stages[0]][f][1] - S[stages[-1]][f][1]
        if l: print("   ", f, sorted(l)); n += 1
    else: print("    DROPPED", f); n += 1
print("NET LOST TAGS:", n, "| per-step losses seen:", lost_any)
sys.exit(1 if n else 0)
