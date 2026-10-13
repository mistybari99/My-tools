---
id: accounting
title_bn: হিসাব (অ্যাকাউন্টিং) চালু করা
title_en: Switch on accounting
tags: accounting, ledger, journal, balance sheet, হিসাব, খতিয়ান, ব্যালান্স শিট
requires: 
optional_route: accounts
optional_phase: phase40
steps:
- route: accounts | check: rule:accounting_start_date | bn: হিসাব শুরুর তারিখ দিন | en: Set the accounting start date
- route: accounts | check: none | bn: প্রারম্ভিক ব্যালান্স (একটি opening journal) লিখুন | en: Enter opening balances (one opening journal)
- route: switchboard | check: health:accounting_no_start | bn: তারপর accounting_on চালু করুন | en: Then switch accounting_on on
---

