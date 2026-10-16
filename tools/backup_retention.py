#!/usr/bin/env python3
"""Retention of the dated backup folders (item U-12). Python 3 standard library only. DRY RUN unless --apply.

The nightly workflow keeps  latest/  (newest) and one folder per day  YYYY/MM/DD/  on the private `backups` branch. The owner states a retention period (setting
backup_retention_days; blank = keep everything, today's behaviour). This tool lists, and only with --apply removes, dated folders older than that many days.

Rules it never breaks:
  * no --days (blank setting) = nothing is removed, it says so;
  * `latest/` and every folder that is not exactly YYYY/MM/DD (photos, README, anything else) are never touched;
  * the newest dated folder is never removed, whatever its age (so a stalled backup can never leave you with none);
  * only whole dated folders are removed, nothing else.
IMPORTANT: git keeps old files in its history. Removing a folder from the branch tip frees nothing in .git and does not make the data unreadable to someone who has the
repository. For that, the backups branch history must be rewritten or the branch recreated: an owner-approved step (docs/HISTORY_CLEANUP_RUNBOOK.md), never automatic.

Usage:  python3 tools/backup_retention.py --root <checkout of the backups branch, folder that holds latest/ and YYYY/> --days N [--apply] [--today YYYY-MM-DD]
Exit code: 0 = done or nothing to do, 2 = refused / could not run.
"""
import argparse
import datetime
import os
import re
import shutil
import sys

DHAKA = datetime.timezone(datetime.timedelta(hours=6))


def dated_folders(root):
    """[(date, path)] for root/YYYY/MM/DD folders, oldest first. Anything else is ignored."""
    out = []
    try:
        years = sorted(os.listdir(root))
    except OSError as e:
        raise SystemExit(f'cannot read {root}: {type(e).__name__}')
    for y in years:
        if not re.fullmatch(r'\d{4}', y) or not os.path.isdir(os.path.join(root, y)):
            continue
        for m in sorted(os.listdir(os.path.join(root, y))):
            if not re.fullmatch(r'\d{2}', m) or not os.path.isdir(os.path.join(root, y, m)):
                continue
            for d in sorted(os.listdir(os.path.join(root, y, m))):
                p = os.path.join(root, y, m, d)
                if not re.fullmatch(r'\d{2}', d) or not os.path.isdir(p):
                    continue
                try:
                    out.append((datetime.date(int(y), int(m), int(d)), p))
                except ValueError:
                    continue
    return sorted(out)


def plan(root, days, today):
    """Returns (to_remove, kept_newest). days None = nothing."""
    folders = dated_folders(root)
    if days is None or not folders:
        return [], (folders[-1] if folders else None)
    cutoff = today - datetime.timedelta(days=days)
    newest = folders[-1]
    return [(d, p) for d, p in folders if d < cutoff and (d, p) != newest], newest


def main(argv=None, out=print):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--root', required=True)
    ap.add_argument('--days', type=int, default=None, help='keep folders newer than this many days (the owner states it; blank = keep everything)')
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--today', help='YYYY-MM-DD (for tests); default: today in Asia/Dhaka')
    a = ap.parse_args(argv)
    if a.days is None:
        out('retention period not stated (backup_retention_days is blank): nothing removed')
        return 0
    if a.days < 1 or a.days > 36500:
        print('refused: --days must be between 1 and 36500', file=sys.stderr)
        return 2
    if not os.path.isdir(a.root):
        print('refused: --root is not a folder', file=sys.stderr)
        return 2
    today = datetime.date.fromisoformat(a.today) if a.today else datetime.datetime.now(DHAKA).date()
    rm, newest = plan(a.root, a.days, today)
    if not rm:
        out(f'nothing older than {a.days} days (newest dated folder: {newest[0] if newest else "none"})')
        return 0
    for d, p in rm:
        out(('removing ' if a.apply else 'would remove ') + os.path.relpath(p, a.root) + f' ({d})')
        if a.apply:
            shutil.rmtree(p)
    if a.apply:
        for mp in sorted({os.path.dirname(p) for _, p in rm}):      # tidy only the month / year folders that this run emptied
            if os.path.isdir(mp) and not os.listdir(mp):
                os.rmdir(mp)
        for yp in sorted({os.path.dirname(os.path.dirname(p)) for _, p in rm}):
            if os.path.isdir(yp) and not os.listdir(yp):
                os.rmdir(yp)
    else:
        out('DRY RUN: add --apply to remove them. Git history still keeps the old files (see docs/integration/W1-G.md).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
