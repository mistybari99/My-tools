select 'C|'||coalesce(card_settle(1,(now() at time zone 'Asia/Dhaka')::date,600,12,'batch','0aa35f24-fdc6-4ef7-a5ad-c79f69c7c01e'::uuid)->>'dup','fresh');
