# Fictitious demo staff by role and location

All names are invented for training and demo. **No account has been created.** The live database has one real account (owner + management). Do not create these in the live project; use a test project or test accounts.

Role codes are the live `roles.code` values. Place codes are the live `locations.code` values. Several people may hold one role at different places.

| Demo name | Role code | Place(s) | Does in the demo day |
|---|---|---|---|
| Karim | `owner` | all | Rules, releases, final decisions |
| Salma | `management` | all | Approves 14-1, 10-2, 05-1 |
| Rahim | `showroom_manager` | `main` | 14-1, 11-1, 10-2, receives transfers |
| Ayesha | `showroom_manager` | `mishti_bari` | Receives godown transfers |
| Shirin | `showroom_manager` | `branch2` | Second showroom day sheet |
| Lipi | `showroom_manager` | `al_cakes` | AL-CAKIZ day sheet |
| Nasrin | `salesperson` | `main` | POS sales, dues |
| Tania | `salesperson` | `branch2` | POS sales |
| Jamal | `storekeeper` | `godown` | GRN, issue, transfer out |
| Selim | `factory_incharge` | `main` | Production, 05-1 |
| Mitu | `factory_incharge` | `cake_factory` | Cake production |
| Hasan | `purchasing` | head office (no place) | Requisition, quotes, PO, bills; counts stock as independent counter |
| Fatema | `cash_controller` | `main` (hub) + view all showrooms | Hub count, 10-3 digital register |
| Ruma | `party_coordinator` | `main` | Party orders, 20-1 / 20-4 |
| Anwar | `hr` | head office | Attendance, witness for stock count |
| Sohel | `carrier` | between places | Carries cash and challans |
| Nazia | `recipe_approver` | head office | Approves recipe changes |

Separation rules to test with this roster: counter ≠ storekeeper (Hasan counts, not Jamal); witness ≠ counter (Anwar); maker ≠ approver; owner self-approve is ON by default (`owner_self_approve`).
Grants for every role are the existing `role_form_perms` (118 rows) and `rule_grants` (58 rows); this roster adds none. The owner must grant places per person (`user_locations`).
