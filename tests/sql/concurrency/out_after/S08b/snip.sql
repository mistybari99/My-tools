select 'C|'||coalesce(card_settle(1,(now() at time zone 'Asia/Dhaka')::date,600,12,'batch',gen_random_uuid())->>'over','?');
