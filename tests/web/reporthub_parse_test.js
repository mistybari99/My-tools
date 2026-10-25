// Question parser of the Business Memory hub (web/reporthub_parse.js). Pure node, no browser, no network: node tests/web/reporthub_parse_test.js <abs dir tests/web>
// Many phrasings in English and Bengali; a wrong reading must show up as an ambiguity or a missing slot, never as a silent guess.
const fs = require('fs'), path = require('path');
const SP = process.argv[2] || __dirname;
const ROOT = path.join(SP, '..', '..');
const P = require(path.join(ROOT, 'web', 'reporthub_parse.js'));
const registry = JSON.parse(fs.readFileSync(path.join(ROOT, 'web', 'data', 'report_registry.json'), 'utf8'));
const locations = [
  { id: 1, code: 'main', kind: 'showroom', name_bn: 'ইসলামিয়া মিষ্টি ঘর — মেইন শোরুম ও মেইন (মিষ্টি) কারখানা', name_en: 'ISLAMIYA MISTY GHAR — Main Showroom & Main (Sweet) Factory' },
  { id: 2, code: 'branch2', kind: 'showroom', name_bn: 'ইসলামিয়া মিষ্টি ঘর — ২য় শাখা', name_en: 'ISLAMIYA MISTY GHAR — 2nd Branch' },
  { id: 3, code: 'mishti_bari', kind: 'showroom', name_bn: 'মিষ্টি বাড়ি', name_en: 'MISTY BARI' },
  { id: 4, code: 'al_cakes', kind: 'showroom', name_bn: 'AL-CAKIZ (বাসার নিচে)', name_en: 'AL-CAKIZ (below the residence)' },
  { id: 5, code: 'mishti_factory', kind: 'factory', name_bn: 'মুজগুন্নি মিষ্টি কারখানা (বন্ধ, যন্ত্র রাখা)', name_en: 'Mujgunni Sweet Factory (closed, machines stored)' },
  { id: 6, code: 'cake_factory', kind: 'factory', name_bn: 'কেক কারখানা (বাসার নিচে)', name_en: 'Cake Factory (below the residence)' },
  { id: 7, code: 'godown', kind: 'godown', name_bn: 'গোডাউন (ইসলামিয়ার পাশের গলি)', name_en: 'Godown (lane beside ISLAMIYA MISTY GHAR)' },
];
const ctx = (o) => Object.assign({ today: '2026-10-17', locations, registry, fiscalStartMonth: null, weekStart: 6 }, o || {});
let bad = 0, n = 0;
const ok = (c, m, extra) => { n++; if (!c) { bad++; console.log('FAIL:', m, extra === undefined ? '' : JSON.stringify(extra)); } };
const T = (text, o) => P.parse(text, ctx(o));
const head = (r) => r.slots.head && r.slots.head.key;
const place = (r) => r.slots.place && r.slots.place.id;
const per = (r) => r.slots.period && [r.slots.period.from, r.slots.period.to];
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ---------- English ----------
let r = T("how much was paid for test_staff_a's meals in the last year");
ok(head(r) === 'staff_meal' && r.slots.person && r.slots.person.kind === 'staff' && /test_staff_a/.test(r.slots.person.query), 'meals + person', r.slots);
ok(same(per(r), ['2025-01-01', '2025-12-31']), 'last year = previous calendar year', per(r));
ok(r.intent === 'spend', 'meals is a spend question', r.intent);
r = T('electricity bill of main branch last 8 months');
ok(head(r) === 'electricity' && place(r) === 1 && same(per(r), ['2026-02-18', '2026-10-17']) && !r.slots.person, 'electricity main branch last 8 months', { h: head(r), p: place(r), per: per(r), person: r.slots.person });
ok(r.slots.head.utility.includes('electricity') && r.slots.head.heads.includes('electricity') && !r.slots.head.heads.includes('utilities'), 'electricity maps to the utility type; the broad head utilities is found by memo words only');
r = T('gas bill of branch 2 this year');
ok(head(r) === 'gas' && place(r) === 2 && same(per(r), ['2026-01-01', '2026-10-17']), 'gas branch 2 this year', { h: head(r), p: place(r), per: per(r) });
r = T('electricity of the 2nd branch last 3 months');
ok(place(r) === 2 && same(per(r), ['2026-07-18', '2026-10-17']), '2nd branch', { p: place(r), per: per(r) });
r = T('rent last month');
ok(head(r) === 'rent' && same(per(r), ['2026-09-01', '2026-09-30']), 'rent last month', { h: head(r), per: per(r) });
r = T('transport this month');
ok(head(r) === 'transport' && same(per(r), ['2026-10-01', '2026-10-17']), 'transport this month');
r = T('how much spent on repairs in october');
ok(head(r) === 'repair' && same(per(r), ['2026-10-01', '2026-10-31']), 'month name', { h: head(r), per: per(r) });
r = T('marketing expenses from 2026-01-01 to 2026-03-31');
ok(head(r) === 'marketing' && same(per(r), ['2026-01-01', '2026-03-31']), 'explicit dates', per(r));
r = T('salary of test_staff_a last 6 months');
ok(r.slots.kinds.includes('salary') && r.slots.person && r.slots.person.kind === 'staff' && same(per(r), ['2026-04-18', '2026-10-17']), 'salary', r.slots);
r = T('advance this month');
ok(r.slots.kind_list.includes('advance') && r.intent === 'spend', 'advance');
r = T('what happened on 2026-10-10');
ok(r.intent === 'day' && same(per(r), ['2026-10-10', '2026-10-10']), 'day replay intent', { i: r.intent, per: per(r) });
r = T('what happened yesterday at main branch');
ok(r.intent === 'day' && same(per(r), ['2026-10-16', '2026-10-16']) && place(r) === 1, 'yesterday + place', { i: r.intent, per: per(r), p: place(r) });
r = T('compare this month vs last month');
ok(r.intent === 'compare' && same([r.slots.period.from, r.slots.period2.from], ['2026-10-01', '2026-09-01']), 'compare intent with two periods', { i: r.intent, p1: per(r), p2: r.slots.period2 });
r = T('wastage last week');
ok(r.intent === 'report' && r.reports.some((x) => x.no === 76 || x.no === 50), 'wastage maps to an existing report', r.reports);
r = T('profit this month');
ok(r.intent === 'report' && r.reports.some((x) => x.no === 3 || x.no === 4), 'profit maps to the profit reports', r.reports);
r = T('meals and electricity last month');
ok(r.ambiguities.some((a) => a.slot === 'head' && a.options.length === 2) && head(r) === null, 'two different heads = ambiguity, not a pick', r.ambiguities);
r = T('factory electricity last year');
ok(r.ambiguities.some((a) => a.slot === 'place' && a.options.length >= 2) && place(r) === null, 'factory = several places = ambiguity', r.ambiguities);
r = T('godown rent this year');
ok(place(r) === 7, 'one godown = that place', place(r));
r = T('the water bill');
ok(r.intent === 'spend' && r.missing.includes('period') && r.ready === false, 'no period is MISSING, never defaulted', { i: r.intent, m: r.missing });
r = T('paid to supplier test_supplier_x last 3 months');
ok(r.slots.person && r.slots.person.kind === 'supplier' && r.slots.kind_list.includes('supplier_payment'), 'supplier person + payment kind', r.slots);
r = T('refund to customer test_customer_y last month');
ok(r.slots.person && r.slots.person.kind === 'customer' && r.slots.kind_list.includes('customer_refund'), 'customer refund', r.slots);
r = T('internet bill last 2 months');
ok(head(r) === 'internet' && same(per(r), ['2026-08-18', '2026-10-17']), 'number as word / digit', per(r));
r = T('electricity last two months');
ok(same(per(r), ['2026-08-18', '2026-10-17']), 'two = 2', per(r));
r = T('fuel for the van last 30 days');
ok(head(r) === 'transport' && same(per(r), ['2026-09-18', '2026-10-17']), 'van = transport; last 30 days', { h: head(r), per: per(r) });
r = T('electricity this fiscal year');
ok(r.slots.period.needs_setting === true && r.missing.includes('period') && r.notes.includes('fiscal_year_not_set'), 'fiscal year without the setting says so', r.slots.period);
r = T('electricity this fiscal year', { fiscalStartMonth: 7 });
ok(same(per(r), ['2026-07-01', '2026-10-17']), 'fiscal year with the setting', per(r));
r = T('electricity last fiscal year', { fiscalStartMonth: 7 });
ok(same(per(r), ['2025-07-01', '2026-06-30']), 'last fiscal year', per(r));
r = T('electricity this week', { weekStart: 6 });
ok(same(per(r), ['2026-10-17', '2026-10-17']), 'week starts Saturday (today is Saturday)', per(r));
r = T('electricity last week');
ok(same(per(r), ['2026-10-10', '2026-10-16']), 'last week', per(r));
r = T('electricity in december');
ok(same(per(r), ['2025-12-01', '2025-12-31']), 'december (not yet this year) = last december', per(r));
r = T('electricity may 2026');
ok(same(per(r), ['2026-05-01', '2026-05-31']), 'month with year', per(r));
r = T('electricity bill past year');
ok(same(per(r), ['2025-10-18', '2026-10-17']) || r.slots.period.kind === 'year', 'past year', per(r));

// ---------- Bengali ----------
r = T('গত ৮ মাসে মেইন শাখার বিদ্যুৎ বিল কত');
ok(head(r) === 'electricity' && place(r) === 1 && same(per(r), ['2026-02-18', '2026-10-17']) && !r.slots.person, 'bn: electricity main last 8 months', { h: head(r), p: place(r), per: per(r), person: r.slots.person });
r = T('গত এক বছরে রহিমের খাবার বাবদ কত টাকা দিয়েছি');
ok(head(r) === 'staff_meal' && same(per(r), ['2025-10-18', '2026-10-17']) && r.slots.person && r.slots.person.kind === 'staff' && r.slots.person.alts.includes('রহিম'), 'bn: person with suffix, meals, 1 year', { h: head(r), per: per(r), person: r.slots.person });
r = T('এই বছর ২য় শাখার গ্যাস বিল');
ok(head(r) === 'gas' && place(r) === 2 && same(per(r), ['2026-01-01', '2026-10-17']), 'bn: gas 2nd branch this year', { h: head(r), p: place(r), per: per(r) });
r = T('গত মাসে ভাড়া কত');
ok(head(r) === null && r.ambiguities.some((a) => a.slot === 'head' && a.options.map((o) => o.key).sort().join() === 'rent,transport'), 'bn: ভাড়া alone = rent or fare, ambiguity', r.ambiguities);
r = T('গত মাসে বাড়িভাড়া কত');
ok(head(r) === 'rent', 'bn: বাড়িভাড়া = rent', head(r));
r = T('গত মাসে রিকশা ভাড়া কত');
ok(head(r) === 'transport', 'bn: রিকশা ভাড়া = transport', head(r));
r = T('গতকাল কী হয়েছিল');
ok(r.intent === 'day' && same(per(r), ['2026-10-16', '2026-10-16']), 'bn: yesterday what happened', { i: r.intent, per: per(r) });
r = T('অক্টোবর মাসে খরচ কত');
ok(same(per(r), ['2026-10-01', '2026-10-31']) && r.intent === 'spend', 'bn: month name', { per: per(r), i: r.intent });
r = T('এই মাসের বেতন');
ok(r.slots.kind_list.includes('salary') && same(per(r), ['2026-10-01', '2026-10-17']), 'bn: salary this month', r.slots);
r = T('গত ৩০ দিনে অগ্রিম কত');
ok(r.slots.kind_list.includes('advance') && same(per(r), ['2026-09-18', '2026-10-17']), 'bn: advance 30 days', per(r));
r = T('গত দুই মাসে ইন্টারনেট বিল');
ok(head(r) === 'internet' && same(per(r), ['2026-08-18', '2026-10-17']), 'bn: number word', per(r));
r = T('গত সপ্তাহে বিক্রি কত');
ok(r.intent === 'report' && same(per(r), ['2026-10-10', '2026-10-16']), 'bn: sales last week -> report', { i: r.intent, per: per(r) });
r = T('এই মাসের লাভ কত');
ok(r.intent === 'report' && r.reports.some((x) => x.no === 3 || x.no === 4), 'bn: profit -> report', r.reports);
r = T('গত বছরের কারখানার বিদ্যুৎ বিল');
ok(r.ambiguities.some((a) => a.slot === 'place'), 'bn: factory = ambiguity', r.ambiguities);
r = T('সরবরাহকারী টেস্টএক্স কে গত ৩ মাসে কত দিয়েছি');
ok(r.slots.person && r.slots.person.kind === 'supplier', 'bn: supplier word', r.slots.person);
r = T('গত ১২ মাসে গ্যাস');
ok(same(per(r), ['2025-10-18', '2026-10-17']), 'bn digits 12', per(r));

// ---------- never a guess ----------
r = T('hello');
ok(r.intent === 'unknown' && r.ready === false, 'unrelated text = unknown', r.intent);
r = T('');
ok(r.intent === 'unknown' && r.missing.includes('text'), 'empty text');
r = T('asdf qwer zxcv');
ok(r.intent === 'unknown' && r.ready === false, 'gibberish = unknown, nothing run', r.intent);
r = T('last 8 months');
ok(r.intent !== 'spend' && !r.ready, 'a period alone does not run anything', r.intent);
r = T('electricity');
ok(r.intent === 'spend' && r.missing.includes('period') && !r.ready, 'electricity with no period waits', r.missing);
r = T('electricity bill main branch last 8 months');
ok(r.ready === true && r.missing.length === 0 && r.ambiguities.length === 0, 'a complete question is ready', { ready: r.ready, m: r.missing, a: r.ambiguities });
ok(r.understood.map((c) => c.slot).join() === 'person,head,place,period' && r.understood.every((c) => ['ok', 'any', 'missing', 'ambiguous'].includes(c.state)), 'the chips are always the same four slots, in order');
r = T('how much was paid to test_staff_a for meals last year');
ok(r.ready === false, 'a named person must be looked up first, so not ready', { ready: r.ready });
// phrasing variants of the same question give the same slots
const vs = ['electricity bill of main branch for the last 8 months', 'main branch electricity bill last 8 months', 'how much did we pay for electricity at main branch in the last 8 months', 'Electricity Bill Main Branch LAST 8 MONTHS'];
vs.forEach((v) => { const q = T(v); ok(head(q) === 'electricity' && place(q) === 1 && same(per(q), ['2026-02-18', '2026-10-17']) && !q.slots.person, 'variant: ' + v, { h: head(q), p: place(q), per: per(q), person: q.slots.person }); });
const bv = ['মেইন শাখার বিদ্যুৎ বিল গত ৮ মাসে', 'গত ৮ মাসের মেইন শাখার বিদ্যুতের বিল', 'মেইন শাখায় গত ৮ মাসে বিদ্যুৎ বিলে কত খরচ হয়েছে'];
bv.forEach((v) => { const q = T(v); ok(head(q) === 'electricity' && place(q) === 1 && same(per(q), ['2026-02-18', '2026-10-17']) && !q.slots.person, 'bn variant: ' + v, { h: head(q), p: place(q), per: per(q), person: q.slots.person }); });
// the parser itself never touches the network or the page
ok(typeof P.parse === 'function' && !/fetch\(|XMLHttpRequest|sb\.rpc|document\./.test(fs.readFileSync(path.join(ROOT, 'web', 'reporthub_parse.js'), 'utf8')), 'parser has no network / DOM code');
ok(registry.reports.length === 193 && registry.sections.length === 14, 'registry has 193 reports and 14 sections');
console.log(bad ? 'RESULT: ' + bad + ' FAILED of ' + n : 'RESULT: all ' + n + ' parser checks passed');
process.exit(bad ? 1 : 0);
