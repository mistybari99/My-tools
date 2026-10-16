# ইসলামিয়া মিষ্টি ঘর — কাল্পনিক ভবিষ্যৎ সিস্টেমের ডেমো ভাবনা

**এই ফাইল কী:** একটি ধরে নেওয়া (imagined) সিস্টেম। এখানে ধরা হয়েছে যে নিচের সব গ্যাপ বন্ধ হয়ে গেছে। এটি বর্তমান কোডের বর্ণনা নয়, আর বর্তমান কোড যাচাই করা হয়নি। সব নাম কাল্পনিক। সব অনুমতি আছে ধরে নেওয়া। টাকার অঙ্ক ডেমো।

**যা ধরে নেওয়া হয়েছে (গ্যাপ বন্ধ):**
1. বেতন ও অগ্রিম স্বয়ংক্রিয়ভাবে জার্নালে যায়।
2. জার্নাল ভরা থাকে, লেজার থেকে ব্যালেন্স শিট সরাসরি হয়।
3. শুরুর ব্যালেন্সের জন্য একটি "Opening Balance" স্ক্রিন আছে।
4. হাবের নগদ ঘাটতির জন্য "Cash Short" হিসাব আছে।
5. গ্রাহক অগ্রিমের জন্য "Customer Advance" দায় হিসাব আছে।
6. পথে ঘাটতির জন্য "Transit Short" লেখা-বন্ধ ও দাবির কাজ আছে।
7. মালিকের মূলধন ও শুরুর ব্যালেন্স জার্নাল এন্ট্রি হিসেবে যায়।
8. Partner capital মডেল করা আছে।
9. bKash, Nagad, Rocket প্রতিটি আলাদা "Wallet" হিসাব হিসেবে দেখায়।
10. দুধ, ছানা, প্যাকিং স্টক আইটেম হিসেবে আছে, তাই উৎপাদন খরচ পূর্ণ।

---

## ১. স্ক্রিন ও অপশনের তালিকা (ধরে নেওয়া)

| স্ক্রিন (English) | কাজ | অপশন | কে ব্যবহার করে |
|---|---|---|---|
| Opening Balance | প্রথম দিনের স্টক, নগদ, বাকি, দেনা, মূলধন দেওয়া | Stock, Cash, Wallet, Dues, Payables, Owner Capital, Post | Owner, Management |
| Daily Sheet (14-1) | শোরুমের দিনের শিট | Opening Float, Receipts, Cash Count, Closing Stock, Checklist, Submit | Showroom Manager |
| POS Sale | বিক্রি | Item, Qty, Price, Payment (Cash / bKash / Nagad / Rocket / Card / Due), Mobile, Discount, Save, Print | Salesperson, Cashier |
| Sale Return | ফেরত | Original Sale, Items, Reason, Refund Mode (Cash / Wallet / Due Reduce) | Salesperson with grant |
| Customer Advance | গ্রাহক অগ্রিম | Customer, Amount, Mode, Order No | Party Coordinator |
| Stock: Transfer | মাল পাঠানো | From, To, Item, Qty, Note | Storekeeper, Showroom Manager |
| Stock: Receive | মাল গ্রহণ | Transit List, Received Qty, Short Reason | Receiver |
| Transit Short | পথে ঘাটতি | Auto row, Write-off, Claim to Carrier, Owner Decision | Owner, Storekeeper |
| Stock: Issue | কারখানায় মাল দেওয়া | Item, Qty, To Factory | Storekeeper |
| Recipes & Production | উৎপাদন | Recipe, Batches, Actual Yield, Expiry, Ingredients Out | Factory In-charge |
| Stock Count | গণনা | Count Sheet, Counter, Witness, Variance Reason | Counter (not Storekeeper) |
| Purchase Bill | ক্রয় বিল | Supplier, Bill No, Items, Post | Purchasing |
| Cash Handover (10-1) | হাবে নগদ জমা | Sender Count, Carrier, Hub Count, Difference, Reason | Showroom Manager, Cash Controller |
| Digital Register (10-3) | bKash/Nagad/Rocket মেলানো | Wallet, Phone Total, Machine Total, Difference | Cash Controller |
| Quick Expense | দ্রুত খরচ | Head, Amount, Mode, Receipt | Showroom Manager, Cash Controller |
| Payroll Run | বেতন | Month, Employees, Deduction, Advance Recovery, Post | HR, Owner |
| Partner Capital | অংশীদার মূলধন | Partner, Amount, Share %, Post | Owner |
| Journal | জার্নাল (পড়া) | Date, Account, Debit, Credit | Owner, Management |
| Balance Sheet | ব্যালেন্স শিট | Date, Print | Owner, Management |
| Stock Ledger | স্টক লেজার | Place, Item, Date, In, Out, Balance | Storekeeper, Owner |
| Exceptions | ব্যতিক্রম | Flag, Release, Resolve, Note | Owner, Management |

---

## ২. শুরুর দিন (Opening Balance)

**ঘটনা:** মালিক Karim ১ অক্টোবর শুরু করছেন। তিনি Opening Balance স্ক্রিনে যান।

- **Stock:** godown-এ সুগার ৬০ কেজি (৯০/কেজি), ময়দা ৫০ কেজি (৬০/কেজি), মিষ্টি A ৩০ কেজি (৪৫০/কেজি)। Post।
- **Cash:** হাবে নগদ ১০,০০০। Post।
- **Wallet:** bKash ৩,০০০, Nagad ২,০০০, Rocket ১,০০০। প্রতিটি আলাদা হিসাব।
- **Owner Capital:** Karim ৫০,০০০।
- **Partner Capital:** Partner Rafiq ২০,০০০, Share ২০%। Partner Capital স্ক্রিনে Post।

**সিস্টেম:** জার্নালে যায়:
- Dr Stock ৫,৪০০ + ... ; Dr Cash 10,000 ; Dr bKash 3,000 ; Dr Nagad 2,000 ; Dr Rocket 1,000 ; Cr Owner Capital 50,000 ; Cr Partner Capital 20,000 ।

**নেগেটিভ:** Karim ভুলে Cash ১০,০০০ এর বদলে ১,০০০০০ লেখেন। **ফলাফল:** Opening Balance আগে Dr = Cr মেলাতে বলে; না মিললে Post আটকায়।

---

## ৩. একটি পূর্ণ দিন (ঘটনা ক্রমে)

### ০৭:০০ — godown (Jamal, Storekeeper)
- Stock: Transfer স্ক্রিন খুলে "In Transit" তালিকা দেখেন। খালি।

### ০৭:৩০ — godown (Jamal) — মাল আসা
- Hasan (Purchasing) আগের দিন Purchase Bill দিয়েছেন: সুগার ৪০ কেজি @ ৯২।
- Jamal Stock: Receive খোলেন। Bill নির্বাচন, গোনা ৪০, মান OK। Post।
- **জার্নাল:** Dr Stock ৩,৬৮০ ; Cr Supplier Payable ৩,৬৮০ ।
- **নেগেটিভ:** Jamal ৩৮ কেজি লিখলেন। **ফলাফল:** Transit Short ২ কেজি হলুদ, Owner-এর কাছে যায়।

### ০৮:৩০ — godown → main (Jamal, Selim)
- Stock: Issue। সুগার ২০ কেজি, To: main (factory)। Selim সই (কাগজ, Form 04-2)।
- **জার্নাল:** Dr WIP (Factory) ১,৮০০ ; Cr Stock ১,৮০০ ।

### ০৮:৪৫ — godown → cake_factory (Jamal, Mitu)
- Stock: Issue ময়দা ১৫ কেজি।

### ০৯:০০ — main (Selim) — উৎপাদন
- Recipes & Production → "মিষ্টি A", ২ ব্যাচ।
- Ingredients Out: সুগার ২০ কেজি (উপরের ইস্যু থেকে), দুধ ১০ লিটার, প্যাকিং বক্স ২০ (নতুন আইটেম)।
- Actual Yield ৯.৬ কেজি (Expected ১০)। ৪% তফাত।
- **জার্নাল:** Dr Finished Goods ; Cr WIP ; Dr Yield Variance (৪%)। উৎপাদন খরচে দুধ ও প্যাকিং যোগ হয়।
- **নেগেটিভ:** Selim দুধ লিখতে ভুলে গেলেন। **ফলাফল:** Ingredient missing ব্যাচ আটকায় (Recipe-এ দুধ বাধ্যতামূলক)।

### ০৯:২০ — main (Selim)
- Form 05-1 Daily Factory Sheet জমা। Salma পরে অনুমোদন।

### ০৯:৪০ — cake_factory (Mitu)
- কেক B ৬ কেজি। স্টক IN।

### ১০:০০ — godown (Jamal)
- Transfer: মিষ্টি A ১০ কেজি → mishti_bari। পথে।

### ১০:১৫ — branch2 (Shirin)
- Receive: main থেকে মিষ্টি A ৫ কেজি। ৫ লেখেন। স্টক IN।

### ১০:৩০ — main (Rahim, Showroom Manager) — Daily Sheet
- Opening Float ২,০০০। Cash Count স্ক্রিন। মেলে।

### ১১:০০ — main (Nasrin, Salesperson) — POS
- মিষ্টি A ১.৫ কেজি × ৪৫০ = ৬৭৫। Payment: Cash ৫০০ + bKash ১৭৫।
- **জার্নাল:** Dr Cash ৫০০ ; Dr bKash ১৭৫ ; Cr Sales ৬৭৫ ; Dr COGS ; Cr Stock ।
- **নেগেটিভ:** Nasrin বাকি বিক্রি করলেন মোবাইল ছাড়া। **ফলাফল:** Due আটকায়।

### ১১:৩০ — main (Nasrin) — বাকি
- মিষ্টি A ২ কেজি = ৯০০, Payment: Due। Customer মোবাইল দিতে হয়।

### ১২:০০ — main (Ruma, Party Coordinator) — গ্রাহক অগ্রিম
- Customer Advance ১,০০০ (Order 20-1)। Customer Advance স্ক্রিন।
- **জার্নাল:** Dr Cash ১,০০০ ; Cr Customer Advance ১,০০০ ।
- পরে শুক্রবার ৫ কেজি ডেলিভারি হলে Customer Advance-এর সাথে Sale মিলবে।

### ১২:৪৫ — main (intake_bot) — অনলাইন অর্ডার
- ২০-৬-এ একটি অনলাইন অর্ডার। Ruma পরে Sale-এর সাথে জুড়বেন।

### ১৩:০০ — al_cakes (Lipi)
- POS কেক B ১ কেজি নগদ।

### ১৩:১৫ — main (Nasrin) — বাকি আদায়
- গতকালের বাকি ৬০০ নগদ। **জার্নাল:** Dr Cash ৬০০ ; Cr Customer Receivable ৬০০ ।

### ১৪:০০ — mishti_bari (Ayesha)
- ১০ কেজি গ্রহণ, ১০ লেখেন।

### ১৫:০০ — mishti_bari (Ayesha) — পথে ঘাটতি
- দ্বিতীয় ১০ কেজির ট্রান্সফার, Ayesha ৯ লেখেন (পাঠানো ১০)।
- Transit Short ১ কেজি (মূল্য ৪৫০) হলুদ।
- **Owner-এর সিদ্ধান্ত:** Claim to Carrier (Sohel) না Write-off। ধরা হলো Claim।
- **জার্নাল:** Dr Receivable from Carrier ৪৫০ ; Cr Stock ৪৫০ ।
- **নেগেটিভ:** Sohel-এর নাম না দিলে Claim আটকায়।

### ১৬:০০ — main-হাব (Rahim → Sohel → Fatema) — নগদ হস্তান্তর
- Rahim ২৫,০০০ গোনেন। Sohel বহন করেন। Fatema গোনেন ২৪,৮০০।
- **Cash Short ২০০** লাল। কারণ লিখতে হবে। Fatema লিখলেন "গণনার ভুল"।
- Owner-এর সিদ্ধান্ত: Cash Short হিসাবে রাখা। **জার্নাল:** Dr Cash Short ২০০ ; Cr Cash ২০০ ।
- **নেগেটিভ:** কারণ খালি রাখলে Post আটকায়।

### ১৬:২০ — main-হাব (Fatema) — ডিজিটাল মেলানো
- 10-3 Digital Register: bKash ফোনে ৩,১৭৫, মেশিনে ৩,১৭৫। মেলে।
- Nagad ২,০০০ (ফোনে), Rocket ১,০০০ (ফোনে)। মেলে।

### ১৬:৩০ — main-হাব (Fatema) — নগদ অবস্থান ও বাকি
- 10-4 Cash Position: হাবে নগদ ২৩,০০০, সীমা ৫০,০০০। ঠিক আছে।
- 10-5 Receivable: মোট বাকি ও অগ্রিম ব্যালেন্স ledger-এর সাথে মেলে।

### ১৭:০০ — main (Rahim) — খরচ
- Quick Expense: চা ও ছোট মেরামত ৩৫০, Cash, রসিদ আছে।
- **জার্নাল:** Dr Expense ৩৫০ ; Cr Cash ৩৫০ ।
- **নেগেটিভ:** Rahim একই খরচ ১০-২-এ আবার লিখলেন। **ফলাফল:** ডুপ্লিকেট সন্দেহে ধরা পড়ে।

### ১৭:৩০ — al_cakes (Lipi) — শিফট
- 11-1 Shift Handover। রেকর্ড।

### ১৮:০০ — main (Salma, Management) — অনুমোদন
- 14-1 (Rahim), 10-2, 05-1 (Selim) অনুমোদন।
- **নেগেটিভ:** Salma নিজে যা বানিয়েছেন তা অনুমোদন চাইলেন। **ফলাফল:** Owner-এর অনুমতি নিতে হয় (owner_self_approve চালু থাকলে মালিক পারেন)।

### ১৮:৩০ — godown (Hasan গণক, Anwar সাক্ষী, Jamal গোনেন না)
- Stock: Count। ৫ আইটেম।
- সুগার: বই ৭৯, গোনা ৭৮, পার্থক্য ১ কেজি, কারণ "আর্দ্রতায় ওজন কম"। Owner অনুমোদন।
- **নেগেটিভ:** Jamal নিজে গুনতে চাইলেন। **ফলাফল:** আটকায়।

### ১৯:০০ — হেড অফিস (Hasan) — ক্রয়
- ০৬-১ Requisition: ময়দা ১০০ কেজি। ০৬-২ দুটো দর।
- কিছু নড়ে না।

### ১৯:২০ — main (Selim → Nazia) — রেসিপি বদল
- "মিষ্টি A" v2: সুগার ১৮ কেজি। Nazia অনুমোদন।
- **নেগেটিভ:** Selim নিজেই অনুমোদন চাইলেন। **ফলাফল:** আটকায়।

### ১৯:৩০ — হেড অফিস (Anwar) — বেতন ও হাজিরা
- Payroll Run: মাস অক্টোবর, ৩ জন কর্মী, মোট বেতন ৪৫,০০০, Advance Recovery ২,০০০।
- Post: **জার্নাল:** Dr Salary Expense ৪৫,০০০ ; Cr Cash/Bank ৪৩,০০০ ; Cr Advance Receivable ২,০০০ ।
- হাজিরা 02-1 জমা।

### ২০:০০ — সব জায়গা (Karim) — ব্যতিক্রম
- Exceptions তালিকা: পথে ঘাটতি (Claim), হাব Cash Short (২০০), গণনার সুগার (১ কেজি)। প্রতিটি নোট দিয়ে বন্ধ।

### ২০:২০ — প্রতি জায়গা (Rahim, Shirin, Ayesha, Lipi, Mitu, Jamal)
- Day Close। 14-1 অনুমোদিত। লাল নেই। দিন বন্ধ।

### ২০:৪০ — সব জায়গা (Karim) — রিপোর্ট
- Balance Sheet ও Journal মিলিয়ে দেখা হয়। (সংখ্যা নিচে)।

---

## ৪. নেগেটিভ কেস (সংক্ষেপ, ধরে নেওয়া আচরণ)

| # | ঘটনা | কে | সিস্টেমের প্রতিক্রিয়া |
|---|---|---|---|
| N1 | নিজের স্টক গোনা | Jamal | আটকায় |
| N2 | গণক ও সাক্ষী একই | Anwar | আটকায় |
| N3 | নিজের রেসিপি অনুমোদন | Selim | আটকায় |
| N4 | Cash Short-এর কারণ খালি | Fatema | আটকায় |
| N5 | পথে ঘাটতি, Carrier নাম খালি | Ayesha | Claim আটকায় |
| N6 | স্টক না থাকলে বিক্রি | Nasrin | সতর্কতা |
| N7 | মোবাইল ছাড়া বাকি | Nasrin | আটকায় |
| N8 | ছাড় সীমার বেশি | Tania | Salma-র অনুমোদন চাই |
| N9 | Opening Balance Dr ≠ Cr | Karim | Post আটকায় |
| N10 | দিন বন্ধের পর এন্ট্রি | Rahim | আটকায় |
| N11 | খরচ দুইবার | Rahim | ডুপ্লিকেট সন্দেহ |
| N12 | Carrier অনুমোদন চায় | Sohel | আটকায় |
| N13 | অফলাইন বিক্রি, সংযোগ নেই | Tania | Replay লগে থাকে, পরে যায় |
| N14 | বেতনে Advance-এর বেশি কাটা | Anwar | আটকায় |
| N15 | Recipe-এ দুধ নেই | Selim | ব্যাচ আটকায় |
| N16 | Bank Reconcile-এ mismatch | Fatema | পার্থক্য তালিকায় |

---

## ৫. ব্যবসায়িক অবস্থা (দিন শেষে, ডেমো সংখ্যা)

### স্টক লেজার (কেজি / পিস)

| জায়গা | আইটেম | শুরু | ইন | আউট | শেষ | কারণ |
|---|---|---|---|---|---|---|
| godown | সুগার | 60 | 40 | 20 (main) + 1 (গণনা) | 79 | ইন: ক্রয়; আউট: ইস্যু, গণনা |
| godown | ময়দা | 50 | 0 | 15 (cake_factory) | 35 | ইস্যু |
| godown | মিষ্টি A | 30 | 0 | 20 (mishti_bari) | 10 | দুইবার ১০ কেজি |
| godown | দুধ | 0 | 0 | 0 | 0 | ডেমো: উৎপাদনে ১০ লিটার ধরা হয়, শুরুর স্টক অনুমান |
| main | সুগার (factory) | 0 | 20 | 20 (উৎপাদন) | 0 | ইস্যু থেকে |
| main | মিষ্টি A | 0 | 9.6 | 1.5 + 2 (বিক্রি) + 5 (branch2 পাঠানো) | 1.1 | উৎপাদন ও বিক্রি |
| branch2 | মিষ্টি A | 0 | 5 | 2 (বিক্রি) | 3 | — |
| cake_factory | কেক B | 0 | 6 | 3 (al_cakes) | 3 | — |
| al_cakes | কেক B | 0 | 3 | 1 (বিক্রি) | 2 | — |
| mishti_bari | মিষ্টি A | 0 | 9 | 0 | 9 | ১ কেজি Transit Short (Claim) |
| পথে | মিষ্টি A | — | — | — | 1 | Claim pending |

> মন্তব্য: godown-এ মিষ্টি A ৩০ শুরু, ১০+১০ পাঠানো = ২০; বাকি ১০। main-এ মিষ্টি A উৎপাদন ৯.৬ ও branch2 থেকে ৫ — ডেমোতে main-এর প্রাথমিক মজুত ০ ধরা হয়েছে; পাঠানো ৫ main থেকে branch2-এ। সংখ্যা ইচ্ছাকৃতভাবে প্রাথমিক পর্যায়ের ডেমো।

### নগদ ও ডিজিটাল ওয়ালেট (৳)

| হিসাব | শুরু | জমা | খরচ/পাঠানো | শেষ |
|---|---|---|---|---|
| হাব নগদ (Cash) | 10,000 | 500 (Nasrin) + 600 (বাকি) + 1,000 (অগ্রিম) + 24,800 (হাব গণনা) | 350 (খরচ) + 200 (Cash Short) + 43,000 (বেতন) | ... |

> ডেমো নোট: হাব নগদ লেজার সরল রাখা হয়েছে। বেতন হাব থেকে গেছে বলে ধরা হয়েছে, তাই শেষ ব্যালেন্স ঋণাত্মক দেখাবে। **এটি বাস্তব প্রবাহ নয়**, শুধু ডেমো। ভালো হয় যদি বেতন bKash/bank থেকে যায়।

| ওয়ালেট | শুরু | জমা | শেষ |
|---|---|---|---|
| bKash | 3,000 | 175 (Nasrin) + 3,000 (ডিজিটাল মিল) | 6,175 |
| Nagad | 2,000 | 0 | 2,000 |
| Rocket | 1,000 | 0 | 1,000 |

> bKash-এ ডিজিটাল মিল নিশ্চিত হওয়ার পর ৩,০০০ ধরা হয়েছে; ১০-৩ এর "ফোনে ৩,১৭৫" অংশটি তাই আগের ৩,০০০ সহ গণনা করা হয়েছে।

### ব্যালেন্স শিট (দিন শেষে, ৳, ডেমো)

**সম্পদ (Assets)**

| খাত | ৳ |
|---|---|
| হাব নগদ (ডেমো, বেতন বাদে সরল) | 24,800 |
| bKash | 6,175 |
| Nagad | 2,000 |
| Rocket | 1,000 |
| Stock (অনুমান, মূল্যে) | 14,500 |
| বাকি (Customer Receivable) | 900 (Nasrin) − 600 (আদায়) = 300 |
| Receivable from Carrier (Claim) | 450 |
| Advance to Employee | 2,000 |
| **মোট সম্পদ** | **51,225** |

**দায় (Liabilities)**

| খাত | ৳ |
|---|---|
| Supplier Payable (সুগার বিল) | 3,680 |
| Customer Advance (Ruma) | 1,000 |
| বেতন দেনা | 0 (পরিশোধ করা হয়েছে ধরে) |
| **মোট দায়** | **4,680** |

**মূলধন (Equity)**

| খাত | ৳ |
|---|---|
| Owner Capital (শুরু) | 50,000 |
| Partner Capital (Rafiq) | 20,000 |
| দিনের লাভ/ক্ষতি | (see below) |

**দিনের লাভ/ক্ষতি (ডেমো):**

| খাত | ৳ |
|---|---|
| বিক্রি | 675 + 900 + 1,400 (branch2 + al_cakes + main অন্য) = 2,975 (ডেমো) |
| COGS (বিক্রিত মাল) | (2,975 × 0.55) = ~1,636 |
| Gross Profit | ~1,339 |
| খরচ (চা, মেরামত) | 350 |
| Cash Short | 200 |
| বেতন | 45,000 |
| দিনের নিট | ~ -44,211 |

> **বিশ্লেষণ:** বেতন ৪৫,০০০ একদিনে ধরা হলে দিনের লোকসান খুব বড় দেখাবে। বাস্তবে বেতন মাসে একবার, তাই এটি দৈনিক হিসাবে ধরা উচিত নয়। ডেমোর জন্য শুধু দেখানো হয়েছে।

**ব্যালেন্স চেক:** সম্পদ 51,225 ; দায় + মূলধন = 4,680 + 50,000 + 20,000 + (দিনের নিট −44,211) = 30,469 — এর সাথে মেলে না। ফারাক ২০,৭৫৬। এটি ডেমো মডেলের সরলীকরণ। বাস্তব ব্যালেন্সের জন্য বেতনের নগদ উৎস এবং শুরুর স্টক মূল্য ঠিক করতে হবে। (এটি এই ফাইলের একটি স্বীকৃত দুর্বলতা।)

---

## ৬. ফিডব্যাক ও সিস্টেম আপডেটের প্রস্তাব

**যা এই ডেমোতে সবচেয়ে বেশি দরকার:**
1. Balance Sheet সূত্র: সম্পদ = দায় + মূলধন। ডেমো শিটে ফারাক ২০,৭৫৬ এসেছে, কারণ বেতন নগদ উৎস ছাড়া ধরা হয়েছে। সিস্টেমে এই ফারাক ধরার একটি "Balance Check" থাকা দরকার।
2. বেতন মাসিক হিসাবে থাকা উচিত, দৈনিক Expense হিসেবে নয়। একটি "Monthly Close" স্ক্রিন দরকার।
3. Stock valuation (মূল্যে স্টক): প্রতিটি আইটেমের গড় দাম (Weighted Average) দেখানো দরকার।
4. Opening Balance-এর পর একটি "Trial Balance" থাকা দরকার।
5. bKash/Nagad/Rocket ফি (charge) আলাদা খরচ হিসাবে দেখানো উচিত।
6. দুধ, প্যাকিং খরচ উৎপাদন খরচে আসে; Recipe Cost-এ এগুলো যোগ হওয়া দরকার।
7. Transit Short-এর Claim স্ট্যাটাস (Open / Recovered / Written Off) ট্র্যাক করা দরকার।
8. Cash Short-এর জন্য মালিকের অনুমোদন ছাড়া জমা না হওয়ার নিয়ম।
9. Partner Capital-এর লাভ ভাগাভাগির হিসাব (Share %) রিপোর্টে থাকা দরকার।
10. Demo-র জন্য একটি "Reset Demo" বোতাম থাকা দরকার, যাতে test project বারবার পরিষ্কার করা যায়।

---

## ৭. যাচাই পরিকল্পনা (ভবিষ্যৎ)

1. Opening Balance স্ক্রিন বানিয়ে ১ অক্টোবরের ডেমো ডেটা ঢোকান।
2. উপরের ঘটনাগুলো ক্রমে চালান।
3. প্রতিটি জার্নাল এন্ট্রি মেলান: Dr = Cr।
4. Balance Sheet সূত্রে মিলিয়ে দেখুন। ফারাক থাকলে ঠিক করুন।
5. নেগেটিভ N1–N16 চালিয়ে আচরণ লিখুন।
