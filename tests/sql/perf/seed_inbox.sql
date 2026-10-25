\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-0000000000a1'
select set_config('request.jwt.claim.sub', :'o', false) is not null as x \gset
select set_rule('inbox_on','true') is null as r1 \gset
set session_replication_role = replica;
insert into sales_channels (code, kind, name_bn, location_id, active) values ('perf_tg','telegram','Perf Telegram',null,true),('perf_fb','facebook','Perf Facebook',null,true),('perf_wa','whatsapp','Perf WhatsApp',null,true);
insert into inbound_messages (channel_id, location_id, external_id, customer_handle, customer_name, msg_text, msg_time, received_at, status)
select (select id from sales_channels where code = (array['perf_tg','perf_fb','perf_wa'])[1+k%3]), 1+(k%3), 'ext'||k, '@h'||(k%900), 'Cust '||(k%900), 'order message text '||k||' please send two kg of item '||(k%500),
       now() - ((k*263)%129600 || ' minutes')::interval, now() - ((k*263)%129600 || ' minutes')::interval,
       case when k%20=0 then 'new' when k%5=0 then 'seen' when k%4=0 then 'converted' else 'ignored' end
from generate_series(1,30000) k;
reset session_replication_role;
analyze inbound_messages;
