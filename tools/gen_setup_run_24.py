#!/usr/bin/env python3
"""Build the paste page for Run 24 (phase 134: business profile + upper layers invisible) in the style of setup-run-21-23.html.
usage: python3 tools/gen_setup_run_24.py <dir that holds setup-run-23.html (style reference)> <out.html>
The SQL string is supabase/phase134.sql byte-identical. One part, one read-only Check that can be run BEFORE the paste (every test is guarded: a cross, never an error).
No chain lock, no localStorage."""
import json, re, sys, os

src, out = sys.argv[1], sys.argv[2]
repo = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SQL = open(os.path.join(repo, 'supabase', 'phase134.sql'), encoding='utf-8').read()

def rg(t): return "case when to_regclass('public.%s') is null then false else %%s end" % t
def fn(sig): return "to_regprocedure('public.%s') is not null" % sig
def body_has(sig, mark):
    return "case when to_regprocedure('public.%s') is null then false else position('%s' in pg_get_functiondef(to_regprocedure('public.%s'))) > 0 end" % (sig, mark, sig)
rows = [
 ("table business_profiles", "to_regclass('public.business_profiles') is not null"),
 ("table business_profile_ops134", "to_regclass('public.business_profile_ops134') is not null"),
 ("function business_profile_get", fn("business_profile_get(bigint)")),
 ("function business_profile_list134", fn("business_profile_list134()")),
 ("function business_profile_save", fn("business_profile_save(bigint,jsonb,uuid)")),
 ("helper _vis_biz134", fn("_vis_biz134()")), ("helper _unit_mgr134", fn("_unit_mgr134(bigint)")), ("helper _biz_mgr134", fn("_biz_mgr134(bigint)")),
 ("RLS on both new tables", "case when to_regclass('public.business_profiles') is null or to_regclass('public.business_profile_ops134') is null then false else (select bool_and(relrowsecurity) from pg_class where oid in (to_regclass('public.business_profiles'), to_regclass('public.business_profile_ops134'))) end"),
 ("every business has a profile", "case when to_regclass('public.business_profiles') is null then false else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.org_units u where u.kind = ''business'' and not exists (select 1 from public.business_profiles b where b.org_unit_id = u.id)', false, true, '')))[1]::text::int = 0 end"),
 ("the sweets business has a profile name", "case when to_regclass('public.business_profiles') is null then false else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.business_profiles b join public.org_units u on u.id = b.org_unit_id where u.code = ''SWEETS'' and length(b.display_name_bn) > 0', false, true, '')))[1]::text::int = 1 end"),
 ("the group unit was handled by the seed (named MD-AL AMIN, or a name you chose)", "exists (select 1 from public.org_units g where g.kind = 'group' and g.attrs -> 'seed134' is not null)"),
 ("the licence column is not readable by the browser role", "case when to_regclass('public.business_profiles') is null then false else not has_column_privilege('authenticated', to_regclass('public.business_profiles'), 'trade_licence_ref', 'select') end"),
 ("org_tree hides the upper layers", body_has("org_tree()", "prof134")),
 ("org_unit_scope hides the upper layers", body_has("org_unit_scope(integer)", "prof134")),
 ("org_unit_save is bound to the own business", body_has("org_unit_save(bigint,bigint,text,text,text,text,text,text,date,date,text,text,jsonb,jsonb,uuid)", "prof134")),
 ("org_scope_list hides the units above the business", body_has("org_scope_list(uuid)", "prof134")),
 ("master_scope_report132 is owner only", body_has("master_scope_report132()", "prof134")),
 ("daily_digest_biz133 gives no existence hint", body_has("daily_digest_biz133(bigint,date)", "prof134")),
 ("rule_val_in133 gives no existence hint", body_has("rule_val_in133(text,bigint)", "prof134")),
 ("policy on org_units follows the business", "exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'org_units' and policyname = 'ou122_read' and qual like '%_unit_mgr134%')"),
 ("no new function is executable by anon", "not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '(134$|_vis_biz134|_unit_mgr134|_unit_vis134|_biz_mgr134)' and has_function_privilege('anon', p.oid, 'execute'))"),
]
CHECK = ("-- READ-ONLY CHECK for phase 134 (Run 24). One SELECT: it writes, changes and deletes nothing.\n-- Paste in Supabase SQL editor -> Run once. Safe BEFORE the paste (every line is a cross then, never an error) and after it.\n"
         "with chk(phase, name, ok) as (values\n" + ",\n".join("  ('134', '%s', coalesce((%s), false))" % (n.replace("'", "''"), c) for n, c in rows) + ")\n"
         "select 'Phase ' || phase as phase,\n  case when bool_and(ok) then '\u2705 done' else '\u274c missing' end as status,\n  count(*) filter (where ok) || '/' || count(*) as found,\n"
         "  coalesce(string_agg(name, ', ') filter (where not ok), '') as missing\nfrom chk group by phase order by phase;\n")
ref = open(os.path.join(src, 'setup-run-23.html'), encoding='utf-8').read()
head = ref[:ref.index('</style></head><body>') + len('</style></head><body>')]
head = re.sub(r'<title>[^<]*</title>', '<title>Run 24</title>', head)
URL = 'https://supabase.com/dashboard/project/rpqrcmesbhwtyrikabhy/sql/new'
def kb(b): return '%.1f KB &middot; {:,} bytes'.format(b) % (b / 1024.0)
def jsstr(s): return json.dumps(s, ensure_ascii=False).replace('</', '<\\/').replace('\u2028', '\\u2028').replace('\u2029', '\\u2029')
sb, cb = len(SQL.encode('utf-8')), len(CHECK.encode('utf-8'))
h = [head]
h.append('\n<h1>Run 24</h1><div class="warn" id="qt">Medium paste (about %.0f KB, phase 134 only: one profile per business, and the upper layers made invisible to the people of a business). Paste once, in one go, AFTER Run 21-23. It renames the top owner/group to MD-AL AMIN only if it still has the old placeholder name, gives every business its own profile (the sweets business keeps its name), and makes the organization tree show a person only his own business. Nothing else changes.</div><small>Phase 134 only. No secrets here. Needs phases up to 133 (Run 21-23). No chain lock.</small>\n' % (sb / 1024.0))
h.append('<div class="box"><div class="meta">%s</div><button id="cp">Copy Run 24</button><div class="msg" id="m"></div>\n<a class="b" href="%s" target="_blank" rel="noopener">Open Supabase SQL editor</a>\n<small>Paste in Supabase SQL editor -> Run once. Safe to run twice.</small></div>\n' % (kb(sb), URL))
h.append('<div class="box" style="border-color:#1f6a46"><b>Check (read-only)</b> <small>One SELECT, changes no data. Safe before and after the paste: a tick or a cross for phase 134.</small><div class="meta">%s</div><button id="cpc" class="sm">Check</button><div class="msg" id="mc"></div><small>Paste in Supabase SQL editor -> Run once. Safe to run twice.</small></div>\n' % kb(cb))
h.append('<script>\nconst SQL=%s;\nconst CHECK=%s;\n' % (jsstr(SQL), jsstr(CHECK)))
h.append("""async function copyText(t,m){
  try{await navigator.clipboard.writeText(t);m.textContent='Copied \\u2713 Now paste in Supabase \\u2192 Run';}
  catch(e){try{const ta=document.createElement('textarea');ta.value=t;ta.style.cssText='position:fixed;top:0;left:0;width:1px;height:1px;opacity:0';document.body.appendChild(ta);ta.focus();ta.select();const ok=document.execCommand('copy');ta.remove();m.textContent=ok?'Copied \\u2713 Now paste in Supabase \\u2192 Run':'Copy failed. Try again.';}catch(e2){m.textContent='Copy failed. Try again.';}}
}
document.getElementById('cp').onclick=()=>copyText(SQL,document.getElementById('m'));
document.getElementById('cpc').onclick=()=>copyText(CHECK,document.getElementById('mc'));
</script></body></html>
""")
open(out, 'w', encoding='utf-8').write(''.join(h))
print('wrote', out, os.path.getsize(out))
