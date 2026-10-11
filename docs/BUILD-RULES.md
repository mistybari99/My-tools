# BUILD-RULES

(Saved verbatim from docs/inputs/Build-commands-functions-only.md, Command 0 STEP 2. Read before every task.)

BUILD-RULES
1. Paper first. This app is the digital version of the business's paper forms. Never remove an existing form, field, option, screen or permission. You may rearrange, group or search them. Removing needs the owner's written yes.
2. Form codes are the paper's own, written as the app writes them: 0-1, 01-1, 08-1, 14-1. Never renumber, reuse or invent one. A retired form keeps its code and gets the status closed.
3. Nothing is deleted. Records, list options, locations, forms and staff are retired or closed, never deleted. A code is never given to anything else.
4. Every list has Add new and Other. There is no free-text box where a list exists. An entry stores the option's id, never its label, so renaming never breaks history.
5. Who may add is a per-list rule: open (anyone; joins the list at once), approval (a request the owner approves; until then the person writes Other), owner (only the owner adds; others write Other). Enforce it on the server or database, not only by hiding buttons.
6. Location, staff ID and time are filled by the system on every record. People never type them.
7. The change log is append-only. Every add, edit, retire, merge, approval, release and state move writes one line: who, when, what, from, to.
8. The person who asks never approves their own request. An approval outside a limit is an exception that is logged; it is never a precedent.
9. Counts are blind. The person types the counted figure first; the expected figure is shown only after the count is saved. The software never counts; it stores what people count. Short or over is always written, even when it is zero.
10. Two signatures are two different logins, each with its own PIN. One login can never sign twice on one form.
11. After approval a record is locked. A change is a request the owner approves, and it appears in the change log.
12. Offline is a state, not a failure. A record saved on the phone and not yet sent shows Not sent yet and is retried automatically. Nothing is lost.
13. Every name the owner enters is stored as name_bn and name_en. Screen text comes from a dictionary with keys and the three modes (বাংলা, Bng-Eng, English). Never hard-code a label.
14. Security: check permissions on the server or database; a hidden button must also be a refused request. Never store a PIN readable. Limit wrong PIN attempts (5 tries, then a 10 minute lock) and log failed attempts.
15. A blank number on a settings sheet blocks the form that needs it. Never invent a limit, a code, a price or a date. If a value is missing, stop and ask.
16. After every task write what changed and what you could not confirm in docs/BUILD-LOG.md, with the manual checks you ran and their results.
