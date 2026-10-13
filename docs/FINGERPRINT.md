# Fingerprint attendance machines - how they connect to Islamia BOS

The machine never talks to the database itself. Punches reach BOS in one of two ways:

1. **Bridge (automatic)** - a small program, `tools/fingerprint_bridge.py`, runs on a PC or a Raspberry Pi in the same shop network.
   Every few minutes it reads the new punches from the machine and sends them to BOS.
2. **File (by hand)** - export the punches to a USB stick on the machine, then in the app open
   **Attendance > Device file**, choose the file, press **Preview** (nothing is saved), check the numbers, press **Import**.
   A wrong import can be undone (it is marked void, never deleted).

Either way the same punch is never stored twice, punches of unknown machine ids wait in the **Unknown device ids** list until
you link them to a person, and the day's attendance (in, out, late, overtime) is worked out from the first and last punch.

## Supported machines

| Brand / kind | Bridge (LAN) | File import |
|---|---|---|
| ZKTeco (K40, K50, MB20, MB360, SpeedFace, F18, iClock, uFace ...) that speak the ZK protocol on port 4370 | yes, with the free `pyzk` package | yes: USB `attlog.dat` / `*_attlog.dat` / `.txt` |
| Hikvision (DS-K1T...) | no (use file) | yes: export the event list as CSV from iVMS-4200 or the device web page |
| Suprema (BioStation / BioEntry) | no (use file) | yes: CSV from BioStar |
| Any other machine | no | yes, if it can save a CSV with a user id and a date-time column (the app lets you pick the columns) |

The machine's clock must be set to **Bangladesh time**. Times without a zone are read as Asia/Dhaka.

## Getting the export file

* **ZKTeco**: Menu > USB Manager (or "Pen Drive Mng.") > Download > Attendance data. The stick gets `attlog.dat`
  (lines like `   12	2026-10-01 08:58:12	1	0	1	0` = user id, date time, verify mode, in/out state, work code).
* **Hikvision**: iVMS-4200 > Access Control > Search events > Export (CSV), or the device web page > Event > Export.
* **Suprema**: BioStar > Monitoring > Event log > filter "authentication success" > CSV.
* Generic CSV: one row per punch with a header; the import screen finds columns named `user_id / ID / AC-No.` and
  `ts / datetime / Time` (or separate `Date` and `Time`) and lets you change the choice.

## Setting up the bridge

1. In the app (owner): **Attendance > Devices > Register device** - give a name, brand and serial. The app shows a **secret token once**.
   Copy it (only its hash is stored; if it is lost, press **New token** and the old one stops working).
2. On the PC / Raspberry Pi install Python 3.8+ and, for ZKTeco over the network, `pip install pyzk`.
3. Copy `tools/fingerprint_bridge.py` to it and set three values (not in the file - in the environment):
   * `SUPABASE_URL` - the project URL (`https://xxxx.supabase.co`)
   * `SUPABASE_ANON_KEY` - the public anon key (the same one the web app uses)
   * `DEVICE_TOKEN` - the token from step 1
4. Try it without sending anything:
   ```
   python3 fingerprint_bridge.py --zk 192.168.1.201 --dry-run
   python3 fingerprint_bridge.py --file attlog.dat --dry-run
   ```
   It prints how many punches it read and would send.
5. Run it for real: `python3 fingerprint_bridge.py --zk 192.168.1.201` (or `--file`). It answers with a JSON line
   (`sent`, `new`, `duplicates`, `rejected`, `unmapped`).

### Run it on a schedule

* **Raspberry Pi / Linux (cron, every 5 minutes)** - `crontab -e` and add
  ```
  */5 * * * * SUPABASE_URL=https://xxxx.supabase.co SUPABASE_ANON_KEY=eyJ... DEVICE_TOKEN=abcd... /usr/bin/python3 /home/pi/fingerprint_bridge.py --zk 192.168.1.201 >> /home/pi/bridge.log 2>&1
  ```
  or keep it running: `python3 fingerprint_bridge.py --zk 192.168.1.201 --loop 300` under systemd.
* **Windows PC (Task Scheduler)** - make `bridge.bat`:
  ```
  set SUPABASE_URL=https://xxxx.supabase.co
  set SUPABASE_ANON_KEY=eyJ...
  set DEVICE_TOKEN=abcd...
  py C:\bos\fingerprint_bridge.py --zk 192.168.1.201 >> C:\bos\bridge.log 2>&1
  ```
  Task Scheduler > Create task > Trigger "Daily, repeat every 5 minutes" > Action "Start a program: C:\bos\bridge.bat".
  Tick "Run whether user is logged on or not".

### What the bridge does

* Reads all punches (ZK over LAN with `pyzk`, or a file), removes exact repeats, sorts by time.
* Keeps a **checkpoint file** (default `~/.bos_fingerprint_checkpoint.json`, change with `--checkpoint`) with the latest time
  already accepted by the server, so the next run sends only newer punches. The checkpoint is written only after the server says yes.
* Sends batches of at most 500 rows to the RPC `attendance_punch_push` (headers `apikey` + `Authorization: Bearer <anon key>`).
* Retries network errors and server errors with a growing wait (`--retries`, `--backoff`); waits a minute if the server says
  `rate_limited`; stops at once (exit code 2) on `bad_token`.
* `--dry-run` reads and counts only: nothing is sent and the checkpoint is not touched.
* Even if the checkpoint is deleted, sending the same punches again stores nothing new (the database ignores duplicates).

Tests: `python3 tools/test_fingerprint_bridge.py` (a fake local server; no network needed).

## Security notes

* The anon key can call **only** `attendance_punch_push`. That function checks the device token (by its SHA-256 hash), accepts at
  most 500 rows per call and `att_push_per_min` calls per minute per device (Switchboard, default 30), refuses times more than
  400 days old or in the future, inserts punches for **that device's place only**, and answers with counts - it never returns
  names, employees or any other data.
* Keep the token like a password. Anyone with it can add punches for that machine (not read anything). If a PC is lost or the token
  leaks: **Attendance > Devices > ⋮ > New token** (the old token stops at once), or switch the device off.
* Punches are append-only. A wrong file import is undone by voiding its batch (kept for audit). Manual corrections are made on the
  day (Attendance > Today > ⋮ > Mark / correct) with a reason, and need approval by a second person; they are audit-logged.
* Once the owner approves a month's payroll, attendance of those people for that month is locked.
* Do not put the bridge on a PC that customers can use. Prefer a Raspberry Pi or an office PC with its own login.

## Matching machine users to employees

Each employee has a **Fingerprint device ID** (Employees > edit, field "Fingerprint device ID") - the user number enrolled on the
machine. Punches with an id nobody has yet are kept (no employee) and listed in **Attendance > Device file > Unknown device ids**;
choose the person and press **Link** - the waiting punches are attached and the days recomputed.
