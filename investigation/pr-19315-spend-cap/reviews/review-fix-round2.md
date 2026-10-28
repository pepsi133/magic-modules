# Adversarial review, round 2: spend_cap removal / mask / flatten (commits cc69ec67b + c3a311883)

Scope: `git diff b1edf518a..c3a311883` restricted to Budget.yaml, custom_flatten/billing_budget_spend_cap.go.tmpl, pre_update/billing_budget.go.tmpl, resource_billing_budget_test.go. `git diff --stat b1edf518a..c3a311883 -- . ':!investigation'` shows exactly those 4 files (263 insertions, 1 deletion). No edits were made in /home/user/magic-modules (`git status --short` empty).

## Per attempt

### R1. Removal path (generated code + API probes)
Generated update function, /home/user/tpgb/google-beta/services/billingbudgets/resource_billing_budget.go lines 882-922:
```
	if d.HasChange("spend_cap") {
		updateMask = append(updateMask, "spendCap.inputState")
	}
	...
	if _, ok := d.GetOk("spend_cap"); ok && len(updateMask) > 0 {
		...
		if !hasInputState {
			updateMask = append(updateMask, "spendCap.inputState")
			url, err = transport_tpg.AddQueryParams(url, map[string]string{"updateMask": strings.Join(updateMask, ",")})
	...
	} else if !ok && d.HasChange("spend_cap") {
		for i, m := range updateMask {
			if m == "spendCap.inputState" {
				updateMask[i] = "spendCap"
			}
		}
		url, err = transport_tpg.AddQueryParams(url, map[string]string{"updateMask": strings.Join(updateMask, ",")})
```
Body on removal: line 831 `else if v, ok := d.GetOkExists("spend_cap"); !tpgresource.IsEmptyValue(reflect.ValueOf(v)) ...` — an empty list is empty, so `obj["spendCap"]` is not set. Confirmed in the R3 log (scratchpad r3.log line 7842-7846): `Updating Budget ... {"amount":..., "budgetFilter":..., "displayName":..., "notificationsRule":..., "thresholdRules":...}` (no spendCap) and `PATCH .../budgets/860fcb2c-...?alt=json&updateMask=spendCap HTTP/1.1` — mask is exactly `spendCap`. Amount-only step (line 5689): `updateMask=amount.specifiedAmount.currencyCode,amount.specifiedAmount.units,amount.specifiedAmount.nanos,spendCap.inputState`; body carried `"spendCap":{"inputState":"CONFIGURED","outputState":"CONFIGURED"}` (expand copies computed output_state from state into the body; harmless because it is not in the mask — probe C3 below confirms the API ignores it).

Remove + amount change in one apply: by code, `d.HasChange("amount")` adds amount.* and the removal branch rewrites only the `spendCap.inputState` entry, giving `amount.*,spendCap`. Verified against the API with curl (scratchpad probe.sh, step B3): `PATCH ...?updateMask=amount.specifiedAmount.currencyCode,amount.specifiedAmount.units,amount.specifiedAmount.nanos,spendCap` with body `{"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"7"}}}` returned 200 with units 7 and no `spendCap` in the response; the subsequent GET also has no spendCap. Not covered by a Terraform test (see finding F3).

Add a spend_cap block to an existing budget (probe A1/A2/B5): `PATCH ...?updateMask=spendCap.inputState` body `{"spendCap":{"inputState":"CONFIGURED"}}` ->
```
{"error":{"code":400,"message":"Cannot transition a regular budget to a spend cap budget.","status":"FAILED_PRECONDITION"}}
```
Same with `updateMask=spendCap`, and same on a budget whose cap had just been removed (B5). The public doc says the same: "You can't edit an existing alerts-only budget to convert it to a spend cap enforcement budget." The provider plans this as an in-place update (spend_cap has no ForceNew / CustomizeDiff), so `terraform apply` fails with this error. See finding F1.

Also verified the hook's premise (probe C1/C2): on a capped budget, `updateMask=amount.specifiedAmount.currencyCode,amount.specifiedAmount.units,amount.specifiedAmount.nanos` without spendCap -> `400 INVALID_ARGUMENT "Request contains an invalid argument."`; `updateMask=displayName` -> same. Discovery doc for `Budget.spendCap`: "If the existing resource is a spend cap and an `update_mask` is supplied in an `UpdateBudget` request, `spend_cap` or `spend_cap.input_state` must be specified in the update mask. To convert a spend cap budget to a regular budget, specify `spend_cap` in the `update_mask` and omit `spend_cap` from the budget in the request."

### R2. Flatten order
Generated flatten, resource_billing_budget.go lines 1426-1435: `if original["outputState"] == "AWAITING_NEXT_PERIOD" {AWAITING_NEXT_PERIOD} else if API inputState present {it} else if d.GetOk("spend_cap.0.input_state") {state} else {"CONFIGURED"}`.
- outputState ENFORCED, state CONFIGURED -> returns CONFIGURED (state branch). No diff.
- outputState AWAITING_NEXT_PERIOD, state AWAITING_NEXT_PERIOD -> AWAITING_NEXT_PERIOD. No diff.
- outputState AWAITING_NEXT_PERIOD, state/config CONFIGURED -> AWAITING_NEXT_PERIOD in state, plan shows in-place update of input_state to CONFIGURED; Update sends body spendCap{inputState:CONFIGURED,...} with mask `spendCap.inputState` (hook does not alter it since d.HasChange("spend_cap") already added it).
Discovery doc, `SpendCap.inputState`: "`CONFIGURED`: Must be set when creating a spend cap (`CreateBudget`). Also valid when updating (`UpdateBudget`) to activate the spend cap. If the spend cap is in state `AWAITING_NEXT_PERIOD`, `input_state` must be set to `CONFIGURED`. - `AWAITING_NEXT_PERIOD`: Valid only when updating (`UpdateBudget`) to explicitly lift an enforced cap. Not allowed if the spend cap is in state `AWAITING_NEXT_PERIOD`. Supplying any other value will result in an INVALID_ARGUMENT error." So the AWAITING_NEXT_PERIOD -> CONFIGURED PATCH is allowed (re-arm, desired), not a 400. However the how-to doc says after a manual lift "a spend cap won't trigger again for the rest of the budget period" unless "you subsequently edit the budget to increase the spend cap amount and set the inputState to CONFIGURED". Whether outputState actually leaves AWAITING_NEXT_PERIOD when only inputState=CONFIGURED is sent (without raising the amount) is not documented and could not be exercised (needs real enforced spend). If it stays AWAITING_NEXT_PERIOD, the flatten produces a permanent diff (finding F2). Probe B2 confirmed the description's other claim: AWAITING_NEXT_PERIOD while outputState CONFIGURED -> `400 INVALID_ARGUMENT "Request contains an invalid argument."`.

### R3. Concurrent run, then lone rerun
Command: `cd /home/user/tpgb && GOOGLE_OAUTH_ACCESS_TOKEN=proxy-injected GOOGLE_USE_DEFAULT_CREDENTIALS=true TF_LOG=DEBUG make testacc TEST=./google-beta/services/billingbudgets TESTARGS="-run='TestAccBillingBudgetsBudget_billingBudgetSpendCapExample|TestAccBillingBudget_spendCapUpdate|TestAccBillingBudgetsBudget_billingBudgetBasicExample|TestAccBillingBudget_billingBudgetUpdate\$\$'"` (log: scratchpad/r3.log)
```
--- PASS: TestAccBillingBudgetsBudget_billingBudgetBasicExample (21.44s)
--- PASS: TestAccBillingBudgetsBudget_billingBudgetSpendCapExample (25.59s)
--- PASS: TestAccBillingBudget_spendCapUpdate (47.00s)
--- PASS: TestAccBillingBudget_billingBudgetUpdate (78.66s)
ok  	github.com/hashicorp/terraform-provider-google-beta/google-beta/services/billingbudgets	78.745s
```
All four ran in parallel (RUN lines 5-11 before any PASS). The two capped budgets used services C7E2-9256-1C43 and AEFD-7695-64FA on the same project with no overlap error.
Lone rerun (`-run='TestAccBillingBudget_spendCapUpdate\$\$'`, scratchpad/r3b.log): `--- PASS: TestAccBillingBudget_spendCapUpdate (42.09s)` / `ok ... 42.204s`. Not order-dependent.

### R4. Negative control
Backed up `/home/user/tpgb/google-beta/services/billingbudgets/resource_billing_budget.go` (md5 be73b337e572bce09a35cb46254cb3de) to scratchpad; changed line 915 so the removal branch keeps `spendCap.inputState`. Rerun of the update test (scratchpad/r4.log):
```
Error: Error updating Budget "billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/4f65ffda-...": googleapi: Error 400: Request contains an invalid argument.
... test_step_number=5 test_name=TestAccBillingBudget_spendCapUpdate
--- FAIL: TestAccBillingBudget_spendCapUpdate (33.97s)
FAIL	github.com/hashicorp/terraform-provider-google-beta/google-beta/services/billingbudgets	34.062s
```
Fails at the removal step as required. Restore: `cp $S/resource_billing_budget.go.bak google-beta/services/billingbudgets/resource_billing_budget.go` -> `cp exit=0`, md5 be73b337e572bce09a35cb46254cb3de again, `grep -c "R4 negative control"` = 0. CheckDestroy ran and the test's budget was deleted.

### R5. Hygiene
- `gofmt -l google-beta/services/billingbudgets/` (tpgb): no output. `gofmt -l` on the mmv1 test file: no output (gofmt cannot parse the .tmpl, expected).
- `go vet ./google-beta/services/billingbudgets/...`: exit 0.
- mmv1 `go test ./...`: 9 `ok` packages, exit 0 (scratchpad/mmv1-gotest.log).
- template-check (tools/template-check): `version-guard --file-list <both templates>` exit 0; `unused-tmpl --file-list <both templates>` exit 0 (both templates referenced from Budget.yaml).
- Regenerated website/docs/r/billing_budget.html.markdown contains the three new sentences: line 379-380 "Only one spend cap budget may exist per project and service; the API rejects a spend cap that overlaps an existing one.", line 596-598 "`AWAITING_NEXT_PERIOD` is only accepted while `output_state` is `ENFORCED`; otherwise the API rejects the update with a generic "invalid argument" error.", line 599-603 "The API does not return this field. When `output_state` is `AWAITING_NEXT_PERIOD`, Terraform reads `input_state` as `AWAITING_NEXT_PERIOD`, so a cap lifted outside Terraform shows as a diff. Otherwise Terraform keeps the configured value in state, and on import uses `CONFIGURED`."
- Generated sample test: the reviewed range changes no sample/example file (stat above), so resource_billing_budget_generated_test.go cannot differ from the base PR's output; the only working-tree deltas in tpgb's generated test are the local PLN/units edits (kept). Generated test files carry no descriptions.

### R6. Upstream fit
- Template names (`pre_update/billing_budget.go.tmpl`, `custom_flatten/billing_budget_spend_cap.go.tmpl`) follow the `<product>_<resource>[_field]` convention used by neighbours; `custom_code.pre_update` is the documented hook (docs/content/develop/custom-code.md line 172-181); rewriting `updateMask` + `AddQueryParams` in pre_update has precedents (alloydb_cluster, alloydb_user, access_context_manager_service_perimeter).
- `plancheck.ExpectResourceAction` is used in 671 places across third_party tests; fine.
- Test name `TestAccBillingBudget_spendCapUpdate` matches the file's existing `TestAccBillingBudget_billingBudgetUpdate` style.
- The flatten is the only custom_flatten using `{{ join $.Lineage ".0." }}`; every other precedent hard-codes the path. Works (renders `spend_cap.0.input_state`) but is unusual; a maintainer may ask for the literal path.
- The hard-coded `update_mask_fields` lists on budget_filter / all_updates_rule are pre-existing and untouched by this change; not a reason to block.
- Description wording: see F4/F5.

## Findings

F1 (high) — mmv1/products/billingbudgets/Budget.yaml line 556 (`- name: spendCap`). Adding a `spend_cap` block to an existing budget plans as an in-place update but the API refuses it: `400 FAILED_PRECONDITION "Cannot transition a regular budget to a spend cap budget."` (probe A1/A2/B5; public doc: "You can't edit an existing alerts-only budget to convert it to a spend cap enforcement budget."). Removing the block by PATCH works, so plain `immutable: true` is wrong (it would force replacement on removal too, and replacement is refused while ENFORCED). Proposed fix: add a `custom_diff` function in templates/terraform/constants/billing_budget.tmpl, e.g.
```go
func resourceBillingBudgetSpendCapDiff(_ context.Context, d *schema.ResourceDiff, meta interface{}) error {
	old, new := d.GetChange("spend_cap")
	if len(old.([]interface{})) == 0 && len(new.([]interface{})) > 0 {
		return d.ForceNew("spend_cap")
	}
	return nil
}
```
register it via `custom_diff: [resourceBillingBudgetSpendCapDiff]` in Budget.yaml, add a sentence to the spend_cap description ("A spend cap cannot be added to an existing budget; adding the block replaces the budget."), and add a test step (regular budget -> spend_cap added, `plancheck.ExpectResourceAction(..., ResourceActionReplace)`).

F2 (medium, unverifiable here) — mmv1/templates/terraform/custom_flatten/billing_budget_spend_cap.go.tmpl line 29. Mapping outputState AWAITING_NEXT_PERIOD to input_state AWAITING_NEXT_PERIOD produces a diff whose apply sends inputState=CONFIGURED. The API accepts it, but the how-to doc says a lifted cap "won't trigger again for the rest of the budget period" unless the amount is increased, so outputState may stay AWAITING_NEXT_PERIOD and the diff would reappear on every plan until the next period. Proposed fix: either (a) state this in the input_state description ("Reverting a lifted cap to `CONFIGURED` only re-arms it if the amount is also increased; otherwise the diff persists until the next period"), or (b) drop the outputState-driven branch and let users detect lifted caps via the computed `output_state` (documented), keeping input_state purely state-driven. Pick one and say which.

F3 (medium) — mmv1/third_party/terraform/services/billingbudgets/resource_billing_budget_test.go line 709-737. The test does not cover the combined "remove block + change amount" apply, which is the path where the mask rewrite (`amount.*,spendCap`) and the body shape matter most. API accepts it (probe B3). Proposed fix: make the removal step also change `units` (e.g. contextRemoved with units "7") so one step exercises both; the plan check and `spend_cap.# = 0` check stay.

F4 (low) — Budget.yaml line 579-581: "`AWAITING_NEXT_PERIOD` is only accepted while `output_state` is `ENFORCED`; otherwise the API rejects the update with a generic "invalid argument" error." Clearer for a Terraform user: "Set `AWAITING_NEXT_PERIOD` only when `output_state` is `ENFORCED`; in any other state the API returns `400 INVALID_ARGUMENT`. Set it back to `CONFIGURED` once the next period starts (the API resets `output_state` to `CONFIGURED`) or the next apply of any other field fails with the same error." The last sentence covers a trap the current text omits: after the period rolls over, state still holds AWAITING_NEXT_PERIOD (state branch of the flatten), config matches, so no diff, but the hook forces `spendCap.inputState` into every mask and the body carries AWAITING_NEXT_PERIOD -> INVALID_ARGUMENT on the next unrelated update.

F5 (low) — Budget.yaml line 566-567: "Only one spend cap budget may exist per project and service; the API rejects a spend cap that overlaps an existing one." The doc wording is "deduplication policy that prevents users from creating more than one budget with the same scope"; suggest "The API rejects a spend cap budget whose project and service match an existing spend cap budget." Also worth one sentence that a cap can be removed by deleting the block (the PR adds this behaviour but does not document it): "Removing the `spend_cap` block converts the budget back to an alerts-only budget; this is refused while `output_state` is `ENFORCED`."

F6 (low) — custom_flatten template line 33: `d.GetOk("{{ join $.Lineage ".0." }}.0.input_state")` is the only Lineage-based path in custom_flatten; harmless, but precedents hard-code `"spend_cap.0.input_state"`. Optional.

F7 (nit) — pre_update template line 13: `len(updateMask) > 0` guard is redundant (if the mask is empty no PATCH is sent at line 930) but harmless; the comment "The API rejects any update of a budget with a spend cap unless..." is now verified (probe C1/C2).

## Verdict
Needs changes. The reviewed removal path, mask rewrite, flatten resolution and test are correct and verified (R1, R3, R4 all behave as intended), but adding `spend_cap` to an existing budget plans an update that the API always refuses (F1), and the re-arm path after an external lift is undocumented and may permadiff (F2).

## Leftover GCP resources
None. `curl https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets` -> `{}` after R4. Probe budgets (reviewprobe-nocap, reviewprobe-cap, reviewprobe-cap2 on service 152E-C115-5142, 5-7 PLN) were each deleted (`{}` responses); all test budgets removed by CheckDestroy.

## Changes outside /home/user/tpgb and the scratchpad
- /home/user/review-fix-round2.md (this report).
- /home/user/tpgb: resource_billing_budget.go restored byte-identical (md5 be73b337e572bce09a35cb46254cb3de); working tree still carries only the pre-existing regeneration + PLN edits. Nothing committed anywhere. /home/user/magic-modules unchanged (`git status --short` empty).
