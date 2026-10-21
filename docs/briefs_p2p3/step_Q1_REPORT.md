# Step Q1 — pos2_test "old queued payload sent"

**Verdict: REAL BUG = NO. Stale test expectation (since phase83). No offline sale is lost.**

## যাচাই হয়েছে
- pos2_test.js কপি করে (ROOT = এই worktree-র web/) চালানো হয়েছে: ঠিক ১টি FAIL, queue খালি হয়ে যায় ("old queued sale replayed" PASS)।
- Debug দিয়ে দেখা গেছে: পুরনো shape-এর payload (client_id aaaaaaaa-..., কোনো p_discount_kind নেই) replay-এ `record_sale_offline` কল হয়েছে, একই p_client, p_lines[0].name = "Old", সঠিক shape-এ — ঠিক একবার।
- ব্যর্থতার কারণ: test-এর mock শুধু `record_sale2` ধরে `window.__LAST` সেট করে; phase83 থেকে queue replay যায় `record_sale_offline`-এ (posfail.js sendOffline), তাই `__LAST` পুরনো মানেই থাকে।
- নতুন tests/web/pos2b_test.js (pos2 কপি, শুধু ওই assertion সংশোধিত): `__CALLS` থেকে দেখে old payload `record_sale_offline`-এ ঠিক ১ বার গেছে, এবং দ্বিতীয় flush-এ আবার যায়নি। ফল: discount asserts failed: 0, errors: none। pos.js অপরিবর্তিত, pos2_test.js অপরিবর্তিত।

## পড়ে বোঝা (চালিয়ে যাচাই হয়নি)
- pos.js `send(p, replay)`: replay হলে `B.posfail.sendOffline(clean(p))`; function না থাকলে record_sale2-তে fallback; `p_discount_kind` ছাড়া পুরনো payload সরাসরি চলে। `record_sale_offline` (phase83.sql) record_sale2-র একই আর্গুমেন্ট নেয়, নতুন দুটি param default null।
- flush: সফল হলে queue থেকে client_id ধরে সরায়; business error হলে failed card (posfail screen), network error হলে queue-তেই থাকে। client_id দিয়ে idempotency record_sale2-র দায়িত্ব (phase-এর SQL পড়ে; live DB-তে চালানো হয়নি)।
- Failed-card-এর posfail screen এই test-এ নতুন করে যাচাই করিনি (posfail_test.js-এ আছে)।

## যাচাই হয়নি
- সত্যিকারের পুরনো app version থেকে আসা browser localStorage queue, live DB, deployed web।
- posqueue_old_test.js বানানো হয়নি, কারণ bug নেই (নির্দেশ অনুযায়ী stale হলে pos2b)।

## Data-loss risk
কম/নেই: পুরনো shape-এর queued sale app update-এর পর replay হয় ও একবারই যায়; নতুন shape অপরিবর্তিত। অবশিষ্ট ঝুঁকি শুধু DB-তে phase83 না থাকলে — তখন কোড record_sale2-তে fallback করে।
