-- A5 prototype of the missing FACTORY-TO-BRANCH STATEMENT, built only from existing tables (stock_transfers, stock_ledger, stock_balance).
-- Runs right after the main scenario; every figure must equal the hand numbers of a5_01_main.sql. ASSUMPTION: "returned to factory" = a transfer whose sender is the branch and receiver is location 1.
\set o  '00000000-0000-0000-0000-000000000001'
select tt.as(:'o');
create temp table stmt as
with it as (select tt.iid('A5-SW') id),
 loc as (select id from locations where id in (1,2,3)),
 inn as (select t.to_location_id l, sum(t.qty) sent_in, sum(t.received_qty) recv_in, sum(t.qty - t.received_qty) filter (where t.status='received') short_in,
                sum(t.qty) filter (where t.status='sent') in_transit
           from stock_transfers t, it where t.item_id=it.id and t.status<>'cancelled' group by 1),
 outt as (select t.from_location_id l, sum(t.qty) sent_out from stock_transfers t, it where t.item_id=it.id and t.status<>'cancelled' group by 1),
 sold as (select s.location_id l, sum(-s.qty_delta) q from stock_ledger s, it where s.item_id=it.id and s.reason in ('sale_out') group by 1),
 waste as (select s.location_id l, sum(-s.qty_delta) q from stock_ledger s, it where s.item_id=it.id and s.reason='wastage' group by 1),
 made as (select s.location_id l, sum(s.qty_delta) q from stock_ledger s, it where s.item_id=it.id and s.reason='production_in' group by 1),
 bal as (select b.location_id l, b.qty from stock_balance b, it where b.item_id=it.id)
select loc.id as location_id, coalesce(made.q,0) made, coalesce(inn.sent_in,0) sent_in, coalesce(inn.recv_in,0) received_in, coalesce(inn.short_in,0) short_in,
       coalesce(inn.in_transit,0) in_transit_to, coalesce(outt.sent_out,0) sent_out, coalesce(sold.q,0) sold, coalesce(waste.q,0) wasted, coalesce(bal.qty,0) remaining
from loc left join inn on inn.l=loc.id left join outt on outt.l=loc.id left join sold on sold.l=loc.id left join waste on waste.l=loc.id left join made on made.l=loc.id left join bal on bal.l=loc.id order by 1;
select * from stmt;
-- A: sent_in 60, received 58, short 2, sent_out(return) 3, sold 40, wasted 2, remaining 13.  B: 30/30/0, sold 25, remaining 5.  Factory: made 100, sent_out 90, sent_in(returns) 3, remaining 13.
select tt.eq('ST-A1 A sent_in', 60, (select sent_in from stmt where location_id=2));
select tt.eq('ST-A2 A received', 58, (select received_in from stmt where location_id=2));
select tt.eq('ST-A3 A short', 2, (select short_in from stmt where location_id=2));
select tt.eq('ST-A4 A returned to factory', 3, (select sent_out from stmt where location_id=2));
select tt.eq('ST-A5 A sold', 40, (select sold from stmt where location_id=2));
select tt.eq('ST-A6 A wasted', 2, (select wasted from stmt where location_id=2));
select tt.eq('ST-A7 A identity: received - returned - sold - wasted = remaining', 13, (select received_in-sent_out-sold-wasted from stmt where location_id=2));
select tt.eq('ST-B1 B identity', 5, (select received_in-sent_out-sold-wasted from stmt where location_id=3));
select tt.eq('ST-F1 factory identity: made - sent out + returned in = remaining', 13, (select made-sent_out+received_in from stmt where location_id=1));
select tt.eq('ST-C1 company: made - sold - short - wasted = sum of remaining (31)', 31, (select sum(made-sold-wasted-short_in) from stmt) );
select tt.eq('ST-C2 sum of remaining', 31, (select sum(remaining) from stmt));
