#!/usr/bin/env python3
"""Build web/data/report_registry.json: the static catalogue behind the Business Memory reports hub (web/reporthub.js).

The registry holds, for every number of the master report list (1..193): id, name in the three language modes, section, the one-line question it answers,
the route / key where the report already exists (or "planned"), a status badge (implemented / incomplete / unavailable / unverified / unaudited),
the data source and the required grant. It also holds the word lists the question parser uses (heads, periods, kinds, measures). Nothing here is a business number.

Seeded from the two audits (REPORTS_AUDIT_1 = reports 1-55, REPORTS_AUDIT_2 = reports 56-104). Reports 105-193 (sections 8-14) are
"unaudited" until audit 3 lands.  To merge audit 3 (or any later change) without editing this file:

    python3 tools/build_report_registry.py --merge docs/REPORTS_AUDIT_3.md          # markdown pipe table(s), see parse_audit_table()
    python3 tools/build_report_registry.py --merge audit3.csv                       # or a csv with the same columns
    python3 tools/build_report_registry.py --master docs/inputs/report_master_list.csv   # optional: the owner's exact names (no,section,name_bn,name_en)
    python3 tools/build_report_registry.py --check                                  # verify web/data/report_registry.json is what this script builds

Table columns (header names, any order, case-insensitive; extra columns are ignored):
    no | name_en | name_bn | section | question_en | question_bn | status | route | source | grant | area | kw | note
    status: implemented | incomplete | unavailable | unverified.  route: report/<key> | <screen route> | planned.
A row for a number that already exists REPLACES the seed row field by field (only the columns that are filled in).
Run with no argument to rebuild the JSON from the seed + the files in tools/report_registry_merge/ (every *.md and *.csv there is merged in name order).
"""
import csv, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'web', 'data', 'report_registry.json')
MERGE_DIR = os.path.join(ROOT, 'tools', 'report_registry_merge')
TOTAL = 193

SECTIONS = [
    (1, 'Executive and management', 'নির্বাহী ও ব্যবস্থাপনা', 1, 10), (2, 'Sales and POS', 'বিক্রি ও POS', 11, 28), (3, 'Product profitability', 'পণ্যের লাভজনকতা', 29, 39),
    (4, 'Production', 'উৎপাদন', 40, 55), (5, 'Stock and inventory', 'স্টক ও মজুত', 56, 75), (6, 'Wastage, freshness and quality', 'অপচয়, তাজা অবস্থা ও মান', 76, 89),
    (7, 'Purchasing and suppliers', 'ক্রয় ও সরবরাহকারী', 90, 104),
]
# sections 8-14: names and number ranges are not known until audit 3 lands; the numbers 105-193 are kept as "unaudited"
for n in range(8, 15):
    SECTIONS.append((n, 'Section %d (not audited yet)' % n, 'বিভাগ %d (এখনও যাচাই হয়নি)' % n, None, None))

GRANTS = {'exec': 'owner or report_profit / view_reports', 'sales': 'report_sales', 'pos': 'report_pos', 'cash': 'report_cash', 'cust': 'report_customers', 'stock': 'report_stock',
          'purch': 'report_purchase', 'exp': 'report_expense', 'profit': 'report_profit or accounts_view', 'cost': 'view_cost', 'quality': 'report_quality', 'ctl': 'report_control',
          'items': 'ITEMS view', 'fin': 'accounts_view', 'ord': 'report_orders', 'staff': 'report_staff'}
AREAS = {'exec': 'Executive', 'sales': 'Sales', 'product': 'Product profit', 'production': 'Production', 'stock': 'Stock', 'quality': 'Quality', 'purchase': 'Purchasing'}

# no | area | status | route | name_en | name_bn | question_en | question_bn | source | grant | kw
# status: I implemented, C incomplete, U unavailable, V unverified.   route: - = planned.   (short codes keep the table readable)
SEED = r'''
1|exec|C|owner|Executive dashboard|নির্বাহী ড্যাশবোর্ড|How is the whole business doing right now?|পুরো ব্যবসা এখন কেমন চলছে?|sales, stock, exceptions (owner board, home)|exec|owner,board,overview,home,সারসংক্ষেপ,মালিকের বোর্ড
2|exec|C|report/pos_day_close|Daily business summary|দৈনিক ব্যবসার সারসংক্ষেপ|What happened in one shop on one day: sales, cash, short or over?|এক দিনে এক দোকানে কী হলো: বিক্রি, ক্যাশ, কম-বেশি?|sales, sale_payments, form 14-1|pos|day close,z report,daily,দিনশেষ,দৈনিক,ক্যাশ মেলানো
3|exec|C|report/l1_pnl|Monthly business summary|মাসিক ব্যবসার সারসংক্ষেপ|What was the month's sales, cost and profit?|মাসে বিক্রি, খরচ আর লাভ কত ছিল?|l1_pnl, month close|profit|month,monthly,p&l,মাস,মাসিক,লাভ
4|exec|C|report/l1_pnl|Sales, gross profit and net profit|বিক্রি, মোট লাভ ও নিট লাভ|How much did we earn and keep after cost and expenses?|খরচ বাদ দিয়ে আসলে কত থাকল?|l1_pnl, l3_shop_pnl, profit check|profit|profit,gross,net,margin,লাভ,মুনাফা,নিট
5|exec|I|report/l3_shop_pnl|Outlet comparison|শাখা তুলনা|Which shop does better than the others?|কোন দোকান অন্যদের চেয়ে ভালো করছে?|l3_shop_pnl, sales_combined|profit|outlet,branch,shop,compare,শাখা,দোকান,তুলনা
6|exec|I|brandpnl|Brand comparison|ব্র্যান্ড তুলনা|Which brand earns more?|কোন ব্র্যান্ড বেশি আয় করছে?|brand_pnl, report_brand_map|profit|brand,ব্র্যান্ড,মিষ্টি বাড়ি,cakiz
7|exec|U|-|Factory versus retail|কারখানা বনাম খুচরা|How does the factory do against the shops?|কারখানা ও দোকানের ফল কেমন তুলনায়?|not captured (transfer valuation)|profit|factory,retail,কারখানা,খুচরা
8|exec|V|finance2|Budget versus actual|বাজেট বনাম বাস্তব|Are we within the budget?|আমরা কি বাজেটের মধ্যে আছি?|budgets, journal|fin|budget,বাজেট,plan
9|exec|U|-|Target versus achievement|লক্ষ্য বনাম অর্জন|Did we reach the sales target?|বিক্রির লক্ষ্যে পৌঁছেছি কি?|not captured (no targets)|exec|target,goal,লক্ষ্য
10|exec|C|owner|KPI trends and exception alerts|KPI-র ধারা ও ব্যতিক্রম সতর্কতা|Which numbers are drifting or red?|কোন সংখ্যাগুলো সরে যাচ্ছে বা লাল?|owner board, exceptions|exec|kpi,trend,alert,red,সতর্ক,লাল
11|sales|I|report/sales_summary|Sales summary|বিক্রির সারসংক্ষেপ|How much did we sell, in how many bills?|কত বিক্রি হলো, কয়টি বিলে?|sales|sales|sales,summary,total,বিক্রি,মোট
12|sales|I|report/sales_trend|Sales trend and period comparison|বিক্রির ধারা ও সময় তুলনা|Is selling going up or down compared with before?|আগের সময়ের চেয়ে বিক্রি বাড়ছে না কমছে?|sales|sales|trend,compare,growth,ধারা,তুলনা
13|sales|I|report/sales_combined|Sales by outlet and brand|শাখা ও ব্র্যান্ড অনুযায়ী বিক্রি|Which outlet or brand sells what?|কোন শাখা বা ব্র্যান্ড কত বিক্রি করে?|sales|sales|outlet,brand,শাখা,ব্র্যান্ড
14|sales|I|report/item_sales|Item-wise sales|আইটেম অনুযায়ী বিক্রি|Which items sell, how many, for how much?|কোন আইটেম কত বিক্রি হচ্ছে?|sales lines|sales|item,product,আইটেম,পণ্য
15|sales|I|report/category_sales|Category-wise sales|ক্যাটাগরি অনুযায়ী বিক্রি|Which category carries the sales?|কোন ক্যাটাগরি বিক্রি টানছে?|sales lines|sales|category,ক্যাটাগরি
16|sales|I|report/hour_weekday|Sales by hour and weekday|ঘণ্টা ও বার অনুযায়ী বিক্রি|When are the busy hours and days?|কোন সময় ও কোন বার ভিড় বেশি?|sales|sales|hour,peak,weekday,ঘণ্টা,ভিড়,বার
17|sales|I|report/retail_wholesale|Retail versus wholesale|খুচরা বনাম পাইকারি|How big is the wholesale share?|পাইকারির অংশ কত বড়?|sales|sales|wholesale,retail,পাইকারি,খুচরা
18|sales|I|report/receipt_register|Receipt and invoice register|রসিদ ও ইনভয়েস তালিকা|Show me every bill of a day.|একদিনের সব বিল দেখান।|sales|sales|receipt,invoice,bill,register,রসিদ,বিল
19|sales|I|report/payment_modes|Payment method report|পেমেন্ট পদ্ধতি রিপোর্ট|How much came in by cash, mobile, card, due?|নগদ, মোবাইল, কার্ড, বাকিতে কত এলো?|sale_payments|cash|payment,cash,bkash,mobile,card,পেমেন্ট,নগদ,বিকাশ
20|sales|C|discounts|Discounts and price overrides|ডিসকাউন্ট ও দাম বদল|Who gave how much discount?|কে কত ডিসকাউন্ট দিল?|sales (discount, override flag)|pos|discount,override,ডিসকাউন্ট,ছাড়
21|sales|I|report/voids|Voids, refunds and returns|বাতিল, ফেরত ও রিটার্ন|How many sales were voided or returned, and why?|কয়টি বিক্রি বাতিল বা ফেরত হলো, কেন?|sales, sale_returns|pos|void,refund,return,বাতিল,ফেরত
22|sales|I|report/quick_unlisted|Quick and unlisted sales|কুইক ও তালিকা-বহির্ভূত বিক্রি|Which sales had no item or cost?|কোন বিক্রিতে আইটেম বা খরচ ছিল না?|sales (quick)|pos|quick,unlisted,কুইক
23|sales|C|report/sales_summary|Average bill and items per bill|গড় বিল ও বিলপ্রতি আইটেম|What is the average bill?|গড় বিল কত?|sales|sales|average,ticket,avg,গড়,বিল
24|sales|U|-|Sales target by outlet|শাখাভিত্তিক বিক্রির লক্ষ্য|Is each outlet on target?|প্রতিটি শাখা কি লক্ষ্যে আছে?|not captured (no targets)|sales|target,লক্ষ্য
25|sales|I|report/item_sales|Top, low and declining products|সেরা, কম ও কমতি পণ্য|Which products rise, which fall?|কোন পণ্য বাড়ছে, কোনটা কমছে?|sales lines|sales|top,slow,declining,সেরা,ধীর,কমছে
26|sales|I|report/x5_staff_trend|Sales by salesperson and cashier|বিক্রয়কর্মী ও ক্যাশিয়ার অনুযায়ী বিক্রি|Who sells how much?|কে কত বিক্রি করে?|sales|sales|staff,cashier,salesperson,কর্মী,ক্যাশিয়ার
27|sales|C|report/s10_orders|Sales channel analysis|বিক্রির মাধ্যম বিশ্লেষণ|Where do orders come from: shop, online, phone?|অর্ডার কোথা থেকে আসে: দোকান, অনলাইন, ফোন?|paper form 20-1 (free-text channel)|ord|channel,online,order,অনলাইন,অর্ডার
28|sales|I|report/q3_complaints|Return and refund reasons|ফেরত ও রিফান্ডের কারণ|Why do customers return things?|গ্রাহক কেন জিনিস ফেরত দেয়?|form 20-3, sale_returns|quality|complaint,return reason,অভিযোগ,কারণ
29|product|I|report/l2_margin|Gross profit and margin by item|আইটেম অনুযায়ী মোট লাভ ও মার্জিন|Which item earns what margin?|কোন আইটেমে কত মার্জিন?|l2_margin (stock-ledger cost)|cost|margin,gp,gross profit,মার্জিন,লাভ
30|product|I|report/l2_margin|Profitability by category|ক্যাটাগরি অনুযায়ী লাভজনকতা|Which category makes money?|কোন ক্যাটাগরি লাভ দেয়?|l2_margin|cost|category,ক্যাটাগরি
31|product|I|report/l3_shop_pnl|Profitability by outlet|শাখা অনুযায়ী লাভজনকতা|Which outlet makes money?|কোন শাখা লাভ দেয়?|l3_shop_pnl|profit|outlet,শাখা
32|product|C|items|Selling price versus current cost|বিক্রয়মূল্য বনাম বর্তমান খরচ|Do our prices still cover cost?|আমাদের দাম কি এখনও খরচ তুলে আনে?|items, item_costs, recipes|cost|price,cost,দাম,খরচ
33|product|C|costing|Standard versus actual cost variance|স্ট্যান্ডার্ড বনাম প্রকৃত খরচের পার্থক্য|Did production cost more than planned?|উৎপাদনে পরিকল্পনার চেয়ে বেশি খরচ হলো?|production_runs|cost|variance,standard,actual,পার্থক্য
34|product|I|report/l2_margin|Contribution profit by product|পণ্যভিত্তিক অবদান-লাভ|What does each product add after direct cost?|সরাসরি খরচ বাদে প্রতিটি পণ্য কত যোগ করে?|l2_margin|cost|contribution,অবদান
35|product|I|report/l2_margin|Product profitability ranking|পণ্যের লাভজনকতার ক্রম|Rank products by profit.|লাভ অনুযায়ী পণ্য সাজান।|l2_margin|cost|rank,ranking,ক্রম
36|product|C|items|Price change history and impact|দাম বদলের ইতিহাস ও প্রভাব|What happened to sales after a price change?|দাম বদলের পর বিক্রিতে কী হলো?|item_price_history|items|price change,history,দাম বদল
37|product|I|report/item_sales|Discount impact on profit|মুনাফায় ডিসকাউন্টের প্রভাব|How much profit did discounts eat?|ডিসকাউন্ট কত লাভ খেয়ে নিল?|sales lines|cost|discount,impact,ডিসকাউন্ট
38|product|C|report/l2_margin|Low-margin and loss-making products|কম মার্জিন ও লোকসানের পণ্য|Which items sell below a safe margin?|কোন পণ্য নিরাপদ মার্জিনের নিচে বিক্রি হয়?|l2_margin|cost|low margin,loss,লোকসান,কম মার্জিন
39|product|C|biz|Portfolio: high sales versus high profit|পোর্টফোলিও: বেশি বিক্রি বনাম বেশি লাভ|Which items sell much but earn little?|কোন পণ্য বেশি বিক্রি হয় কিন্তু লাভ কম?|biz (ABC)|cost|abc,portfolio
40|production|U|-|Production plan versus actual|উৎপাদন পরিকল্পনা বনাম বাস্তব|Did we make what we planned?|যা পরিকল্পনা করেছি তা কি বানিয়েছি?|not captured (no plan)|stock|plan,actual,পরিকল্পনা
41|production|I|report/f1_production|Batch and production register|ব্যাচ ও উৎপাদন তালিকা|What was made, when, by whom?|কী কখন কে বানাল?|production_runs|stock|batch,production,ব্যাচ,উৎপাদন
42|production|I|costing|Recipe and BOM costing|রেসিপি ও BOM খরচ|What does one batch cost?|এক ব্যাচের খরচ কত?|recipes, recipe_lines|cost|recipe,bom,রেসিপি
43|production|C|costing|Standard versus actual manufacturing cost|স্ট্যান্ডার্ড বনাম প্রকৃত উৎপাদন খরচ|Is real cost above the recipe cost?|প্রকৃত খরচ কি রেসিপির খরচের চেয়ে বেশি?|production_runs|cost|standard,actual
44|production|U|report/f3_raw_vs_recipe|Raw material use versus recipe|কাঁচামাল ব্যবহার বনাম রেসিপি|Did we use more milk or sugar than the recipe says?|রেসিপির চেয়ে বেশি দুধ বা চিনি লেগেছে?|not captured (real issue per batch)|stock|raw,recipe,variance,কাঁচামাল
45|production|C|report/f2_yield|Yield versus standard|ফলন বনাম মান|Did a batch give the expected yield?|ব্যাচ কি প্রত্যাশিত ফলন দিল?|form 05-4 yield test|stock|yield,ফলন
46|production|I|costing|Batch-wise production cost|ব্যাচভিত্তিক উৎপাদন খরচ|What did each batch cost?|প্রতিটি ব্যাচে কত খরচ?|production_runs|cost|batch cost
47|production|C|costing|Labour and overhead cost|শ্রম ও ওভারহেড খরচ|How much labour and overhead goes into a batch?|এক ব্যাচে শ্রম ও ওভারহেড কত?|cost components|cost|labour,overhead,শ্রম,ওভারহেড
48|production|U|-|Output per labour hour|শ্রমঘণ্টাপ্রতি উৎপাদন|How productive is the labour?|শ্রমিকরা কতটা উৎপাদনশীল?|not captured (no labour hours)|stock|labour hour,productivity
49|production|C|report/f2_yield|Rejection, rework and production loss|বাতিল, পুনঃকাজ ও উৎপাদন ক্ষতি|How much was lost while making?|বানাতে গিয়ে কত নষ্ট হলো?|form 05-4|stock|reject,rework,loss,নষ্ট
50|production|I|report/wastage|Wastage by reason, product and batch|কারণ, পণ্য ও ব্যাচ অনুযায়ী অপচয়|What was wasted and why?|কী নষ্ট হলো আর কেন?|stock_wastage|stock|wastage,waste,অপচয়,নষ্ট
51|production|U|-|Capacity utilization|ক্ষমতা ব্যবহার|How much of the capacity is used?|ক্ষমতার কত অংশ ব্যবহার হচ্ছে?|not captured (no rated capacity)|stock|capacity
52|production|U|-|Production orders and pending orders|উৎপাদন অর্ডার ও বাকি অর্ডার|Which orders are waiting to be made?|কোন অর্ডার বানানোর অপেক্ষায়?|not captured|stock|order,pending
53|production|C|report/f1_production|Production-to-dispatch reconciliation|উৎপাদন থেকে চালানের মিল|Made, sent, received, short: does it add up?|বানানো, পাঠানো, পাওয়া, কম: হিসাব মেলে?|production_runs, stock_transfers|stock|dispatch,reconcile,চালান
54|production|I|report/k3_store_ledger|Finished goods: produced, sold, remaining|তৈরি মাল: বানানো, বিক্রি, বাকি|How much finished stock is left?|কতটা তৈরি মাল বাকি আছে?|stock_ledger|stock|finished goods,fg,তৈরি মাল
55|production|U|-|Manufacturing cost variance analysis|উৎপাদন খরচ পার্থক্য বিশ্লেষণ|Is the cost gap from price, usage or yield?|খরচের পার্থক্য কি দাম, ব্যবহার না ফলনের?|not captured (needs actual use and yield)|cost|variance
56|stock|I|report/stock_balance|Stock levels by item and place|আইটেম ও জায়গা অনুযায়ী মজুত|How much of each item is where?|কোন আইটেম কোথায় কত আছে?|stock_balance|stock|stock,balance,level,মজুত,স্টক
57|stock|C|report/stock_balance|Stock value|মজুতের মূল্য|What is the stock worth?|মজুতের দাম কত?|stock_balance (avg cost)|cost|valuation,value,মূল্য
58|stock|I|report/stock_low|Low-stock list|কম মজুতের তালিকা|What is running out?|কী ফুরিয়ে আসছে?|stock_balance, items.min_stock|stock|low stock,minimum,কম মজুত
59|stock|I|stockx|Reorder suggestions|আবার অর্ডারের পরামর্শ|What should we reorder?|কী আবার অর্ডার করা উচিত?|reorder_report|stock|reorder,অর্ডার
60|stock|C|report/stock_balance|Raw material stock|কাঁচামালের মজুত|How much raw material is on hand?|হাতে কাঁচামাল কত?|stock_balance|stock|raw material,কাঁচামাল
61|stock|C|report/stock_balance|Finished goods stock|তৈরি মালের মজুত|How much finished stock is on hand?|হাতে তৈরি মাল কত?|stock_balance|stock|finished,তৈরি মাল
62|stock|C|report/stock_balance|Packaging stock|প্যাকেজিং মজুত|How much packaging is on hand?|হাতে প্যাকেজিং কত?|stock_balance|stock|packaging,box,প্যাকেজিং,বাক্স
63|stock|C|report/k3_store_ledger|Stock movement: opening, in, out, closing|মজুত চলাচল: শুরু, ঢোকা, বেরোনো, শেষ|What moved in and out of an item?|একটি আইটেমে কী ঢুকল আর বেরোল?|stock_ledger|stock|movement,ledger,চলাচল
64|stock|C|report/transfers_gap|Transfer register|ট্রান্সফার তালিকা|What was sent between places?|জায়গায় জায়গায় কী পাঠানো হলো?|stock_transfers|stock|transfer,challan,ট্রান্সফার,চালান
65|stock|C|shortages|Transfer receipt differences|ট্রান্সফার গ্রহণে পার্থক্য|What arrived short or damaged?|কী কম বা নষ্ট পৌঁছাল?|shortage_transit|stock|short,damaged,transit,কম,পথে
66|stock|C|report/k2_count_variance|Stock count variance|স্টক গণনার পার্থক্য|Where did the count differ from the books?|গণনা কোথায় খাতার সাথে মেলেনি?|form 04-3, stock_count_adjust|stock|count,variance,গণনা
67|stock|C|report/item_slow|Slow and dead stock|ধীর ও মৃত স্টক|What is not selling?|কী বিক্রি হচ্ছে না?|sales, stock|stock|slow,dead,ধীর
68|stock|U|-|Stock ageing|স্টকের বয়স|How old is what we hold?|যা আছে তার বয়স কত?|not captured (no lot date on raw receipts)|stock|ageing,age,বয়স
69|stock|C|report/expiry_soon|Expiry list|মেয়াদ তালিকা|What expires soon?|কী শিগগির মেয়াদ শেষ হবে?|stock_batches|stock|expiry,expire,মেয়াদ
70|stock|C|stockx|Batch ageing and FEFO view|ব্যাচের বয়স ও FEFO|Which batch should go out first?|কোন ব্যাচ আগে বেরোবে?|stock_batches|stock|fefo,batch,ব্যাচ
71|stock|C|report/k3_store_ledger|Stock adjustments: who, why, value|স্টক সমন্বয়: কে, কেন, কত|Who adjusted stock and why?|কে কেন স্টক সমন্বয় করল?|stock_ledger|stock|adjustment,সমন্বয়
72|stock|C|report/exceptions_summary|Negative stock and integrity list|ঋণাত্মক স্টক ও অসঙ্গতি তালিকা|Where is the stock below zero or wrong?|কোথায় স্টক শূন্যের নিচে বা ভুল?|stock_balance, exceptions|stock|negative,integrity,ঋণাত্মক
73|stock|C|stockx|Stock turnover|স্টক আবর্তন|How fast does stock turn over?|স্টক কত দ্রুত ঘোরে?|stock_ledger|stock|turnover,আবর্তন
74|stock|U|-|Stockout and unmet demand|স্টক ফুরানো ও অপূর্ণ চাহিদা|When did we run out and lose sales?|কখন স্টক ফুরিয়ে বিক্রি হারালাম?|not captured (no stockout log)|stock|stockout,demand,ফুরিয়ে
75|stock|C|report/stock_balance|Period stock reconciliation|সময়কালের স্টক মিলান|Opening plus in minus out equals closing?|শুরু + ঢোকা - বেরোনো = শেষ?|stock_ledger, stock_reconcile|stock|reconcile,মিলান
76|quality|I|report/wastage|Wastage report|অপচয় রিপোর্ট|How much was written off?|কত বাদ দেওয়া হলো?|stock_wastage|stock|wastage,write off,অপচয়
77|quality|C|report/wastage|Wastage as a share of stock or sales|মজুত বা বিক্রির তুলনায় অপচয়|Is wastage rising against sales?|বিক্রির তুলনায় অপচয় কি বাড়ছে?|stock_wastage, sales|stock|wastage percent,অপচয় শতাংশ
78|quality|C|report/f2_yield|Production wastage and yield|উৎপাদনে অপচয় ও ফলন|How much is lost in making?|বানাতে কত নষ্ট হয়?|form 05-4, stock_wastage|stock|yield,production loss
79|quality|C|report/wastage|Unsold and expired goods|অবিক্রিত ও মেয়াদোত্তীর্ণ মাল|How much was thrown away unsold?|কত অবিক্রিত ফেলে দেওয়া হলো?|stock_wastage, returns|stock|unsold,expired,অবিক্রিত
80|quality|C|-|Unsold finished goods by batch|ব্যাচ অনুযায়ী অবিক্রিত তৈরি মাল|Which batches are left unsold?|কোন ব্যাচ অবিক্রিত পড়ে আছে?|stock_batches|stock|unsold,batch
81|quality|U|-|Shelf-life setup coverage|মেয়াদ নির্ধারণের কভারেজ|Which items have no shelf life set?|কোন আইটেমের মেয়াদ ঠিক করা নেই?|not captured (shelf_life_rules empty)|stock|shelf life,মেয়াদ
82|quality|C|-|Daily closing stock versus next-day opening|দিনশেষ স্টক বনাম পরদিন শুরু|Does closing stock match tomorrow's opening?|দিনশেষ স্টক কি পরদিনের শুরুর সাথে মেলে?|stock_ledger|stock|closing,opening
83|quality|U|-|Batch traceability: supplier lot to sale|ব্যাচ ট্রেস: সরবরাহকারীর লট থেকে বিক্রি|Where did a batch come from and go to?|একটি ব্যাচ কোথা থেকে এসে কোথায় গেল?|not captured (supplier lot)|stock|trace,lot,ট্রেস
84|quality|C|-|Finished goods distribution by outlet and batch|শাখা ও ব্যাচ অনুযায়ী তৈরি মাল বণ্টন|Which outlet got which batch?|কোন শাখা কোন ব্যাচ পেল?|stock_transfers, ledger|stock|distribution,বণ্টন
85|quality|U|-|Recall report|রিকল রিপোর্ট|Which customers or shops got a bad batch?|খারাপ ব্যাচ কোন দোকান বা গ্রাহক পেয়েছে?|not captured (no recall record)|quality|recall,রিকল
86|quality|I|report/q2_hygiene|Hygiene checklist report|পরিচ্ছন্নতা চেকলিস্ট রিপোর্ট|Were the hygiene checks done?|পরিচ্ছন্নতার চেক কি হয়েছে?|forms 14-1, 05-1|quality|hygiene,clean,পরিচ্ছন্নতা
87|quality|I|report/q1_fridge_temp|Fridge temperature log|ফ্রিজের তাপমাত্রা লগ|Were the fridges in range?|ফ্রিজ কি সঠিক তাপমাত্রায় ছিল?|fridge sheet|quality|fridge,temperature,ফ্রিজ,তাপমাত্রা
88|quality|I|report/q3_complaints|Customer complaints|গ্রাহকের অভিযোগ|What did customers complain about?|গ্রাহক কী নিয়ে অভিযোগ করেছে?|form 20-3|quality|complaint,অভিযোগ
89|quality|C|stockx|Quality inspection and rejection|মান পরিদর্শন ও বাতিল|What was rejected at receipt?|গ্রহণের সময় কী বাতিল হলো?|qc_records|quality|qc,inspection,reject,মান
90|purchase|I|report/purchases_by_supplier|Purchase summary|ক্রয়ের সারসংক্ষেপ|How much did we buy in total?|মোট কত কেনা হলো?|purchase_bills|purch|purchase,buy,ক্রয়,কেনা
91|purchase|I|report/purchases_by_supplier|Purchases by supplier|সরবরাহকারী অনুযায়ী ক্রয়|Whom do we buy from, how much?|কার কাছ থেকে কত কিনি?|purchase_bills|purch|supplier,সরবরাহকারী
92|purchase|C|report/p2_rate_trend|Purchase value by item|আইটেম অনুযায়ী ক্রয়মূল্য|What do we spend on each item?|প্রতিটি আইটেমে কত খরচ করি?|purchase_lines|purch|item,আইটেম
93|purchase|I|report/p2_rate_trend|Purchase price trend|ক্রয়দামের ধারা|Which input got dearer?|কোন কাঁচামাল দামি হলো?|purchase_lines|purch|price trend,rate,দাম
94|purchase|C|report/p4_supplier_score|Supplier scorecard|সরবরাহকারীর স্কোরকার্ড|Which supplier is reliable?|কোন সরবরাহকারী নির্ভরযোগ্য?|forms 06-3, 04-1, 06-4|purch|scorecard,reliable
95|purchase|I|report/p5_po_match|Purchase orders and open POs|ক্রয় অর্ডার ও খোলা PO|Which POs are still open?|কোন PO এখনও খোলা?|form 06-3|purch|po,order,অর্ডার
96|purchase|I|report/p5_po_match|PO, GRN and bill match|PO, GRN ও বিল মিল|Do order, receipt and bill agree?|অর্ডার, গ্রহণ আর বিল কি মেলে?|forms 06-3, 04-1, 06-4|purch|match,grn,মিল
97|purchase|I|report/p5_po_match|PO delivery status|PO ডেলিভারির অবস্থা|Which deliveries are late?|কোন ডেলিভারি দেরি?|form 06-3|purch|late,delivery,দেরি
98|purchase|C|report/supplier_ageing|Supplier payables ageing|সরবরাহকারীর পাওনার বয়স|How much do we owe, since when?|কত পাওনা, কত দিন ধরে?|purchase_bills, supplier_payments|purch|payable,ageing,owe,পাওনা,বাকি
99|purchase|I|payables|Supplier ledger|সরবরাহকারীর খাতা|What is the full account with one supplier?|এক সরবরাহকারীর পুরো হিসাব কী?|supplier_ledger|purch|ledger,খাতা
100|purchase|C|report/purchases_by_supplier|Purchase returns|ক্রয় ফেরত|What did we send back?|কী ফেরত দিয়েছি?|purchase_bills (return)|purch|return,ফেরত
101|purchase|C|report/p2_rate_trend|Price variance against the agreed price|চুক্তির দামের সাথে পার্থক্য|Did a supplier charge more than agreed?|সরবরাহকারী কি চুক্তির চেয়ে বেশি নিল?|not captured (no agreed price)|purch|variance,agreed
102|purchase|I|report/p4_supplier_score|Supplier delivery performance|সরবরাহকারীর ডেলিভারি কর্মক্ষমতা|Who delivers late?|কে দেরিতে দেয়?|forms 06-3, 06-4|purch|delivery,performance
103|purchase|C|report/p4_supplier_score|Supplier rejection rate|সরবরাহকারীর বাতিলের হার|How much of a supplier's goods is rejected?|সরবরাহকারীর কত মাল বাতিল হয়?|qc_records|purch|rejection,reject
104|purchase|U|-|Preferred and alternative suppliers|পছন্দের ও বিকল্প সরবরাহকারী|Who else can supply this item?|এই আইটেম আর কে দিতে পারে?|not captured (no item_suppliers)|purch|alternative,preferred,বিকল্প
'''

# audit flags (defect notes) shown as a small "known issue" line; text from REPORTS_AUDIT_1 / 2
NOTES = {
    2: 'D1b: expected drawer cash ignores cash refunds', 3: 'D3: net profit leaves out losses until the profit switch is on', 4: 'D3: net profit leaves out losses until the profit switch is on',
    11: 'D1: engine-1 sales reports ignore returns', 12: 'D1', 13: 'D1', 14: 'D1, D2', 15: 'D1, D2', 16: 'D1', 17: 'D1', 19: 'D1', 31: 'D3', 37: 'D2',
    33: 'D5: actual yield is never captured, actual cost equals standard', 43: 'D5, D6', 44: 'D4: shows 0.00 percent because actual is the recipe itself', 45: 'D5: run yield is not captured',
    69: 'three expiry thresholds exist', 94: 'prints 0 when the paper forms were not used', 98: 'shows 0.00 overdue when credit days are empty', 57: 'drops lines with no cost without saying how many',
}

STATUS = {'I': 'implemented', 'C': 'incomplete', 'U': 'unavailable', 'V': 'unverified'}

# ---- word lists for the question parser (web/reporthub_parse.js reads them). No business number; heads are codes of the option lists / cost types. ----
PARSER = {
    'heads': [
        {'key': 'staff_meal', 'label': {'bn': 'স্টাফের খাবার / নাস্তা', 'en': 'Staff meals / snacks'}, 'heads': ['staff_meal'], 'sensitive': True,
         'en': ['meal', 'meals', 'lunch', 'dinner', 'snack', 'snacks', 'tiffin', 'food', 'tea'], 'bn': ['খাবার', 'নাস্তা', 'নাশতা', 'দুপুরের', 'টিফিন', 'খানা', 'চায়ের']},
        {'key': 'electricity', 'label': {'bn': 'বিদ্যুৎ বিল', 'en': 'Electricity'}, 'heads': ['electricity'], 'utility': ['electricity'],
         'en': ['electricity', 'electric', 'electrical', 'power bill', 'current bill', 'pdb', 'desco', 'dpdc', 'reb'], 'bn': ['বিদ্যুৎ', 'বিদ্যুত', 'কারেন্ট', 'ইলেকট্রিক', 'বিদ্যুতের']},
        {'key': 'gas', 'label': {'bn': 'গ্যাস বিল', 'en': 'Gas'}, 'heads': ['gas'], 'utility': ['gas'], 'en': ['gas', 'lpg', 'cylinder'], 'bn': ['গ্যাস', 'সিলিন্ডার']},
        {'key': 'water', 'label': {'bn': 'পানির বিল', 'en': 'Water'}, 'heads': ['water'], 'utility': ['water'], 'en': ['water', 'wasa'], 'bn': ['পানি', 'ওয়াসা']},
        {'key': 'internet', 'label': {'bn': 'ইন্টারনেট', 'en': 'Internet'}, 'heads': ['internet'], 'utility': ['internet'], 'en': ['internet', 'wifi', 'broadband'], 'bn': ['ইন্টারনেট', 'ওয়াইফাই']},
        {'key': 'rent', 'label': {'bn': 'ভাড়া (বাড়ি/দোকান)', 'en': 'Rent'}, 'heads': ['rent'], 'utility': ['rent'], 'en': ['rent', 'rental', 'lease'], 'bn': ['বাড়িভাড়া', 'দোকান ভাড়া', 'দোকানভাড়া', 'ভাড়া'], 'ambiguous_with': 'transport'},
        {'key': 'transport', 'label': {'bn': 'যাতায়াত / পরিবহন', 'en': 'Transport'}, 'heads': ['transport'], 'en': ['transport', 'rickshaw', 'van', 'fare', 'delivery cost', 'carrying', 'travel'], 'bn': ['যাতায়াত', 'পরিবহন', 'রিকশা', 'ভ্যান', 'গাড়িভাড়া', 'ভাড়া'], 'ambiguous_with': 'rent'},
        {'key': 'repair', 'label': {'bn': 'মেরামত', 'en': 'Repairs'}, 'heads': ['repair', 'machine_repair'], 'utility': ['machine_repair'], 'en': ['repair', 'repairs', 'maintenance', 'fix', 'mechanic'], 'bn': ['মেরামত', 'রক্ষণাবেক্ষণ', 'মিস্ত্রি']},
        {'key': 'hospitality', 'label': {'bn': 'আপ্যায়ন', 'en': 'Customer hospitality'}, 'heads': ['hospitality'], 'en': ['hospitality', 'guest', 'guests', 'entertain'], 'bn': ['আপ্যায়ন', 'মেহমান', 'অতিথি']},
        {'key': 'labour', 'label': {'bn': 'অস্থায়ী শ্রমিকের মজুরি', 'en': 'Temporary labour wages'}, 'heads': ['labour'], 'sensitive': True, 'en': ['labour', 'labor', 'daily wage', 'temporary worker'], 'bn': ['শ্রমিক', 'দৈনিক মজুরি', 'মজুরি']},
        {'key': 'marketing', 'label': {'bn': 'মার্কেটিং', 'en': 'Marketing'}, 'heads': ['marketing'], 'en': ['marketing', 'advertising', 'ad', 'ads', 'boost', 'promotion', 'banner', 'leaflet'], 'bn': ['মার্কেটিং', 'বিজ্ঞাপন', 'প্রচার', 'বুস্ট']},
        {'key': 'sourcing', 'label': {'bn': 'বাইরের সোর্সিং', 'en': 'Outside-sourced goods'}, 'heads': ['sourcing'], 'en': ['sourcing', 'outside goods', 'outsourced'], 'bn': ['সোর্সিং', 'বাইরের মাল']},
    ],
    # kinds of money out: words that pick the source kinds (staff pay words imply the payroll right)
    'kinds': [
        {'key': 'salary', 'kinds': ['salary'], 'sensitive': True, 'en': ['salary', 'salaries', 'wage', 'wages', 'payroll', 'pay slip'], 'bn': ['বেতন', 'মাইনে', 'বেতনের']},
        {'key': 'advance', 'kinds': ['advance'], 'sensitive': True, 'en': ['advance', 'advances', 'loan to staff'], 'bn': ['অগ্রিম', 'অ্যাডভান্স', 'এডভান্স']},
        {'key': 'purchase', 'kinds': ['purchase'], 'en': ['purchase', 'purchases', 'bought', 'buying', 'bill from supplier'], 'bn': ['ক্রয়', 'কেনা', 'কিনেছি', 'কিনলাম']},
        {'key': 'supplier_payment', 'kinds': ['supplier_payment'], 'en': ['paid to supplier', 'supplier payment', 'payment to supplier'], 'bn': ['সরবরাহকারীকে পরিশোধ', 'মহাজনকে দিয়েছি']},
        {'key': 'refund', 'kinds': ['customer_refund'], 'en': ['refund', 'refunds', 'refunded'], 'bn': ['রিফান্ড', 'ফেরত দিয়েছি']},
        {'key': 'expense', 'kinds': ['quick_expense', 'expense_voucher'], 'en': ['expense', 'expenses', 'spent', 'spend', 'spending', 'cost'], 'bn': ['খরচ', 'ব্যয়', 'খরচা']},
    ],
    'person_words': {'staff': {'en': ['staff', 'employee', 'worker', 'karigor', 'cook', 'cashier', 'salesman', 'salesperson'], 'bn': ['কর্মী', 'স্টাফ', 'কারিগর', 'কর্মচারী', 'শ্রমিক', 'ক্যাশিয়ার']},
                     'supplier': {'en': ['supplier', 'vendor', 'seller'], 'bn': ['সরবরাহকারী', 'মহাজন', 'সাপ্লায়ার', 'বিক্রেতা']},
                     'customer': {'en': ['customer', 'client', 'buyer'], 'bn': ['গ্রাহক', 'কাস্টমার', 'ক্রেতা']}},
    'place_words': {'factory': {'en': ['factory'], 'bn': ['কারখানা', 'ফ্যাক্টরি']}, 'branch': {'en': ['branch', 'outlet', 'shop', 'showroom'], 'bn': ['শাখা', 'দোকান', 'শোরুম', 'আউটলেট']}, 'godown': {'en': ['godown', 'store', 'warehouse'], 'bn': ['গোডাউন', 'গুদাম']}},
    'ordinals': {'en': {'1st': 1, 'first': 1, '2nd': 2, 'second': 2, '3rd': 3, 'third': 3}, 'bn': {'প্রথম': 1, 'দ্বিতীয়': 2, 'তৃতীয়': 3}},
    'num_words': {'en': {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12, 'a': 1, 'an': 1},
                  'bn': {'এক': 1, 'দুই': 2, 'দু': 2, 'তিন': 3, 'চার': 4, 'পাঁচ': 5, 'ছয়': 6, 'ছ': 6, 'সাত': 7, 'আট': 8, 'নয়': 9, 'দশ': 10, 'এগারো': 11, 'বারো': 12}},
    'months': {'en': ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'],
               'en_short': ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'],
               'bn': ['জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর']},
    'period_words': {
        'last': {'en': ['last', 'past', 'previous', 'prev'], 'bn': ['গত', 'শেষ', 'বিগত']}, 'this': {'en': ['this', 'current'], 'bn': ['এই', 'চলতি', 'এ ']},
        'day': {'en': ['day', 'days'], 'bn': ['দিন']}, 'week': {'en': ['week', 'weeks'], 'bn': ['সপ্তাহ', 'হপ্তা']}, 'month': {'en': ['month', 'months'], 'bn': ['মাস']}, 'year': {'en': ['year', 'years'], 'bn': ['বছর', 'বৎসর']},
        'today': {'en': ['today'], 'bn': ['আজ', 'আজকে']}, 'yesterday': {'en': ['yesterday'], 'bn': ['গতকাল', 'কাল']}, 'fiscal': {'en': ['fiscal', 'financial year'], 'bn': ['অর্থবছর', 'অর্থ বছর']},
        'since': {'en': ['since', 'from'], 'bn': ['থেকে']}, 'ago': {'en': ['ago'], 'bn': ['আগে']},
    },
    'measures': {'total': {'en': ['how much', 'total', 'sum', 'amount', 'paid', 'spent', 'cost'], 'bn': ['কত', 'মোট', 'কত টাকা', 'দিয়েছি', 'খরচ']},
                 'count': {'en': ['how many', 'how often', 'count', 'number of', 'times'], 'bn': ['কয়টা', 'কয়বার', 'কতবার', 'কতগুলো', 'সংখ্যা']},
                 'list': {'en': ['list', 'show', 'details', 'every', 'all'], 'bn': ['তালিকা', 'দেখাও', 'দেখান', 'সব']},
                 'happened': {'en': ['what happened', 'replay', 'what went on', 'story of'], 'bn': ['কী হয়েছিল', 'কি হয়েছিল', 'কী ঘটেছিল', 'কি ঘটেছিল', 'কী হলো', 'কি হলো']},
                 'compare': {'en': ['compare', 'versus', 'vs', 'changed', 'difference between', 'why did'], 'bn': ['তুলনা', 'বনাম', 'বদলেছে', 'কেন বাড়ল', 'কেন কমল', 'পার্থক্য']}},
    'stopwords': {'en': ['the', 'of', 'for', 'in', 'on', 'at', 'to', 'was', 'were', 'is', 'are', 'did', 'do', 'we', 'i', 'my', 'me', 'our', 'much', 'many', 'what', 'how', 'when', 'where', 'who', 'which', 'a', 'an', 'and', 'or', 'by', 'with', 'from', 'it', 'that', 'this', 'last', 'past', 'month', 'months', 'year', 'years', 'day', 'days', 'week', 'weeks', 'bill', 'bills', 'paid', 'pay', 'spend', 'spent', 'been', 'have', 'has', 'had', 'give', 'gave', 'given', 'show', 'tell', 'please', 'total', 'amount', 'all', 'one', 'only', 's', 'his', 'her', 'their', 'its', 'ago', 'than', 'then', 'cost', 'costs', 'expense', 'expenses', 'money', 'taka', 'tk', 'member', 'members', 'person', 'people', 'someone', 'anyone', 'any', 'each', 'every', 'per', 'branch', 'outlet', 'shop', 'showroom', 'factory', 'godown', 'store', 'also', 'so', 'if', 'be', 'can', 'could', 'should', 'would', 'there', 'about', 'during', 'between', 'over', 'into'],
                  'bn': ['কত', 'টাকা', 'মোট', 'গত', 'এই', 'মাস', 'মাসে', 'বছর', 'বছরে', 'দিন', 'দিনে', 'সপ্তাহ', 'কী', 'কি', 'কেন', 'কবে', 'কোথায়', 'কে', 'একজন', 'এক', 'জন', 'আমি', 'আমরা', 'আমার', 'দিয়েছি', 'দিলাম', 'দেওয়া', 'হয়েছে', 'হয়েছিল', 'ছিল', 'বিল', 'খরচ', 'খরচা', 'ব্যয়', 'জন্য', 'থেকে', 'পর্যন্ত', 'এর', 'ও', 'আর', 'বা', 'যত', 'সব', 'দেখাও', 'দেখান', 'বলো', 'বলুন', 'পরিশোধ', 'করেছি', 'করেছে', 'করা', 'টা', 'টি', 'বিলের', 'জনের', 'কোন', 'কোনো', 'কিছু', 'মধ্যে', 'প্রতি', 'আছে', 'ছিলো', 'হলো', 'হয়', 'দিয়েছিলাম', 'দিয়েছিল', 'কর', 'শাখার', 'দোকানের', 'বাবদ', 'বিষয়ে', 'ব্যাপারে', 'নিয়ে', 'হিসেবে', 'হিসাবে', 'শাখায়', 'দোকানে', 'খরচে', 'বিলে']},
}

# phrase -> report number: used when a question is about a report that already exists (the parser also scores names and keywords)
INTENT_HINTS = [
    {'en': ['profit', 'loss', 'p&l'], 'bn': ['লাভ', 'ক্ষতি', 'মুনাফা'], 'reports': [3, 4, 5]},
    {'en': ['sales', 'sold', 'revenue'], 'bn': ['বিক্রি', 'বিক্রয়'], 'reports': [11, 12, 14]},
    {'en': ['stock', 'inventory'], 'bn': ['স্টক', 'মজুত'], 'reports': [56, 58, 63]},
    {'en': ['wastage', 'waste'], 'bn': ['অপচয়', 'নষ্ট'], 'reports': [76, 50]},
    {'en': ['due', 'owe', 'payable'], 'bn': ['বাকি', 'পাওনা'], 'reports': [98, 99]},
    {'en': ['discount'], 'bn': ['ডিসকাউন্ট', 'ছাড়'], 'reports': [20, 37]},
    {'en': ['expiry', 'expire'], 'bn': ['মেয়াদ'], 'reports': [69]},
]


def split_seed():
    rows = []
    for line in SEED.strip().splitlines():
        p = line.split('|')
        if len(p) != 11:
            raise SystemExit('seed row has %d fields: %r' % (len(p), line[:80]))
        no, area, st, route, en, bn, qen, qbn, src, gr, kw = p
        rows.append({'no': int(no), 'area': area, 'status': STATUS[st], 'route': None if route == '-' else route, 'name_en': en, 'name_bn': bn, 'question_en': qen, 'question_bn': qbn,
                     'source': src, 'grant': GRANTS.get(gr, gr), 'kw': [k.strip() for k in kw.split(',') if k.strip()]})
    return rows


def section_of(no):
    for n, en, bn, a, b in SECTIONS:
        if a is not None and a <= no <= b:
            return n
    return None


def build_row(r):
    no = r['no']
    sec = section_of(no)
    route = r.get('route')
    return {
        'no': no, 'id': 'r%03d' % no, 'section': sec, 'area': r.get('area') or 'unaudited',
        'name': {'bn': r['name_bn'], 'en': r['name_en'], 'mix': '%s (%s)' % (r['name_en'], r['name_bn'])},
        'question': {'bn': r['question_bn'], 'en': r['question_en'], 'mix': r['question_bn']},
        'status': r['status'], 'route': route, 'planned': route is None and r['status'] in ('unavailable', 'incomplete', 'unaudited'),
        'source': r.get('source') or '', 'grant': r.get('grant') or '', 'kw': r.get('kw', []), 'note': r.get('note') or NOTES.get(no, ''),
    }


def placeholder(no):
    return {'no': no, 'id': 'r%03d' % no, 'section': None, 'area': 'unaudited',
            'name': {'bn': 'রিপোর্ট নং %d (এখনও যাচাই হয়নি)' % no, 'en': 'Report #%d (not audited yet)' % no, 'mix': 'Report #%d (যাচাই হয়নি)' % no},
            'question': {'bn': 'অডিট ৩ আসার পর এই রিপোর্টের নাম ও প্রশ্ন বসবে।', 'en': 'The name and question appear when audit 3 is merged.', 'mix': 'Audit 3 merge হলে নাম ও প্রশ্ন বসবে।'},
            'status': 'unaudited', 'route': None, 'planned': True, 'source': '', 'grant': '', 'kw': [], 'note': ''}


def parse_audit_table(text):
    """Pipe tables in markdown: the first row of a table is the header. Returns a list of dicts keyed by header names."""
    out, head = [], None
    for line in text.splitlines():
        s = line.strip()
        if not s.startswith('|'):
            head = None
            continue
        cells = [c.strip().strip('`') for c in s.strip('|').split('|')]
        if all(re.fullmatch(r':?-{2,}:?', c) for c in cells if c):
            continue
        if head is None:
            head = [c.lower().replace(' ', '_') for c in cells]
            continue
        out.append(dict(zip(head, cells)))
    return out


def merge_file(rows, path):
    if path.endswith('.csv'):
        with open(path, encoding='utf-8') as f:
            tab = [{(k or '').lower(): (v or '').strip() for k, v in r.items()} for r in csv.DictReader(f)]
    else:
        tab = parse_audit_table(open(path, encoding='utf-8').read())
    n = 0
    for t in tab:
        m = re.match(r'^\D*(\d{1,3})$', t.get('no', '') or t.get('#', ''))
        if not m:
            continue
        no = int(m.group(1))
        if not 1 <= no <= TOTAL:
            continue
        r = rows.setdefault(no, placeholder_row(no))
        for k_in, k_out in (('name_en', 'name_en'), ('name_bn', 'name_bn'), ('question_en', 'question_en'), ('question_bn', 'question_bn'), ('source', 'source'), ('grant', 'grant'), ('area', 'area'), ('note', 'note')):
            if t.get(k_in):
                r[k_out] = t[k_in]
        if t.get('status'):
            s = t['status'].lower()
            if s not in ('implemented', 'incomplete', 'unavailable', 'unverified'):
                raise SystemExit('%s: report %d has status %r' % (path, no, t['status']))
            r['status'] = s
        if t.get('route'):
            r['route'] = None if t['route'].lower() in ('planned', '-') else t['route']
        if t.get('section'):
            r['section_no'] = int(re.sub(r'\D', '', t['section']) or 0) or None
        if t.get('kw'):
            r['kw'] = [k.strip() for k in re.split(r'[,;]', t['kw']) if k.strip()]
        n += 1
    return n


def placeholder_row(no):
    return {'no': no, 'area': 'unaudited', 'status': 'unaudited', 'route': None, 'name_en': 'Report #%d (not audited yet)' % no, 'name_bn': 'রিপোর্ট নং %d (এখনও যাচাই হয়নি)' % no,
            'question_en': 'The name and question appear when audit 3 is merged.', 'question_bn': 'অডিট ৩ আসার পর এই রিপোর্টের নাম ও প্রশ্ন বসবে।', 'source': '', 'grant': '', 'kw': []}


def build(merge_files=(), master=None):
    rows = {r['no']: r for r in split_seed()}
    for no in range(1, TOTAL + 1):
        rows.setdefault(no, placeholder_row(no))
    merged = 0
    for p in merge_files:
        merged += merge_file(rows, p)
    if master:
        with open(master, encoding='utf-8') as f:
            for t in csv.DictReader(f):
                no = int(re.sub(r'\D', '', t.get('no', '')) or 0)
                if no in rows:
                    for k in ('name_bn', 'name_en'):
                        if (t.get(k) or '').strip():
                            rows[no][k] = t[k].strip()
    reports = []
    for no in range(1, TOTAL + 1):
        r = rows[no]
        b = build_row(r)
        if r.get('section_no'):
            b['section'] = r['section_no']
        reports.append(b)
    counts = {}
    for b in reports:
        counts[b['status']] = counts.get(b['status'], 0) + 1
    sections = []
    for n, en, bn, a, z in SECTIONS:
        ids = [b['no'] for b in reports if b['section'] == n]
        sc = {}
        for b in reports:
            if b['section'] == n:
                sc[b['status']] = sc.get(b['status'], 0) + 1
        sections.append({'no': n, 'id': 's%02d' % n, 'name': {'bn': bn, 'en': en, 'mix': '%s (%s)' % (en, bn)}, 'range': [a, z] if a else None, 'count': len(ids), 'status_counts': sc})
    return {
        'version': 1, 'generated_by': 'tools/build_report_registry.py', 'total': TOTAL, 'status_counts': counts,
        'note': 'Reports 1-104 come from audits 1 and 2 (names are the audits\' wording; the owner\'s master list may word them differently - use --master). Reports 105-193 are unaudited until audit 3 is merged.',
        'areas': AREAS, 'sections': sections, 'reports': reports, 'parser': PARSER, 'intent_hints': INTENT_HINTS,
    }


def dump(obj):
    return json.dumps(obj, ensure_ascii=False, indent=1, sort_keys=False) + '\n'


def main(argv):
    merge, master, check = [], None, False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--merge':
            merge.append(argv[i + 1]); i += 2
        elif a == '--master':
            master = argv[i + 1]; i += 2
        elif a == '--check':
            check = True; i += 1
        else:
            raise SystemExit(__doc__)
    if os.path.isdir(MERGE_DIR):
        merge = sorted(os.path.join(MERGE_DIR, f) for f in os.listdir(MERGE_DIR) if f.endswith(('.md', '.csv'))) + merge
    text = dump(build(merge, master))
    if check:
        cur = open(OUT, encoding='utf-8').read() if os.path.exists(OUT) else ''
        print('OK' if cur == text else 'DIFFERENT: run python3 tools/build_report_registry.py')
        return 0 if cur == text else 1
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write(text)
    d = json.loads(text)
    print('wrote %s: %d reports, %s' % (os.path.relpath(OUT, ROOT), len(d['reports']), d['status_counts']))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
