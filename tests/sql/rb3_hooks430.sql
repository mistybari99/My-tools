-- RPT-B3 hooks for phase 430 (marker bos430). THESE ARE NOT PART OF phase430.sql: the integrator pastes them (docs/integration/RPT-B3.md, section 3).
-- phase430_test.sql runs this file inside a transaction that is rolled back, so the patched shared function only ever exists on a scratch copy.
-- Every pair is [old exact text, new exact text]. A missing site stops the paste (nothing half changed). Paste twice = no-op (marker bos430).

-- H430-1 post_purchase: (a) refuse a bill whose stock lines have no supplier lot / expiry while the owner's switches receipt_lot_required / receipt_expiry_required are ON,
--                        (b) after a successful posting make the stock batches of the staged lots. Both switches OFF and no staged lot = exactly today's behaviour.
--                        Without this hook the purchase screen applies the lots itself right after posting and the "required" switches are enforced by the screen only.
select public._rb3_patch('public.post_purchase(uuid,jsonb)'::regprocedure, array[
  $a$r := public._post_purchase_p13(p_id, p_payments);$a$,
  $a$perform public._rb3_lot_gate(p_id); /* bos430 */ r := public._post_purchase_p13(p_id, p_payments);$a$,
  $a$if coalesce((r->>'dup')::boolean, false) then return r; end if;$a$,
  $a$if coalesce((r->>'dup')::boolean, false) then return r; end if; begin perform public._rb3_lot_apply(p_id); exception when others then null; end; /* bos430 */$a$], 'bos430');
