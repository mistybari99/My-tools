#!/usr/bin/env python3
"""Build ONE combined paste page (Run 21-23: phases 131, 132, 133) from the three single pages.
usage: python3 tools/gen_setup_run_21_23.py <dir with setup-run-21.html 22 23> <out.html>
The SQL and CHECK strings are taken programmatically from the single pages (JSON string constants). The SQL strings are used byte-identical.
The CHECK strings get a few documented, asserted replacements so that every check, and Check all, can be run BEFORE the part is pasted
(they then answer 0/N and a cross instead of an error, and every check is false until its own part exists). Style and behaviour follow setup-run-17-20.html:
no chain lock, no localStorage, Copy Part N + its own Check + Check all."""
import json, re, sys, os

src, out = sys.argv[1], sys.argv[2]

def const(js, name):
    m = re.search(r'^const ' + name + r'=("(?:[^"\\\n]|\\.)*");', js, re.M)
    return json.loads(m.group(1)) if m else None

def load(n):
    s = open(os.path.join(src, 'setup-run-%d.html' % n), encoding='utf-8').read()
    js = re.search(r'<script>([\s\S]*?)</script>', s).group(1)
    return const(js, 'SQL'), const(js, 'CHECK')

def sub1(text, old, new):
    assert text.count(old) == 1, ('pattern count', text.count(old), old[:80])
    return text.replace(old, new)

(sql1, chk1), (sql2, chk2), (sql3, chk3) = load(21), load(22), load(23)

# ---- guards: a check must never error before its part is pasted, and must be false (not true) before ----
# Part 2 (phase 132)
sig = 'public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)'
chk2 = sub1(chk2,
  "to_regprocedure('%s') is not null and position('/* m132 */' in pg_get_functiondef('%s'::regprocedure)) > 0" % (sig, sig),
  "case when to_regprocedure('%s') is null then false else position('/* m132 */' in pg_get_functiondef(to_regprocedure('%s'))) > 0 end" % (sig, sig))
chk2 = sub1(chk2,
  "exists (select 1 from public.rules where key = 'org_scope_on' and kind = 'switch')),\n  ('132', 'browser role cannot write",
  "to_regclass('public.master_scope132') is not null and exists (select 1 from public.rules where key = 'org_scope_on' and kind = 'switch')),\n  ('132', 'browser role cannot write")
# items.org_unit_id already exists since phase125: count it only once phase132 is there (so 'before' is 0/N)
chk2 = sub1(chk2,
  "('132', 'column items.org_unit_id', exists (",
  "('132', 'column items.org_unit_id', to_regclass('public.master_scope132') is not null and exists (")
# Part 3 (phase 133)
chk3 = sub1(chk3,
  "public.rule_val('em_minutes') is not distinct from (select coalesce(r.value, r.default_value) from public.rules r where r.key = 'em_minutes')",
  "case when to_regclass('public.rule_overrides') is null then false else public.rule_val('em_minutes') is not distinct from (select coalesce(r.value, r.default_value) from public.rules r where r.key = 'em_minutes') end")
chk3 = sub1(chk3,
  "exists (select 1 from public.rules where key = 'org_scope_on' and kind = 'switch')),\n  ('133', 'browser role cannot write",
  "to_regclass('public.rule_overrides') is not null and exists (select 1 from public.rules where key = 'org_scope_on' and kind = 'switch')),\n  ('133', 'browser role cannot write")
chk3 = sub1(chk3,
  "not has_table_privilege('anon', 'public.rule_overrides', 'select') and not has_table_privilege('anon', 'public.rule_grant_overrides133', 'select') end",
  "not has_table_privilege('anon', to_regclass('public.rule_overrides'), 'select') and coalesce(not has_table_privilege('anon', to_regclass('public.rule_grant_overrides133'), 'select'), false) end")
chk3 = sub1(chk3,
  "not has_table_privilege('authenticated', 'public.rule_overrides', 'insert') end",
  "not has_table_privilege('authenticated', to_regclass('public.rule_overrides'), 'insert') end")
chk3 = sub1(chk3,
  "'no function of phase133 is executable by anon', not exists (",
  "'no function of phase133 is executable by anon', to_regprocedure('public.scope_gaps133()') is not null and not exists (")
chk2 = sub1(chk2,
  "else not has_table_privilege('authenticated', 'public.master_shares132', 'insert') end",
  "else not has_table_privilege('authenticated', to_regclass('public.master_shares132'), 'insert') end")

SQLS = [sql1, sql2, sql3]
CHECKS = [chk1, chk2, chk3]
PARTS = [
 ('Part 1', 'Phase 131: verified reports, Stage 1 (sales, profit, stock, wastage, cash, ageing). Switched OFF by the rule rpt131_on.', 'phase 131'),
 ('Part 2', 'Phase 132: master data (customers, items, suppliers ...) kept apart between businesses. Inert while org_scope_on is OFF.', 'phase 132'),
 ('Part 3', 'Phase 133: behaviour, permissions and reports kept apart between businesses. Inert while org_scope_on is OFF.', 'phase 133'),
]
URL = 'https://supabase.com/dashboard/project/rpqrcmesbhwtyrikabhy/sql/new'

# style + skeleton copied from the published setup-run-17-20.html (same head, same css)
ref = open(os.path.join(src, 'setup-run-17-20.html'), encoding='utf-8').read() if os.path.exists(os.path.join(src, 'setup-run-17-20.html')) else None
head_end = ref.find('</style></head><body>') + len('</style></head><body>') if ref else None
head = ref[:head_end].replace('<title>Run 17-20</title>', '<title>Run 21-23</title>')

def kb(b): return '%.1f KB &middot; {:,} bytes'.format(b) % (b / 1024.0)
def jsstr(s):
    t = json.dumps(s, ensure_ascii=False).replace('</', '<\\/').replace('\u2028', '\\u2028').replace('\u2029', '\\u2029')
    return t

h = [head]
h.append('\n<h1>Run 21-23</h1><div class="warn" id="qt">Three pastes in one page (phases 131 to 133). Paste the parts in order, Part 1 -> Part 3, one at a time in the Supabase SQL editor: copy, paste, Run once, then the next part. Do Run 17-20 first. Nothing you use today changes: every new feature is OFF.</div><small>No secrets here. Each part is safe to run twice. Every Check is read-only and may also be run before the part is pasted (it then shows a cross and 0/N).</small>\n')
h.append('<a class="b" href="%s" target="_blank" rel="noopener">Open Supabase SQL editor</a>\n' % URL)
for i, (nm, desc, ph) in enumerate(PARTS, 1):
    sb = len(SQLS[i-1].encode('utf-8')); cb = len(CHECKS[i-1].encode('utf-8'))
    h.append('<div class="box"><b>%s</b> <small>%s</small><div class="meta">%s</div>\n<button id="cp%d">Copy %s</button><div class="msg" id="m%d"></div>\n<a class="b" href="%s" target="_blank" rel="noopener">Open Supabase SQL editor</a>\n<small>Paste in Supabase SQL editor -> Run once. Safe to run twice.</small>\n<div style="border-top:1px solid #bb8b30;margin-top:10px;padding-top:6px"><b>Check (read-only)</b> <small>One SELECT, changes no data. Paste and Run: a tick or a cross for %s (a cross with 0/N if the part is not pasted yet).</small><div class="meta">%s</div><button id="cpc%d" class="sm">Check</button><div class="msg" id="mc%d"></div></div></div>\n'
      % (nm, desc, kb(sb), i, nm, i, URL, ph, kb(cb), i, i))
h.append('<div class="box" style="border-color:#1f6a46"><b>Check all (read-only)</b> <small>One SELECT, changes no data. Returns one row per phase (131 to 133) with a tick or a cross; safe before, between and after the pastes.</small><button id="cpall" class="sm">Check all</button><div class="msg" id="mall"></div></div>\n')
h.append('<script>\n')
for i in range(3): h.append('const SQL%d=%s;\n' % (i+1, jsstr(SQLS[i])))
for i in range(3): h.append('const CHECK%d=%s;\n' % (i+1, jsstr(CHECKS[i])))
h.append("""const SQLS=[SQL1,SQL2,SQL3],CHECKS=[CHECK1,CHECK2,CHECK3];
function checkAll(){return '-- READ-ONLY CHECK for Run 21-23 (all three parts). One SELECT: it writes, changes and deletes nothing.\\n-- Result: one row per phase with a tick or a cross; "missing" lists what is not there yet. Safe to run before the parts are pasted.\\nselect * from (\\n'+CHECKS.map(c=>'select * from (\\n'+c.trim().replace(/;\\s*$/,'')+'\\n) q').join('\\nunion all\\n')+'\\n) allq order by phase;\\n';}
async function copyText(t,m){
  try{await navigator.clipboard.writeText(t);m.textContent='Copied \\u2713 Now paste in Supabase \\u2192 Run';}
  catch(e){try{const ta=document.createElement('textarea');ta.value=t;ta.style.cssText='position:fixed;top:0;left:0;width:1px;height:1px;opacity:0';document.body.appendChild(ta);ta.focus();ta.select();const ok=document.execCommand('copy');ta.remove();m.textContent=ok?'Copied \\u2713 Now paste in Supabase \\u2192 Run':'Copy failed. Try again.';}catch(e2){m.textContent='Copy failed. Try again.';}}
}
for(let k=1;k<=3;k++){
  document.getElementById('cp'+k).onclick=()=>copyText(SQLS[k-1],document.getElementById('m'+k));
  document.getElementById('cpc'+k).onclick=()=>copyText(CHECKS[k-1],document.getElementById('mc'+k));
}
document.getElementById('cpall').onclick=()=>copyText(checkAll(),document.getElementById('mall'));
</script></body></html>
""")
open(out, 'w', encoding='utf-8').write(''.join(h))
print('wrote', out, os.path.getsize(out))
