select 'A|'||coalesce(setup_recommend_apply('800afb46-959a-485d-8a33-d362c11a8b3f'::uuid)->>'dup','fresh')||'|'||(setup_recommend_apply('800afb46-959a-485d-8a33-d362c11a8b3f'::uuid)->>'count');
