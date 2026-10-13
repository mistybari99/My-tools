#!/usr/bin/env python3
"""Islamia BOS - fingerprint device bridge (module B2, supabase/phase42.sql).

Reads attendance punches from a fingerprint machine and pushes them to the BOS database in batches of at most 500 rows through the
RPC  attendance_punch_push(p_token, p_rows)  - the ONLY function the anon key may call. The device token (from the app: Attendance >
Devices > Register) identifies the machine; the server stores only its hash, maps device user ids to employees and ignores duplicates.

Sources
  --zk HOST[:PORT]     a ZKTeco machine on the LAN (needs the optional package  pyzk:  pip install pyzk)
  --file PATH          a device export: ZKTeco USB attlog (.dat / .txt, tab separated: user id, date time, verify, in/out, workcode)
                       or a CSV with a header row (user_id / ts columns; see --col-user / --col-ts)
Config (environment)   SUPABASE_URL, SUPABASE_ANON_KEY, DEVICE_TOKEN   (or --url / --key / --token)
Safety                 --dry-run (parse and count, send nothing), retries with back-off, a local checkpoint file so nothing is sent twice
                       (the server is idempotent as well: the same punch is never stored twice).

Standard library only (+ optional pyzk). Python 3.8+. Times are the machine's local clock (set it to Bangladesh time); they are sent
without a zone and the server reads them as Asia/Dhaka.
Exit codes: 0 ok, 1 network / server trouble after all retries, 2 bad token or bad configuration.
"""
import argparse
import csv
import datetime as dt
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request

BATCH_MAX = 500
TS_FORMATS = ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M:%S", "%Y/%m/%d %H:%M:%S", "%d/%m/%Y %H:%M:%S", "%d-%m-%Y %H:%M:%S", "%Y/%m/%d %H:%M", "%d/%m/%Y %H:%M")


class FatalError(Exception):
    """A problem that retrying will not fix (bad token, bad configuration)."""


def parse_ts(text):
    """Return 'YYYY-MM-DD HH:MM:SS' for a device time text, or None."""
    t = (text or "").strip()
    if not t:
        return None
    for f in TS_FORMATS:
        try:
            return dt.datetime.strptime(t, f).strftime("%Y-%m-%d %H:%M:%S")
        except ValueError:
            pass
    return None


def row(uid, ts, state=None, verify=None, workcode=None):
    r = {"user_id": str(uid).strip(), "ts": ts}
    if state not in (None, ""):
        r["dir"] = str(state).strip()
    if verify not in (None, ""):
        r["verify"] = str(verify).strip()
    if workcode not in (None, ""):
        r["workcode"] = str(workcode).strip()
    return r


def parse_attlog(text):
    """ZKTeco attlog: '<uid>\\t<YYYY-MM-DD HH:MM:SS>\\t<verify>\\t<state>\\t<workcode>...' (spaces between date and time are kept)."""
    out, bad = [], 0
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = [p for p in line.split("\t")] if "\t" in line else line.split()
        if "\t" not in line and len(parts) >= 3:          # space separated: uid date time ...
            parts = [parts[0], parts[1] + " " + parts[2]] + parts[3:]
        parts = [p.strip() for p in parts]
        if len(parts) < 2:
            bad += 1
            continue
        ts = parse_ts(parts[1])
        if not parts[0] or ts is None:
            bad += 1
            continue
        out.append(row(parts[0], ts, parts[3] if len(parts) > 3 else None, parts[2] if len(parts) > 2 else None, parts[4] if len(parts) > 4 else None))
    return out, bad


def parse_csv(text, col_user=None, col_ts=None, col_dir=None, col_date=None, col_time=None):
    """CSV with a header. Columns are found by name (user_id / uid / ac-no / id; ts / datetime / time; dir / state / status) unless given."""
    rd = csv.DictReader(io.StringIO(text))
    heads = {h.strip().lower(): h for h in (rd.fieldnames or [])}

    def pick(given, names):
        if given:
            return heads.get(given.strip().lower(), given)
        for n in names:
            if n in heads:
                return heads[n]
        return None
    cu = pick(col_user, ["user_id", "uid", "userid", "user id", "ac-no.", "ac-no", "enroll id", "id", "pin", "employee id"])
    ct = pick(col_ts, ["ts", "datetime", "date time", "date/time", "time", "punch time", "checktime"])
    cd = pick(col_dir, ["dir", "direction", "state", "status", "in/out", "checktype"])
    if not col_ts and "date" in heads and ct == heads.get("time"):      # separate Date and Time columns
        ct = None
    cdate, ctime = (pick(col_date, ["date"]) if col_date or not ct else None), (pick(col_time, ["time"]) if col_time or not ct else None)
    if not cu or not (ct or (cdate and ctime)):
        raise FatalError("csv: cannot find the user id / time columns (use --col-user / --col-ts)")
    out, bad = [], 0
    for r in rd:
        uid = (r.get(cu) or "").strip()
        ts = parse_ts(r.get(ct)) if ct else parse_ts(((r.get(cdate) or "") + " " + (r.get(ctime) or "")).strip())
        if not uid or ts is None:
            bad += 1
            continue
        out.append(row(uid, ts, r.get(cd) if cd else None))
    return out, bad


def read_file(path, **cols):
    with open(path, "r", encoding="utf-8-sig", errors="replace") as f:
        text = f.read()
    first = text.lstrip().splitlines()[0] if text.strip() else ""
    if path.lower().endswith(".csv") or ("," in first and not first[:1].isdigit()):
        return parse_csv(text, **cols)
    return parse_attlog(text)


def read_zk(host, port=4370, timeout=10, password=0):  # pragma: no cover - needs a real machine
    try:
        from zk import ZK  # optional dependency: pip install pyzk
    except ImportError:
        raise FatalError("the pyzk package is needed for --zk (pip install pyzk); or export the file and use --file")
    conn = ZK(host, port=port, timeout=timeout, password=password, force_udp=False, ommit_ping=True).connect()
    try:
        conn.disable_device()
        out = [row(a.user_id, a.timestamp.strftime("%Y-%m-%d %H:%M:%S"), getattr(a, "punch", None), getattr(a, "status", None)) for a in conn.get_attendance()]
    finally:
        try:
            conn.enable_device()
        finally:
            conn.disconnect()
    return out, 0


def key(r):
    return r["user_id"] + "|" + r["ts"]


class Checkpoint:
    """Remembers what was sent: the latest time sent and the punch keys at that time (two punches may share a second)."""

    def __init__(self, path):
        self.path, self.last_ts, self.keys = path, "", set()
        if path and os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    d = json.load(f)
                self.last_ts, self.keys = d.get("last_ts", ""), set(d.get("keys", []))
            except (OSError, ValueError):
                pass

    def fresh(self, rows):
        return [r for r in rows if r["ts"] > self.last_ts or (r["ts"] == self.last_ts and key(r) not in self.keys)]

    def mark(self, rows):
        if not rows:
            return
        top = max(r["ts"] for r in rows)
        if top > self.last_ts:
            self.last_ts, self.keys = top, set()
        self.keys |= {key(r) for r in rows if r["ts"] == self.last_ts}
        self.save()

    def save(self):
        if not self.path:
            return
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"last_ts": self.last_ts, "keys": sorted(self.keys), "saved_at": dt.datetime.now().isoformat(timespec="seconds")}, f)
        os.replace(tmp, self.path)


def push(url, anon_key, token, rows, retries=4, backoff=2.0, rate_wait=61.0, timeout=30, log=None):
    """POST one batch to the RPC. Returns the server answer (dict). Retries network errors, 5xx, 429 and rate_limited."""
    body = json.dumps({"p_token": token, "p_rows": rows}).encode("utf-8")
    endpoint = url.rstrip("/") + "/rest/v1/rpc/attendance_punch_push"
    headers = {"apikey": anon_key, "Authorization": "Bearer " + anon_key, "Content-Type": "application/json", "Accept": "application/json"}
    attempt = 0
    while True:
        attempt += 1
        try:
            req = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8") or "{}")
        except urllib.error.HTTPError as e:
            text = e.read().decode("utf-8", "replace")
            if "bad_token" in text:
                raise FatalError("the device token was refused (bad_token): register the device again or reset its token")
            if "too_many_rows" in text:
                raise FatalError("the server refused the batch size")
            wait = rate_wait if ("rate_limited" in text or e.code == 429) else backoff * (2 ** (attempt - 1))
            retry = e.code >= 500 or e.code == 429 or "rate_limited" in text
            if not retry or attempt > retries:
                raise RuntimeError("server error %s: %s" % (e.code, text[:300]))
        except (urllib.error.URLError, OSError, ValueError) as e:
            if attempt > retries:
                raise RuntimeError("network error: %s" % e)
            wait = backoff * (2 ** (attempt - 1))
        if log:
            log("retry %d in %.1fs" % (attempt, wait))
        time.sleep(wait)


def run(args, env=None, log=print):
    env = os.environ if env is None else env
    url, anon_key, token = args.url or env.get("SUPABASE_URL"), args.key or env.get("SUPABASE_ANON_KEY"), args.token or env.get("DEVICE_TOKEN")
    if args.zk:
        host, _, port = args.zk.partition(":")
        rows, bad = read_zk(host, int(port or 4370))
    elif args.file:
        rows, bad = read_file(args.file, col_user=args.col_user, col_ts=args.col_ts, col_dir=args.col_dir)
    else:
        raise FatalError("give --zk HOST or --file PATH")
    seen, uniq = set(), []
    for r in sorted(rows, key=lambda x: (x["ts"], x["user_id"])):
        if key(r) not in seen:
            seen.add(key(r))
            uniq.append(r)
    cp = Checkpoint(args.checkpoint)
    if args.dry_run:
        cp.path = None                         # read it to report, never write in a dry run
    todo = cp.fresh(uniq)
    summary = {"read": len(rows), "unreadable": bad, "unique": len(uniq), "to_send": len(todo), "batches": (len(todo) + args.batch - 1) // args.batch,
               "from": todo[0]["ts"] if todo else None, "to": todo[-1]["ts"] if todo else None, "dry_run": bool(args.dry_run), "sent": 0, "new": 0, "duplicates": 0, "rejected": 0, "unmapped": 0}
    if args.dry_run:
        summary["users"] = len({r["user_id"] for r in todo})
        return summary
    if not (url and anon_key and token):
        raise FatalError("set SUPABASE_URL, SUPABASE_ANON_KEY and DEVICE_TOKEN (or --url / --key / --token)")
    for i in range(0, len(todo), args.batch):
        part = todo[i:i + args.batch]
        ans = push(url, anon_key, token, part, retries=args.retries, backoff=args.backoff, rate_wait=args.rate_wait, log=log)
        cp.mark(part)                     # only after the server said yes
        summary["sent"] += len(part)
        for k in ("new", "duplicates", "rejected", "unmapped"):
            summary[k] += int(ans.get(k) or 0)
    return summary


def build_parser():
    p = argparse.ArgumentParser(description="Push fingerprint punches to Islamia BOS (attendance_punch_push).")
    src = p.add_mutually_exclusive_group()
    src.add_argument("--zk", help="ZKTeco machine HOST[:PORT] on the LAN (needs pyzk)")
    src.add_argument("--file", help="device export file (.dat / .txt attlog or .csv)")
    p.add_argument("--url"), p.add_argument("--key"), p.add_argument("--token")
    p.add_argument("--checkpoint", default=os.path.join(os.path.expanduser("~"), ".bos_fingerprint_checkpoint.json"))
    p.add_argument("--dry-run", action="store_true", help="read and count only, send nothing")
    p.add_argument("--batch", type=int, default=BATCH_MAX)
    p.add_argument("--retries", type=int, default=4)
    p.add_argument("--backoff", type=float, default=2.0)
    p.add_argument("--rate-wait", type=float, default=61.0)
    p.add_argument("--loop", type=int, default=0, help="repeat every N seconds (0 = once)")
    p.add_argument("--col-user"), p.add_argument("--col-ts"), p.add_argument("--col-dir")
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    args.batch = max(1, min(args.batch, BATCH_MAX))
    while True:
        try:
            print(json.dumps(run(args), ensure_ascii=False))
        except FatalError as e:
            print("STOP: %s" % e, file=sys.stderr)
            return 2
        except RuntimeError as e:
            print("ERROR: %s" % e, file=sys.stderr)
            if not args.loop:
                return 1
        if not args.loop:
            return 0
        time.sleep(args.loop)


if __name__ == "__main__":
    sys.exit(main())
