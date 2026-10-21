#!/usr/bin/env python3
"""Unit tests for tools/fingerprint_bridge.py against a tiny local fake of the Supabase RPC.
Run:  python3 -m unittest tools/test_fingerprint_bridge.py   (from the repo root)   or   python3 tools/test_fingerprint_bridge.py
"""
import json
import os
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fingerprint_bridge as fb  # noqa: E402

TOKEN = "t" * 64


class Fake(BaseHTTPRequestHandler):
    """Mimics /rest/v1/rpc/attendance_punch_push: checks the token, refuses > 500 rows, de-duplicates like the database."""
    store = set()
    calls = []
    script = []          # queue of forced answers: (status, body) used before the normal logic

    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n).decode("utf-8"))
        Fake.calls.append({"path": self.path, "apikey": self.headers.get("apikey"), "auth": self.headers.get("Authorization"), "body": body})
        if Fake.script:
            code, ans = Fake.script.pop(0)
            return self.reply(code, ans)
        if self.path != "/rest/v1/rpc/attendance_punch_push":
            return self.reply(404, {"message": "not found"})
        if body.get("p_token") != TOKEN:
            return self.reply(400, {"code": "P0001", "message": "bad_token"})
        rows = body.get("p_rows") or []
        if len(rows) > 500:
            return self.reply(400, {"code": "P0001", "message": "too_many_rows"})
        new = 0
        for r in rows:
            k = (r["user_id"], r["ts"])
            if k not in Fake.store:
                Fake.store.add(k)
                new += 1
        self.reply(200, {"ok": True, "received": len(rows), "new": new, "duplicates": len(rows) - new, "rejected": 0, "unmapped": 0})

    def reply(self, code, obj):
        b = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)


class BridgeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = HTTPServer(("127.0.0.1", 0), Fake)
        cls.url = "http://127.0.0.1:%d" % cls.srv.server_address[1]
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()

    def setUp(self):
        Fake.store, Fake.calls, Fake.script = set(), [], []
        self.tmp = tempfile.mkdtemp()
        self.cp = os.path.join(self.tmp, "cp.json")

    def write(self, name, text):
        p = os.path.join(self.tmp, name)
        with open(p, "w", encoding="utf-8") as f:
            f.write(text)
        return p

    def args(self, *extra):
        return fb.build_parser().parse_args(["--url", self.url, "--key", "anon-key", "--token", TOKEN, "--checkpoint", self.cp, "--backoff", "0.01", "--rate-wait", "0.01"] + list(extra))

    def attlog(self, n=3, day="2026-09-01"):
        return "".join("%5d\t%s %02d:%02d:00\t1\t%d\t0\t0\n" % (100 + i % 7, day, 8 + (i // 60) % 12, i % 60, i % 2) for i in range(n))

    # ---------- parsing ----------
    def test_parse_attlog_tab_and_space(self):
        rows, bad = fb.parse_attlog("    1\t2026-09-01 08:58:12\t1\t0\t0\t0\n  2  2026-09-01 18:01:00  1  1\nbroken line\n\n")
        self.assertEqual(bad, 1)
        self.assertEqual(rows[0], {"user_id": "1", "ts": "2026-09-01 08:58:12", "dir": "0", "verify": "1", "workcode": "0"})
        self.assertEqual(rows[1]["user_id"], "2")
        self.assertEqual(rows[1]["ts"], "2026-09-01 18:01:00")
        self.assertEqual(rows[1]["dir"], "1")

    def test_parse_csv_with_header_and_custom_columns(self):
        rows, bad = fb.parse_csv("AC-No.,Name,Time,State\n101,TestF,01/09/2026 08:55:00,C/In\n102,TestK,bad,C/Out\n")
        self.assertEqual((len(rows), bad), (1, 1))
        self.assertEqual(rows[0], {"user_id": "101", "ts": "2026-09-01 08:55:00", "dir": "C/In"})
        rows, bad = fb.parse_csv("code,when\n7,2026-09-02 09:00\n", col_user="code", col_ts="when")
        self.assertEqual(rows, [{"user_id": "7", "ts": "2026-09-02 09:00:00"}])
        with self.assertRaises(fb.FatalError):
            fb.parse_csv("a,b\n1,2\n")

    def test_separate_date_and_time_columns(self):
        rows, _ = fb.parse_csv("user_id,date,time\n5,2026-09-03,07:30:00\n")
        self.assertEqual(rows, [{"user_id": "5", "ts": "2026-09-03 07:30:00"}])

    # ---------- dry run ----------
    def test_dry_run_sends_nothing_and_writes_no_checkpoint(self):
        p = self.write("attlog.dat", self.attlog(5) + "    1\t2026-09-01 08:00:00\t1\t0\t0\n" * 2)
        s = fb.run(self.args("--file", p, "--dry-run"), env={}, log=lambda *_: None)
        self.assertTrue(s["dry_run"])
        self.assertEqual((s["read"], s["unique"], s["to_send"], s["batches"]), (7, 6, 6, 1))
        self.assertEqual(Fake.calls, [])
        self.assertFalse(os.path.exists(self.cp))

    # ---------- push, batches, headers ----------
    def test_push_in_batches_of_500_with_headers(self):
        p = self.write("attlog.dat", self.attlog(1200))
        s = fb.run(self.args("--file", p), env={}, log=lambda *_: None)
        self.assertEqual(len(Fake.calls), 3)
        self.assertEqual([len(c["body"]["p_rows"]) for c in Fake.calls], [500, 500, 200])
        c = Fake.calls[0]
        self.assertEqual(c["path"], "/rest/v1/rpc/attendance_punch_push")
        self.assertEqual((c["apikey"], c["auth"], c["body"]["p_token"]), ("anon-key", "Bearer anon-key", TOKEN))
        self.assertEqual((s["sent"], s["new"], s["duplicates"]), (1200, 1200, 0))
        self.assertTrue(os.path.exists(self.cp))

    def test_checkpoint_means_nothing_is_sent_twice(self):
        p = self.write("attlog.dat", self.attlog(10))
        fb.run(self.args("--file", p), env={}, log=lambda *_: None)
        self.assertEqual(len(Fake.calls), 1)
        s = fb.run(self.args("--file", p), env={}, log=lambda *_: None)
        self.assertEqual((s["to_send"], s["sent"]), (0, 0))
        self.assertEqual(len(Fake.calls), 1)          # no second request
        # a newer punch (and one in the same second as the last one sent) goes on the next run
        last = sorted(fb.parse_attlog(self.attlog(10))[0], key=lambda r: r["ts"])[-1]["ts"]
        p2 = self.write("attlog2.dat", self.attlog(10) + "  999\t%s\t1\t0\t0\n  100\t2026-09-02 08:00:00\t1\t0\t0\n" % last)
        s = fb.run(self.args("--file", p2), env={}, log=lambda *_: None)
        self.assertEqual((s["to_send"], s["new"]), (2, 2))

    def test_env_config(self):
        p = self.write("a.dat", self.attlog(2))
        args = fb.build_parser().parse_args(["--file", p, "--checkpoint", self.cp])
        s = fb.run(args, env={"SUPABASE_URL": self.url, "SUPABASE_ANON_KEY": "k2", "DEVICE_TOKEN": TOKEN}, log=lambda *_: None)
        self.assertEqual(s["new"], 2)
        self.assertEqual(Fake.calls[0]["apikey"], "k2")
        with self.assertRaises(fb.FatalError):
            fb.run(fb.build_parser().parse_args(["--file", p, "--checkpoint", os.path.join(self.tmp, "x.json")]), env={}, log=lambda *_: None)

    # ---------- failures ----------
    def test_retry_on_server_error_then_success(self):
        Fake.script = [(500, {"message": "boom"}), (503, {"message": "busy"})]
        p = self.write("a.dat", self.attlog(3))
        msgs = []
        s = fb.run(self.args("--file", p), env={}, log=msgs.append)
        self.assertEqual(s["new"], 3)
        self.assertEqual(len(Fake.calls), 3)
        self.assertEqual(len(msgs), 2)

    def test_rate_limited_waits_and_retries(self):
        Fake.script = [(400, {"code": "P0001", "message": "rate_limited"})]
        p = self.write("a.dat", self.attlog(3))
        s = fb.run(self.args("--file", p), env={}, log=lambda *_: None)
        self.assertEqual((s["new"], len(Fake.calls)), (3, 2))

    def test_bad_token_stops_and_keeps_checkpoint_empty(self):
        p = self.write("a.dat", self.attlog(3))
        args = fb.build_parser().parse_args(["--url", self.url, "--key", "k", "--token", "wrong" * 8, "--checkpoint", self.cp, "--file", p])
        with self.assertRaises(fb.FatalError):
            fb.run(args, env={}, log=lambda *_: None)
        self.assertEqual(len(Fake.calls), 1)               # not retried
        self.assertFalse(os.path.exists(self.cp))
        self.assertEqual(fb.main(["--url", self.url, "--key", "k", "--token", "wrong" * 8, "--checkpoint", self.cp, "--file", p]), 2)

    def test_gives_up_after_retries_and_does_not_mark_sent(self):
        Fake.script = [(500, {})] * 10
        p = self.write("a.dat", self.attlog(3))
        with self.assertRaises(RuntimeError):
            fb.run(self.args("--file", p, "--retries", "2"), env={}, log=lambda *_: None)
        self.assertEqual(len(Fake.calls), 3)
        self.assertFalse(os.path.exists(self.cp))
        Fake.script = []

    def test_network_down(self):
        p = self.write("a.dat", self.attlog(1))
        args = fb.build_parser().parse_args(["--url", "http://127.0.0.1:9", "--key", "k", "--token", TOKEN, "--checkpoint", self.cp, "--file", p, "--retries", "1", "--backoff", "0.01"])
        with self.assertRaises(RuntimeError):
            fb.run(args, env={}, log=lambda *_: None)

    def test_batch_size_cannot_exceed_500(self):
        p = self.write("attlog.dat", self.attlog(600))
        self.assertEqual(fb.main(["--url", self.url, "--key", "k", "--token", TOKEN, "--checkpoint", self.cp, "--file", p, "--batch", "5000"]), 0)
        self.assertEqual([len(c["body"]["p_rows"]) for c in Fake.calls], [500, 100])


if __name__ == "__main__":
    unittest.main(verbosity=2)
