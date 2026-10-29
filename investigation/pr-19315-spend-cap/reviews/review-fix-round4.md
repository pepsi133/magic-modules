# Review round 4: 96a871a60 (google_billing_budget spend_cap CustomizeDiff refactor, unit test, docs)

Verdict: **needs changes**. The code and the test are correct and pass, and gofmt/vet are clean. Two of the documentation sentences can mislead a user into re-arming a cap they lifted (both Medium).

## Checks

### 1. Wrapper and nil handling
- Wrapper: `return billingBudgetSpendCapAddedCustomizeDiffFunc(d, d.Id())` (billing_budget.tmpl:28). `*schema.ResourceDiff` satisfies `tpgresource.TerraformResourceDiff`, and the generated package builds and vets.
- Helper: `oldCap, _ := o.([]interface{})` / `newCap, _ := n.([]interface{})`. A nil value or a non-slice value gives a nil slice with len 0, so there is no panic. The old code used `o.([]interface{})` without the ok check and would panic.
- Mock: `func (d *ResourceDiffMock) GetChange(key string) (interface{}, interface{}) { return d.Before[key], d.After[key] }` (tpgresource/resource_test_utils.go:95-97). A missing key returns (nil, nil). It is handled.
- I checked this with an extra test loaded through a `go test -overlay`, so no repo file changed. An empty mock gives forceNew=false. Explicit nil on both sides gives false. A missing Before key with an After value gives true. This is the right result: there was no cap before, so adding one forces a new budget.

### 2. Unit test
- Each case calls `billingBudgetSpendCapAddedCustomizeDiffFunc(d, tc.id)` and asserts `d.IsForceNew != tc.forceNew`. The mock records the call with `func (d *ResourceDiffMock) ForceNew(key string) error { d.IsForceNew = true; return nil }` (resource_test_utils.go:121-124).
- Mutations, run through overlay:
  - The helper always returns nil: the test FAILS on `spend_cap_added`. So a no-op helper would not pass.
  - The `id == ""` guard is removed: FAILS on `new_resource_with_spend_cap`.
  - The helper always forces a new budget: FAILS on `no_spend_cap`, `spend_cap_removed`, `spend_cap_kept` and `spend_cap_kept,_input_state_changed`.
  - The helper forces a new budget on any change in length: FAILS on `spend_cap_removed`.
- Command: `cd /home/user/tpgb && . /home/user/tools/env.sh && GOPROXY=direct go test ./google-beta/services/billingbudgets/ -run TestUnit -v`. Output: `--- PASS: TestUnitBillingBudget_spendCapAddedCustomizeDiff (0.00s)` with all 6 subtests PASS, then `ok .../services/billingbudgets 0.076s`.

### 3. Descriptions (Budget.yaml at 96a871a60)
Checked against https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps. That page says: "You can't delete a spend cap budget while it's enforced." It also says that at the start of the period all spend cap budgets "automatically reset" and the status returns to Configured, and that "Enforced caps are lifted automatically."
- "or the next period starts" (lines 570-572): **supported by inference only**. The page never says it in so many words, but an automatic reset ends ENFORCED, so the delete ban no longer applies. OK to keep.
- The page does not use the term AWAITING_NEXT_PERIOD.

### 4. Formatting, package and copy rule
- `gofmt -l google-beta/services/billingbudgets/ mmv1/third_party/terraform/services/billingbudgets/` printed nothing.
- `go vet ./google-beta/services/billingbudgets/` passed (VET-OK).
- The internal test file declares `package billingbudgets`, not `_test`. 43 `*_internal_test.go` precedents exist under mmv1/third_party/terraform/services/, for example alloydb, apigee and bigtable, and all use the internal package.
- No copy rule is needed. The generator copied the file to tpgb with the "Type: Handwritten" header and rewrote the import to `terraform-provider-google-beta/google-beta/tpgresource`. Apart from the header, the copy is identical to the source.

## Findings

| # | Severity | File:line | Finding | Fix |
|---|---|---|---|---|
| F1 | Medium | mmv1/products/billingbudgets/Budget.yaml:586-590 | "Set it back to `CONFIGURED` before changing any other field" drops the earlier wording "after the next period starts". A user who lifts a cap and then edits, say, the display name in the same period is told to set `CONFIGURED` first. Lines 594-595 say that doing so may re-activate the cap. The two sentences contradict each other on what to do during a lifted period. | Change it to: "After the next period starts, set it back to `CONFIGURED`: every update of a capped budget re-sends this field, and `AWAITING_NEXT_PERIOD` is rejected once the cap is no longer enforced. Until then, other fields cannot be changed without re-sending `CONFIGURED`." Note: the second sentence is only true if the API accepts `CONFIGURED` while the cap is lifted. Verify that, or drop the sentence. |
| F2 | Medium | Budget.yaml:594-595 | "Re-applying `CONFIGURED` after a cap was lifted outside Terraform may re-activate the cap" is ambiguous. State already holds `CONFIGURED` and the API does not return the field, so a plain re-apply produces no diff and sends no PATCH. The real trigger is any later update of another field: pre_update/billing_budget.go.tmpl always adds `spendCap.inputState` to the mask. The statement is also unverified ("may"). The Google page says a manually lifted cap "won't trigger again for the rest of the budget period" unless the target amount is raised. | Change it to: "Any later Terraform update of the budget re-sends `input_state = CONFIGURED`, which may re-activate a cap lifted outside Terraform." Or verify the behavior and state it without "may". |
| F3 | Low | Budget.yaml:570-571 | "cannot be deleted until the cap is lifted (`input_state = AWAITING_NEXT_PERIOD`)" does not say that the lift has to be applied before `terraform destroy`. A destroy alone sends no update. | Add "apply `input_state = AWAITING_NEXT_PERIOD` before destroying". |
| F4 | Low | Budget.yaml:574-575 | "A spend cap cannot be added to an existing budget. Adding the block replaces the budget." can be one sentence. | "Adding a `spend_cap` block to an existing budget replaces the budget." |
| F5 | Low (earlier commits in the range, not 96a871a60) | Budget.yaml:569 and 573-574 | The Google page does not support these. It says only the name, target amount, project and service can be edited on a spend cap budget, which conflicts with "only `input_state` can be changed" while enforced. It also never describes removing a cap. The "Removing the `spend_cap` block converts the budget back to an alerts-only budget" claim rests only on the acceptance test in resource_billing_budget_test.go. | Make sure an acceptance test covers removing the cap. Optionally reword line 569 so it does not contradict the page. |
| F6 | Info | resource_billing_budget_internal_test.go | No test case covers a missing key or a nil value. The overlay test shows the helper already handles it. | Optionally add a case `before: nil, after: configured, forceNew: true`. |

## Changes outside /home/user/tpgb and the scratchpad
None. `git status` in /home/user/magic-modules is clean. I made no edits in tpgb either: the mutation tests used `go test -overlay` with files under the scratchpad. tpgb shows only the pre-existing generated changes. The only file I wrote outside those two places is this report at /home/user/review-fix-round4.md, as requested.
