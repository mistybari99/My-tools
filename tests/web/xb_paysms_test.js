// XB payment SMS reader: 32 sample texts (test fixtures only; invented numbers and ids, no names). Run: node tests/web/xb_paysms_test.js
// The layouts are UNVERIFIED against the owner's real messages; the test proves the reader's rules, not the bank's wording.
const assert = require('assert');
const path = require('path');
const { parseMobilePaySms } = require(path.join(__dirname, '..', '..', 'web', 'xb_paysms.js'));

const CASES = [
  // bKash receive
  { t: 'bKash: You have received Tk 500.00 from 01711000001. Fee Tk 0.00. Balance Tk 2,345.67. TrxID 8F3K2L9M1X at 17/10/2026 10:23', ok: true, provider: 'bkash', trx: '8F3K2L9M1X', amount: 500, sender: '01711000001', kind: 'in' },
  { t: 'bKash: You have received Tk 1,250 from 01711000002. Balance Tk 9,999.00. TrxID ABC123XYZ9 at 01/10/2026 18:05', ok: true, provider: 'bkash', trx: 'ABC123XYZ9', amount: 1250, sender: '01711000002' },
  { t: 'বিকাশ: আপনার বিকাশে ৳ ৭৫০.০০ জমা হয়েছে। প্রেরক: 01711000003। TrxID 7K2M9P4Q1R 17/10/2026 11:00', ok: true, provider: 'bkash', trx: '7K2M9P4Q1R', amount: 750, sender: '01711000003' },
  { t: 'Cash In Tk 300.00 from 01711000004 successful. bKash TrxID C1D2E3F4G5 at 16/10/2026 09:12', ok: true, provider: 'bkash', trx: 'C1D2E3F4G5', amount: 300, sender: '01711000004' },
  { t: 'You have received Tk 2000 from 01711000005. TrxID 9ZZ8Y7X6W5V4 at 17.10.2026 08:00 bKash', ok: true, provider: 'bkash', trx: '9ZZ8Y7X6W5V4', amount: 2000, date: '17.10.2026' },
  { t: 'Fee Tk 5.00. bKash: You have received Tk 1,000.00 from 01711000011. TrxID K9L8M7N6P5 at 17/10/2026 10:00', ok: true, provider: 'bkash', trx: 'K9L8M7N6P5', amount: 1000 },
  { t: 'Balance Tk 2,000 before. bKash: You have received Tk 300 from 01711000012. TrxID X1Y2Z3W4V5', ok: true, amount: 300, trx: 'X1Y2Z3W4V5' },
  { t: 'bkash: trxid 8f3k2l9m1x received Tk 45.50 from 01711000013', ok: true, trx: '8F3K2L9M1X', amount: 45.5 },
  { t: 'You have received Tk 500.00 from a friend. bKash TrxID ABCDE12345', ok: true, trx: 'ABCDE12345', amount: 500, sender: null },
  { t: 'বিকাশ: ৳ ৫০০.০০ পেয়েছেন। প্রেরক 01711000024 TrxID 9H8G7F6E5D 18.10.2026 09:01', ok: true, trx: '9H8G7F6E5D', amount: 500, sender: '01711000024' },
  // bKash outgoing, promo, incomplete: never a receipt
  { t: 'You have sent Tk 500.00 to 01711000006. bKash TrxID 1A2B3C4D5E at 17/10/2026 10:23', ok: false, kind: 'out', reason: 'outgoing_money_not_a_receipt' },
  { t: 'bKash payment of Tk 800.00 to 01711000007 successful. TrxID 5Q6R7S8T9U', ok: false, kind: 'out' },
  { t: 'bKash cashback Tk 25.00 credited. TrxID 4M5N6P7Q8R', ok: false, reason: 'amount_not_found' },
  { t: 'You have received Tk 500.00 from 01711000009. bKash Balance Tk 100.00.', ok: false, reason: 'trx_id_not_found' },
  { t: 'bKash: You have received Tk 50 from 01711000010. TrxID AB12', ok: false, reason: 'trx_id_not_found' },
  { t: 'bKash: your OTP is 123456. Do not share it with anyone.', ok: false, reason: 'amount_not_found' },
  { t: 'bKash: You have received Tk 100 from 01711000030. TrxID 3C4D5E6F7G. You have received Tk 9.00 from 01711000031. TrxID 2B3C4D5E6F', ok: false, reason: 'several_messages_pasted' },
  { t: 'Congrats! You won Tk 50000. Claim at the link. TrxID Q1W2E3R4T5', ok: false, reason: 'provider_not_recognised' },
  // Nagad
  { t: 'Money Received. Amount: Tk 1,500.00 Sender: 01711000013 TrxID: NG7H8J9K0L Date: 17/10/2026 12:30 Nagad', ok: true, provider: 'nagad', trx: 'NG7H8J9K0L', amount: 1500, sender: '01711000013' },
  { t: 'Nagad: You received Tk 800 from 01711000014. TxnID: NG1A2B3C4D', ok: true, provider: 'nagad', trx: 'NG1A2B3C4D', amount: 800, sender: '01711000014' },
  { t: 'Nagad: Cash In successful. Amount Tk 400.00 from 01711000015. TrxID NG5K6L7M8N', ok: true, provider: 'nagad', trx: 'NG5K6L7M8N', amount: 400 },
  { t: 'Nagad payment received Tk 2,500 from 01711000016. Balance Tk 3,000. TrxID 0P9O8I7U6Y', ok: true, provider: 'nagad', trx: '0P9O8I7U6Y', amount: 2500 },
  { t: 'নগদ: ৳ ১,২০০.০০ জমা হয়েছে। প্রেরক 01711000017। TrxID NG3R4T5Y6U', ok: true, provider: 'nagad', trx: 'NG3R4T5Y6U', amount: 1200, sender: '01711000017' },
  { t: 'Nagad: You sent Tk 300 to 01711000018. TrxID NG9Z8X7C6V', ok: false, kind: 'out' },
  { t: 'Nagad: Refund Tk 150 credited. TrxID NG4B5N6M7L', ok: false, reason: 'direction_unknown' },
  { t: 'Nagad receive Tk 90 from 01711000019 TrxID NG2X3C4V5B on 17/10/2026', ok: true, provider: 'nagad', trx: 'NG2X3C4V5B', amount: 90 },
  // Rocket
  { t: 'Rocket: Tk 600.00 received from 01711000019. TrxID RK1A2B3C4D at 17/10/2026 14:05', ok: true, provider: 'rocket', trx: 'RK1A2B3C4D', amount: 600, sender: '01711000019' },
  { t: 'Rocket: Tk 1,000 received from 01711000020. Balance Tk 5,000. TrxID RK5T6Y7U8I', ok: true, provider: 'rocket', trx: 'RK5T6Y7U8I', amount: 1000 },
  { t: 'Rocket: Payment of Tk 250.00 to 01711000021 done. TrxID RK0O9I8U7Y', ok: false, kind: 'out' },
  // edge
  { t: '', ok: false, reason: 'empty' },
  { t: '   ', ok: false, reason: 'empty' },
  { t: 'Rocket: received Tk 10 from 01711000022. TrxID RK9999', ok: true, provider: 'rocket', trx: 'RK9999', amount: 10 },
];

let pass = 0, fail = 0;
CASES.forEach((c, i) => {
  const r = parseMobilePaySms(c.t);
  try {
    assert.strictEqual(r.ok, c.ok, 'ok');
    if (c.provider !== undefined) assert.strictEqual(r.provider, c.provider, 'provider');
    if (c.trx !== undefined) assert.strictEqual(r.trx, c.trx, 'trx');
    if (c.amount !== undefined) assert.strictEqual(r.amount, c.amount, 'amount');
    if (c.sender !== undefined) assert.strictEqual(r.sender, c.sender, 'sender');
    if (c.kind !== undefined) assert.strictEqual(r.kind, c.kind, 'kind');
    if (c.date !== undefined) assert.strictEqual(r.date, c.date, 'date');
    if (c.reason !== undefined) assert.ok(r.reasons.includes(c.reason), 'reason ' + c.reason + ' in ' + JSON.stringify(r.reasons));
    pass++;
  } catch (e) {
    fail++;
    console.log('FAIL #' + (i + 1) + ': ' + e.message + ' | ' + JSON.stringify(r) + ' | ' + c.t);
  }
});
// the reader is deterministic: the same text always gives the same answer (a re-paste never gives a new Trx)
const again = parseMobilePaySms(CASES[0].t);
assert.deepStrictEqual(again, parseMobilePaySms(CASES[0].t));
console.log('XB SMS reader: ' + pass + ' pass, ' + fail + ' fail (' + CASES.length + ' samples)');
if (fail) process.exit(1);
