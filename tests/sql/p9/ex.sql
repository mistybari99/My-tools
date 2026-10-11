set work_mem='64MB';
\timing on
explain (analyze, costs off, timing off) select f.item_id, coalesce(round(sum(f.qty),3),0), count(*), count(distinct f.sale_id), coalesce(round(sum(f.net),2),0), round(sum(f.qty*c.cost_price) filter (where c.cost_price is not null),2) from sales_fact f left join item_costs c on c.item_id=f.item_id where f.location_id = any ('{1,2,3,4,5,6,7}'::int[]) and f.day between '2026-01-01' and '2026-12-31' and f.status='done' group by 1;
explain (analyze, costs off, timing off) select f.item_id, coalesce(round(sum(f.qty),3),0), count(*), coalesce(round(sum(f.net),2),0) from sales_fact f where f.location_id = any ('{1,2,3,4,5,6,7}'::int[]) and f.day between '2026-01-01' and '2026-12-31' and f.status='done' group by 1;
