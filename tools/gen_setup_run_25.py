#!/usr/bin/env python3
"""Build the paste page for Run 25 (phase 135: places of a business created from the app) in the style of setup-run-21-23.html.
usage: python3 tools/gen_setup_run_25.py <dir that holds setup-run-24.html (style reference)> <out.html>
The SQL string is supabase/phase135.sql byte-identical. One part, one read-only Check that can be run BEFORE the paste (every test is guarded: a cross, never an error).
No chain lock, no localStorage."""
import json, re, sys, os

src, out = sys.argv[1], sys.argv[2]
repo = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SQL = open(os.path.join(repo, 'supabase', 'phase135.sql'), encoding='utf-8').read()

def rg(t): return "case when to_regclass('public.%s') is null then false else %%s end" % t
def fn(sig): return "to_regprocedure('public.%s') is not null" % sig
def body_has(sig, mark):
    return "case when to_regprocedure('public.%s') is null then false else position('%s' in pg_get_functiondef(to_regprocedure('public.%s'))) > 0 end" % (sig, mark, sig)
rows = [
 ("table business_place_ops135", "to_regclass('public.business_place_ops135') is not null"),
 ("RLS on business_place_ops135", "case when to_regclass('public.business_place_ops135') is null then false else (select relrowsecurity from pg_class where oid = to_regclass('public.business_place_ops135')) end"),
 ("function business_place_create135", fn("business_place_create135(bigint,text,text,text,text,bigint,uuid)")),
 ("function business_place_move135", fn("business_place_move135(integer,bigint,text,boolean,boolean,uuid,bigint)")),
 ("function business_places_list135", fn("business_places_list135(bigint)")),
 ("function business_profile_ensure135", fn("business_profile_ensure135(bigint)")),
 ("helper _pc_ok135", fn("_pc_ok135()")), ("helper _pc_biz135", fn("_pc_biz135()")), ("helper _pc_unit135", fn("_pc_unit135()")), ("helper _place_impact135", fn("_place_impact135(integer,bigint)")),
 ("location_save is patched once (the place is born mapped)", body_has("location_save(integer,jsonb)", "loc135")),
 ("location_save carries the marker exactly once", "case when to_regprocedure('public.location_save(integer,jsonb)') is null then false else (length(pg_get_functiondef(to_regprocedure('public.location_save(integer,jsonb)'))) - length(replace(pg_get_functiondef(to_regprocedure('public.location_save(integer,jsonb)')), '/* loc135 */', ''))) / length('/* loc135 */') = 1 end"),
 ("no new function is executable by anon", "not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '135$' and has_function_privilege('anon', p.oid, 'execute'))"),
 ("the token helpers are closed to the browser role", "not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_pc_ok135', '_pc_biz135', '_pc_unit135', '_place_impact135') and has_function_privilege('authenticated', p.oid, 'execute'))"),
 ("the browser role cannot write the ops table", "case when to_regclass('public.business_place_ops135') is null then false else not has_table_privilege('authenticated', to_regclass('public.business_place_ops135'), 'insert') end"),
]
CHECK = ("-- READ-ONLY CHECK for phase 135 (Run 25). One SELECT: it writes, changes and deletes nothing.\n-- Paste in Supabase SQL editor -> Run once. Safe BEFORE the paste (every line is a cross then, never an error) and after it.\n"
         "with chk(phase, name, ok) as (values\n" + ",\n".join("  ('135', '%s', coalesce((%s), false))" % (n.replace("'", "''"), c) for n, c in rows) + ")\n"
         "select 'Phase ' || phase as phase,\n  case when bool_and(ok) then '\u2705 done' else '\u274c missing' end as status,\n  count(*) filter (where ok) || '/' || count(*) as found,\n"
         "  coalesce(string_agg(name, ', ') filter (where not ok), '') as missing\nfrom chk group by phase order by phase;\n")
ref = open(os.path.join(src, 'setup-run-24.html'), encoding='utf-8').read()
head = ref[:ref.index('</style></head><body>') + len('</style></head><body>')]
head = re.sub(r'<title>[^<]*</title>', '<title>Run 25</title>', head)
URL = 'https://supabase.com/dashboard/project/rpqrcmesbhwtyrikabhy/sql/new'
def kb(b): return '%.1f KB &middot; {:,} bytes'.format(b) % (b / 1024.0)
def jsstr(s): return json.dumps(s, ensure_ascii=False).replace('</', '<\\/').replace('\u2028', '\\u2028').replace('\u2029', '\\u2029')
sb, cb = len(SQL.encode('utf-8')), len(CHECK.encode('utf-8'))
h = [head]
h.append('\n<h1>Run 25</h1><div class="warn" id="qt">Small paste (about %.0f KB, phase 135 only: places of a business). Paste once, in one go, AFTER Run 24. It lets the owner create the places (shops, branches, warehouses) of a second business from the app and maps them to that business, and lets the owner move a place between businesses (dry-run first). The only existing function it touches is location_save (one small, exact patch; the old Places screen behaves as before). Nothing else changes.</div><small>Phase 135 only. No secrets here. Needs phases up to 134 (Run 21-24). No chain lock.</small>\n' % (sb / 1024.0))
h.append('<div class="box"><div class="meta">%s</div><button id="cp">Copy Run 25</button><div class="msg" id="m"></div>\n<a class="b" href="%s" target="_blank" rel="noopener">Open Supabase SQL editor</a>\n<small>Paste in Supabase SQL editor -> Run once. Safe to run twice.</small></div>\n' % (kb(sb), URL))
h.append('<div class="box" style="border-color:#1f6a46"><b>Check (read-only)</b> <small>One SELECT, changes no data. Safe before and after the paste: a tick or a cross for phase 135.</small><div class="meta">%s</div><button id="cpc" class="sm">Check</button><div class="msg" id="mc"></div><small>Paste in Supabase SQL editor -> Run once. Safe to run twice.</small></div>\n' % kb(cb))
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
