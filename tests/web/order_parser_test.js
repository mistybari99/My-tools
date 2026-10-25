// X3: web/order_parser.js - 66 chat messages (Bangla, English, Banglish, mixed) against a neutral test catalogue.
// Checks the draft fields: enquiry kind, mobile, items with quantity and unit, delivery day and time, address, and the flags a person must look at.
// Run: node tests/web/order_parser_test.js   (node 18+; no browser, no network)
'use strict';
const path = require('path');
const P = require(path.join(__dirname, '..', '..', 'web', 'order_parser.js'));

// neutral test catalogue: test_ ids, product names only
const CAT = [
  { id: 'test_choc', name_bn: 'চকলেট কেক', name_en: 'Chocolate cake', unit: 'kg', aliases: ['choc cake', 'chocolet cake', 'chokleto cake'] },
  { id: 'test_vanilla', name_bn: 'ভ্যানিলা কেক', name_en: 'Vanilla cake', unit: 'kg', aliases: ['vanila cake', 'vanilla'] },
  { id: 'test_rosogolla', name_bn: 'রসগোল্লা', name_en: 'Rosogolla', unit: 'kg', aliases: ['rosgolla', 'rosgulla'] },
  { id: 'test_sandesh', name_bn: 'সন্দেশ', name_en: 'Sandesh', unit: 'pc', aliases: ['shondesh', 'sondesh'] },
  { id: 'test_pastry', name_bn: 'পেস্ট্রি', name_en: 'Pastry', unit: 'pc', aliases: ['pestry', 'pasteri'] },
  { id: 'test_cookies', name_bn: 'কুকিজ', name_en: 'Cookies', unit: 'pc', aliases: ['cookie', 'biscuit'] },
  { id: 'test_bread', name_bn: 'পাউরুটি', name_en: 'Bread', unit: 'pc', aliases: ['pauruti', 'paun'] },
  { id: 'test_birthday', name_bn: 'জন্মদিনের কেক', name_en: 'Birthday cake', unit: 'kg', aliases: ['bday cake', 'birthday'] },
];
const TODAY = '2026-10-17';

// [message, expected]. expected keys (all optional): kind, phone (string or null), day (offset or null), hour, lines: [[id, qty, unit]],
// unknown (true = a line with no item), flags (must include), noFlags (must not include), name, address
const CASES = [
  ['চকলেট কেক 2 kg, কাল বিকেল 5টা, মোবাইল 01711000009', { kind: 'order', phone: '01711000009', day: 1, hour: 17, lines: [['test_choc', 2, 'kg']] }],
  ['2 kg chocolate cake, tomorrow 5pm, 01711000009, House 5 Road 3 Dhaka', { kind: 'order', phone: '01711000009', day: 1, hour: 17, lines: [['test_choc', 2, 'kg']], flags: ['address_guessed'] }],
  ['vanilla cake 1 kg please, deliver today 7 pm', { kind: 'order', day: 0, hour: 19, lines: [['test_vanilla', 1, 'kg']] }],
  ['rosogolla 500gm', { kind: 'order', lines: [['test_rosogolla', 0.5, 'kg']], flags: ['day_missing', 'phone_missing'] }],
  ['রসগোল্লা ২ কেজি কাল সকাল ১০টা', { kind: 'order', day: 1, hour: 10, lines: [['test_rosogolla', 2, 'kg']] }],
  ['দুইটি পেস্ট্রি আর তিনটি কুকিজ লাগবে', { kind: 'order', lines: [['test_pastry', 2, 'pc'], ['test_cookies', 3, 'pc']] }],
  ['2 pastry and 3 cookies please', { kind: 'order', lines: [['test_pastry', 2, 'pc'], ['test_cookies', 3, 'pc']] }],
  ['3 pastry, 2 cookies, 1 bread', { lines: [['test_pastry', 3, 'pc'], ['test_cookies', 2, 'pc'], ['test_bread', 1, 'pc']] }],
  ['ছয়টি সন্দেশ দাও', { kind: 'order', lines: [['test_sandesh', 6, 'pc']] }],
  ['ভ্যানিলা কেক আছে কি?', { kind: 'availability', lines: [['test_vanilla', 1, 'kg']] }],
  ['চকলেট কেকের দাম কত?', { kind: 'price', lines: [['test_choc', 1, 'kg']] }],
  ['Birthday cake price koto?', { kind: 'price', lines: [['test_birthday', 1, 'kg']] }],
  ['Rosogolla price?', { kind: 'price' }],
  ['বাসার কেক নষ্ট ছিল, অভিযোগ আছে', { kind: 'complaint' }],
  ['cake was rotten, very bad', { kind: 'complaint' }],
  ['কাস্টম কেক লাগবে, নাম লিখে দিন test_name_three', { kind: 'custom_cake' }],
  ['custom design birthday cake 3 kg', { kind: 'custom_cake', lines: [['test_birthday', 3, 'kg']] }],
  ['photo cake lagbe 1kg', { kind: 'custom_cake', lines: [] }],
  ['Hi', { kind: 'other', lines: [] }],
  ['Thanks!', { kind: 'other', lines: [] }],
  ['ধন্যবাদ, আগামীকাল দেখা হবে', { kind: 'other', day: 1 }],
  ['Name: test_name_one\nPhone: 01711000009\nAddress: Gulshan 2 road 4\n2 kg chocolate cake\nTomorrow 4 pm', { kind: 'order', name: 'test_name_one', phone: '01711000009', address: 'Gulshan 2 road 4', day: 1, hour: 16, lines: [['test_choc', 2, 'kg']], noFlags: ['address_guessed'] }],
  ['নাম: test_name_bn\nমোবাইল: ০১৭১১০০০০০৯\nঠিকানা: ধানমন্ডি ৭, রোড ৮\nরসগোল্লা ১ কেজি', { kind: 'order', name: 'test_name_bn', phone: '01711000009', lines: [['test_rosogolla', 1, 'kg']], noFlags: ['address_missing'] }],
  ['+8801711000009 chocolate cake 1kg', { kind: 'order', phone: '01711000009', lines: [['test_choc', 1, 'kg']] }],
  ['8801711000009', { kind: 'other', phone: '01711000009', lines: [] }],
  ['01911-123456 order', { kind: 'order', phone: '01911123456' }],
  ['01211234567 chocolate cake', { phone: null, flags: ['phone_missing'] }],
  ['12345', { kind: 'other', phone: null, lines: [] }],
  ['ভ্যানিলা কেক ২ টা', { lines: [['test_vanilla', 2, 'pc']] }],
  ['2 bread', { lines: [['test_bread', 2, 'pc']], flags: ['day_missing'] }],
  ['বিকেল ৫টায় পাউরুটি দরকার', { kind: 'order', hour: 17, lines: [['test_bread', 1, 'pc']] }],
  ['sandesh 10 pcs, delivery 9 am', { kind: 'order', hour: 9, lines: [['test_sandesh', 10, 'pc']] }],
  ['sondesh 1 dozen', { lines: [['test_sandesh', 1, 'dozen']] }],
  ['pastry 1 box', { lines: [['test_pastry', 1, 'box']] }],
  ['cookies 2', { lines: [['test_cookies', 2, 'pc']], flags: ['unit_unclear'] }],
  ['দুটো রসগোল্লা কাল', { day: 1, lines: [['test_rosogolla', 2, 'kg']], flags: ['unit_unclear'] }],
  ['birthday cake', { lines: [['test_birthday', 1, 'kg']], flags: ['qty_missing'] }],
  ['birthday cake 2kg, age 5 likhben', { lines: [['test_birthday', 2, 'kg']], unknown: true }],
  ['chocolate cake 3 kg, mango cake 1 kg', { lines: [['test_choc', 3, 'kg']], unknown: true }],
  ['মোবাইল ০১৮১২৩৪৫৬৭৮ অর্ডার করতে চাই', { kind: 'order', phone: '01812345678' }],
  ['ঢাকা মিরপুর ১০, বাসা ২৩', { lines: [], flags: ['address_guessed'], noFlags: ['unknown_item'] }],
  ['Road 5, House 12, Dhaka', { flags: ['address_guessed'], lines: [] }],
  ['address: House 7 road 9 mohammadpur dhaka', { address: 'House 7 road 9 mohammadpur dhaka', noFlags: ['address_guessed', 'address_missing'] }],
  ['আজ সন্ধ্যা ৭টায় 2 kg chocolate cake', { day: 0, hour: 19, lines: [['test_choc', 2, 'kg']] }],
  ['parshu 5 kg birthday cake', { day: 2, lines: [['test_birthday', 5, 'kg']] }],
  ['today chocolate cake 1 kg', { day: 0, lines: [['test_choc', 1, 'kg']] }],
  ['কাল বেলা ১২টা', { day: 1, hour: 12 }],
  ['কাল ৩টায়', { day: 1, hour: 3, timeConf: 'low' }],
  ['chocolate cake chocolate cake', { lines: [['test_choc', 1, 'kg']] }],
  ['ভ্যানিলা কেক ও চকলেট কেক দুটো করে', { lines: [['test_vanilla', 1, 'kg'], ['test_choc', 2, 'kg']] }],
  ['order: 2kg chocolate cake', { kind: 'order', lines: [['test_choc', 2, 'kg']] }],
  ['lagbe 3 kg vanilla cake', { kind: 'order', lines: [['test_vanilla', 3, 'kg']] }],
  ['3 kg vanilla cake dibo', { kind: 'order', lines: [['test_vanilla', 3, 'kg']] }],
  ['chai chocolate cake 1 kg', { kind: 'order', lines: [['test_choc', 1, 'kg']] }],
  ['দাম কত রসগোল্লার 1 কেজি?', { kind: 'price', lines: [['test_rosogolla', 1, 'kg']] }],
  ['pastry price 500 taka?', { kind: 'price', lines: [['test_pastry', 1, 'pc']] }],
  ['ভ্যানিলা কেক ১০০০ টাকা', { lines: [['test_vanilla', 1, 'kg']] }],
  ['Eid cake order 5 kg chocolate cake, Eid er dine', { kind: 'order', lines: [['test_choc', 5, 'kg']] }],
  ['pastry 2 pcs and sandesh 1 dozen and rosogolla 1 kg please order', { kind: 'order', lines: [['test_pastry', 2, 'pc'], ['test_sandesh', 1, 'dozen'], ['test_rosogolla', 1, 'kg']] }],
  ['পাঁচ কেজি বার্থডে কেক', { lines: [], unknown: true }],
  ['1 kg birthday cake for 01711000009 deliver at 6pm home', { phone: '01711000009', hour: 18, lines: [['test_birthday', 1, 'kg']] }],
  ['সন্দেশ ৫০০ গ্রাম কুরিয়ার', { lines: [['test_sandesh', 0.5, 'kg']] }],
  ['Shondesh 12 pieces', { lines: [['test_sandesh', 12, 'pc']] }],
  ['pauruti 6 ta lagbe kal', { kind: 'order', day: 1, lines: [['test_bread', 6, 'pc']] }],
  ['amar chocolate cake 2 kilo lagbe kal sokal 10 ta e', { kind: 'order', day: 1, lines: [['test_choc', 2, 'kg']] }],
  ['কেক', { kind: 'other', lines: [] }],
  ['🎂 chocolate cake 1kg 😊', { lines: [['test_choc', 1, 'kg']] }],
  ['Tomorrow 2 kg chocolate cake, 01711000009, House 9 Road 2 Banani, Dhaka. Payment bkash', { kind: 'order', phone: '01711000009', day: 1, lines: [['test_choc', 2, 'kg']] }],
  ['আপনাদের chocolate cake আছে? 1 kg লাগবে', { lines: [['test_choc', 1, 'kg']] }],
  ['birthday cake 1kg cancel korte chai', { lines: [['test_birthday', 1, 'kg']] }],
  ['ডিম ২ ডজন', { lines: [], unknown: true }],
  ['chocolet cake 4 pc', { lines: [['test_choc', 4, 'pc']] }],
  ['cookie 2 packets', { lines: [['test_cookies', 2, 'pc']], flags: ['unit_unclear'] }],
  ['vanila cake kal 1kg', { day: 1, lines: [['test_vanilla', 1, 'kg']] }],
  ['1kg rosgolla 2 pc', { lines: [['test_rosogolla', 1, 'kg']] }],
];

let pass = 0, fail = 0;
const bad = (i, msg, why) => { fail++; console.log('FAIL #' + i + ' ' + JSON.stringify(msg) + ' - ' + why); };

CASES.forEach(([msg, e], i) => {
  const r = P.parse(msg, CAT, { todayIso: TODAY });
  const probs = [];
  if (e.kind !== undefined && r.kind !== e.kind) probs.push('kind ' + r.kind + ' != ' + e.kind);
  if (e.phone !== undefined && r.mobile !== e.phone) probs.push('phone ' + r.mobile + ' != ' + e.phone);
  if (e.day !== undefined && (r.day ? r.day.offset : null) !== e.day) probs.push('day ' + (r.day ? r.day.offset : null) + ' != ' + e.day);
  if (e.hour !== undefined && (!r.time || r.time.hour !== e.hour)) probs.push('hour ' + (r.time ? r.time.hour : null) + ' != ' + e.hour);
  if (e.timeConf !== undefined && (!r.time || r.time.confidence !== e.timeConf)) probs.push('time confidence ' + (r.time ? r.time.confidence : null));
  if (e.name !== undefined && r.name !== e.name) probs.push('name ' + r.name);
  if (e.address !== undefined && r.address !== e.address) probs.push('address ' + r.address);
  if (e.lines !== undefined) {
    const known = r.lines.filter((l) => l.item_id);
    const got = known.map((l) => [l.item_id, l.qty, l.unit]);
    if (JSON.stringify(got) !== JSON.stringify(e.lines)) probs.push('lines ' + JSON.stringify(got) + ' != ' + JSON.stringify(e.lines));
  }
  if (e.unknown) { if (!r.lines.some((l) => !l.item_id) || r.flags.indexOf('unknown_item') < 0) probs.push('no unknown item flagged'); }
  (e.flags || []).forEach((f) => { if (r.flags.indexOf(f) < 0) probs.push('missing flag ' + f + ' (have ' + r.flags.join(',') + ')'); });
  (e.noFlags || []).forEach((f) => { if (r.flags.indexOf(f) >= 0) probs.push('unexpected flag ' + f); });
  if (r.note.indexOf('nothing is ordered') < 0) probs.push('draft note missing');
  if (probs.length) bad(i, msg, probs.join('; ')); else pass++;
});

// the rules that matter most, as direct checks
const safe = P.parse('2 kg chocolate cake', CAT, { todayIso: TODAY });
if (!(safe.kind && safe.note)) { bad('safety', 'x', 'no draft note'); } else pass++;
const unk = P.parse('mango cake 2 kg', CAT, { todayIso: TODAY });
if (unk.lines.length !== 1 || unk.lines[0].item_id !== null || unk.lines[0].confidence !== 'none') bad('no guess', 'mango', 'an unknown item was matched to something'); else pass++;
if (P.findPhone('call 0171100000x') !== null) bad('phone', 'x', 'bad phone matched'); else pass++;
if (P.isoDay(1, '2026-12-31') !== '2027-01-01') bad('iso', 'x', 'day rollover wrong'); else pass++;
if (P.normText('০১৭১১০০০০০৯') !== '01711000009') bad('digits', 'x', 'Bangla digits not converted'); else pass++;
// no alias shorter than 3 letters can match (no false hits on short words)
const short = P.parse('ok ya ok', [{ id: 'test_short', name_en: 'ok', aliases: ['ya'] }], { todayIso: TODAY });
if (short.lines.length !== 0) bad('short', 'x', 'short alias matched'); else pass++;

console.log('RESULT pass=' + pass + ' fail=' + fail + ' (messages=' + CASES.length + ')');
process.exit(fail ? 1 : 0);
