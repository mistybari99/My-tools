#!/bin/bash
# usage: fn_snapshot.sh <db> <out.tsv>   one line per public function: identity <TAB> md5(pg_get_functiondef) <TAB> sorted distinct bosNN tags
psql -h ${PGSOCK:-/tmp} -p ${PGPORT:-5544} -U postgres -d "$1" -qAt -F $'\t' -c "
select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)),
  coalesce((select string_agg(t, ',' order by t) from (select distinct m[1] t from regexp_matches(pg_get_functiondef(p.oid), '(bos[0-9]+)', 'g') m) x), '')
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind in ('f','p') order by 1" > "$2"
