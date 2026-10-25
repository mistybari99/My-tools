select 'B|'||coalesce(setup_recommend_apply(gen_random_uuid())->>'count','?');
