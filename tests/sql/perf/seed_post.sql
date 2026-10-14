select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) is not null as x \gset
\timing on
select acct_post_pending(false,5000) - 'preview' as r \gset
select :'r'::jsonb->>'posted' p, :'r'::jsonb->>'more' m, :'r'::jsonb->>'errors' e, :'r'::jsonb->'waiting' w, :'r'::jsonb->'by_type' bt;
select acct_post_pending(false,5000) - 'preview' as r \gset
select :'r'::jsonb->>'posted' p, :'r'::jsonb->>'more' m, :'r'::jsonb->>'errors' e;
select acct_post_pending(false,5000) - 'preview' as r \gset
select :'r'::jsonb->>'posted' p, :'r'::jsonb->>'more' m, :'r'::jsonb->>'errors' e;
select acct_post_pending(false,5000) - 'preview' as r \gset
select :'r'::jsonb->>'posted' p, :'r'::jsonb->>'more' m, :'r'::jsonb->>'errors' e;
select acct_post_pending(false,5000) - 'preview' as r \gset
select :'r'::jsonb->>'posted' p, :'r'::jsonb->>'more' m, :'r'::jsonb->>'errors' e;
select count(*) entries, (select count(*) from journal_lines) lines from journal_entries;
