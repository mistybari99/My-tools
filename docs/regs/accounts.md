# Registration: Module A (Accounting)

## (a) web/ia.js lines
```js
rec('accounts', 'acc', ['হিসাব ও খতিয়ান', 'Accounts & ledger', 'Accounts ও Ledger'], { icon: 'doc', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true, kw: ['accounts', 'ledger', 'journal', 'balance sheet', 'trial balance', 'profit', 'chart of accounts', 'হিসাব', 'খতিয়ান', 'জার্নাল', 'ব্যালান্স শিট'] }),
```

## (b) web/index.html (after cashmoves.js, any place after stock2.js / entry.js)
```html
<script src="accounts.js"></script>
```

## (c) SQL (supabase/phase40.sql, run after phase28)
- Grants: accounts_view (read all reports), accounts_manage (post, manual journal, opening, chart, mappings). Owner always.
- Rules: accounting_on (switch, OFF), accounting_autopost (switch, ON), accounting_start_date (text YYYY-MM-DD, empty = "Data needed").
- Tables (RLS, read-only to users, writes only via SECURITY DEFINER functions): coa_accounts, acct_mappings, journal_entries, journal_lines (append-only).
- Visibility: owner / head management / accountant with a company-wide accounts_manage grant see all places; others see only their places (accounts_view).
- Owner steps: run phase40.sql, set start date (Accounts > Settings), enter opening balances (by party for customers/suppliers), switch accounting_on.
