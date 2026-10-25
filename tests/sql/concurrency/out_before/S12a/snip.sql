select 'A|'||coalesce(setup_recommend_apply('a4ae4e4b-4fe9-4b2b-8a7d-ad030542e523'::uuid)->>'dup','fresh')||'|'||(setup_recommend_apply('a4ae4e4b-4fe9-4b2b-8a7d-ad030542e523'::uuid)->>'count');
