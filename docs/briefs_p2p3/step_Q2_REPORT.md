# Step Q2 (bos106) - optviews_ui_test failures

Verdict: product bug = NO. It is a test-harness problem. No product file (web/) was changed.

## Cause
tests/web/s10_common.js (used through w5_common.js) hard-codes ROOT = '/home/user/My-tools/web'. serve() therefore serves that other tree, not the worktree under test. That tree has no working optviews hook, so the drawer was never filtered or locked: 5 asserts failed and the sheet click crashed (CRASH, timeout waiting for .sheet). The port was a fixed 8473 (clash risk).

## Fix
New tests/web/optviews_ui2_test.js (corrected copy; the old file is untouched): serves this worktree's web/ (path from __dirname), uses a random free port, SP defaults to its own dir. Added asserts: r:home and r:optviews can never be hidden; the drawer still renders with Hide+Locked data.

## যাচাই হয়েছে
- node tests/web/optviews_ui2_test.js on wt-q2: errors none, assert failures 0.
- Hide removes the entry from drawer and search; Locked row is tagged, opens the ask-owner sheet and the page does not open; no data / server error -> drawer unchanged; my_option_views read once; owner screen has no Bangla letters in English mode.
- r:home / r:optviews are never hidden (hidden() false).
- node --check OK; no conflict markers.

## পড়ে বোঝা
- The 3 hook lines (ia.js visible(), nav.js entries(), nav.js load) are intact after navfold; no edit needed.
- nav_test, favsync_test, settings2_test also reference /home/user/My-tools (same class of harness risk); nav2, control, ia, navfold, optviews tests do not. Since no product code changed, their results are unchanged by construction.

## যাচাই হয়নি
- The navfold collapsed footer was only checked as "drawer renders with views data", not its fold interaction.
- The other 8 suites were not run to completion (nav, nav2, control, favsync passed in a partial run, which used the My-tools tree where hard-coded; ia/settings2/navfold/optviews not confirmed).
