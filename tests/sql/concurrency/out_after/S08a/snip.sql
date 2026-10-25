select 'C|'||coalesce(card_settle(1,(now() at time zone 'Asia/Dhaka')::date,600,12,'batch','81e19e79-6268-4b53-9e44-bc78519e71ad'::uuid)->>'dup','fresh');
