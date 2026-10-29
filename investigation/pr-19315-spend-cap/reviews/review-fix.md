# Adversarial review: commit 2a441756e (billingbudgets spend_cap permadiff + update mask)

Artifact: `git show 2a441756e` on branch claude/great-galileo-1gggv5 in /home/user/magic-modules.
Files: mmv1/products/billingbudgets/Budget.yaml, mmv1/templates/terraform/custom_flatten/billing_budget_spend_cap.go.tmpl,
mmv1/templates/terraform/pre_update/billing_budget.go.tmpl, mmv1/third_party/terraform/services/billingbudgets/resource_billing_budget_test.go.

## Verdict: NEEDS CHANGES

The two stated goals (no permadiff on `input_state`; PATCH of a capped budget always carries `spendCap.inputState`) work and are
proven by live tests. Two real defects remain: (1) removing the `spend_cap` block from config is a guaranteed bare 400 (the hook does
not handle the removal case and the generated mask is wrong for it), and (2) the two spend-cap acceptance tests are `t.Parallel()` and
create a cap on the same project+service, which the API rejects as an overlap -- they will flake against each other in CI
(reproduced here on the first run).

---

## Per-attempt log

### B1. custom_flatten semantics on a NestedObject

`mmv1/templates/terraform/flatten_property_method.go.tmpl` lines 15-19: the `define "flattenPropertyMethod"` branches
`{{- else if and $.CustomFlatten (not $.ShouldIgnoreCustomFlatten) }} {{- customTemplate $ $.CustomFlatten false -}}`
and the `{{- if $.NestedProperties }} {{ range ... template "flattenPropertyMethod" }}` recursion sits inside the trailing
`{{- else -}}` branch, so child flatteners are NOT emitted when the parent has a custom_flatten. Confirmed in the generated file:

```
$ grep -n "flattenBillingBudgetsBudgetSpendCap" /home/user/tpgb/google-beta/services/billingbudgets/resource_billing_budget.go
1392:func flattenBillingBudgetsBudgetSpendCap(v interface{}, d *schema.ResourceData, config *transport_tpg.Config) interface{} {
2199:	if err = d.Set("spend_cap", flattenBillingBudgetsBudgetSpendCap(res["spendCap"], d, config)); err != nil {
```
No `flattenBillingBudgetsBudgetSpendCapInputState/OutputState/Reconciling` exist. Function name/signature matches the generator's
call (`flatten{{$.GetPrefix}}{{$.TitlelizeProperty}}`; `{{ join $.Lineage ".0." }}` rendered as `spend_cap`, so the GetOk key is
`spend_cap.0.input_state`). Expanders for all three children still exist (lines 1868-1912), so Update sends
`"spendCap":{"inputState":"CONFIGURED","outputState":"CONFIGURED"}` (quoted from the rerun log, line 1438) -- harmless because
the mask only lists `spendCap.inputState` (probe P7 below confirms the API accepts it).

### B2. Breaking the flatten

Live API facts (probe script, project ${GOOGLE_PROJECT_NUMBER}, service C7E2-9256-1C43, 5 PLN):
- P1/P2: create and GET return `"spendCap": {"outputState": "CONFIGURED"}` only -- `inputState` is never returned, `reconciling` absent when false.
- Only one spend-cap budget may exist per project+service: a second create returns
  `400 FAILED_PRECONDITION "Overlap detected with existing cost view ... for project ${GOOGLE_PROJECT_NUMBER}, service services/C7E2-9256-1C43."`

Cases:
- Import of a capped budget: state empty -> `d.GetOk("spend_cap.0.input_state")` false -> derived `CONFIGURED` from `outputState`.
  Proven: `TestAccBillingBudget_spendCapUpdate` steps 2 and 4 are `ImportStateVerify: true` with no ignore list and PASS (see B4).
- Budget without cap: `res["spendCap"]` is nil -> flatten returns nil -> no block in state; Basic and handwritten Update tests PASS with
  no spendCap in any request (`grep -c spendCap` on the Basic log = 0) and no perpetual-diff failure.
- `d.GetOk` inside the flattener: `d` in Read-after-Create and Read-after-Update is the planned new state (config value), so it returns
  the configured value; in import `d` holds only the ID so GetOk returns false and the derivation path runs. The rerun log shows the
  Read-after-Update with the planned `CONFIGURED` and a clean post-apply plan. Correct for all three.
- input_state CONFIGURED -> AWAITING_NEXT_PERIOD while output_state CONFIGURED: probe P5
  `PATCH ?updateMask=spendCap.inputState {"spendCap":{"inputState":"AWAITING_NEXT_PERIOD"}}` -> `400 INVALID_ARGUMENT "Request
  contains an invalid argument."`. The provider surfaces this as `Error updating Budget ...: googleapi: Error 400: Request contains an
  invalid argument.` -- no hint at all. State stays consistent (Update returns before Read; state keeps CONFIGURED; the plan re-proposes
  the change each run). Finding M2.
- outputState ENFORCED with configured CONFIGURED: output_state is Computed-only, so no diff; input_state is taken from state. OK.
  (Could not reach ENFORCED with a 5 PLN cap in the test window; reasoned from schema.)
- `reconciling` flapping: Computed, Optional false -> never diffs. OK.
- Cap lifted in console / `plan -refresh-only`: there are two server shapes. (a) spendCap deleted server-side (probe P6 shows
  `updateMask=spendCap` with no body does this: GET then returns no `spendCap`): flatten returns nil, state drops the block, plan shows
  `+ spend_cap` -- drift is visible, good. (b) cap lifted to AWAITING_NEXT_PERIOD while the block still exists: `outputState` becomes
  AWAITING_NEXT_PERIOD (visible, computed) but `input_state` stays CONFIGURED from state -- the real `inputState` drift is hidden, and the
  next unrelated apply will re-send `inputState: CONFIGURED` via the hook, re-enabling the cap silently. The field description documents
  that the value is kept from state, but not this consequence. Finding M3. A cheap improvement: when `outputState == "AWAITING_NEXT_PERIOD"`
  prefer that over the state value (the derivation branch already does this for import, so the ordering of the two branches is the
  only change).

### B3. Breaking the pre_update hook

Order in generated `resourceBillingBudgetsBudgetUpdate` (/home/user/tpgb/.../resource_billing_budget.go):
line 836 `updateMask := []string{}`, 838-878 HasChange blocks (877 `updateMask = append(updateMask, "spendCap.inputState")`),
881 first `AddQueryParams`, 886-903 the hook, 912 `if len(updateMask) > 0 { SendRequest(PATCH) }`.
So the hook runs AFTER the generated mask and after the first AddQueryParams, and re-sets the query parameter. `AddQueryParams`
(google-beta/transport/transport.go:244) uses `q.Set`, so no duplicate `updateMask` key. Encoding is `%2C` for commas, identical to the
generated path. Precedent for this pattern: `mmv1/templates/terraform/pre_update/access_context_manager_service_perimeter.go.tmpl`
lines 37-38 do the same re-join + AddQueryParams.
- Empty mask: `len(updateMask) > 0` guard means the hook adds nothing and no PATCH is sent. Correct.
- `spend_cap` itself changed: generated code already appended `spendCap.inputState`; the loop finds it and does not duplicate. Correct.
- `d.GetOk("spend_cap")` on an empty list returns ok=false; no panic. Correct.
- Block removed (HasChange true, GetOk false): the hook skips, the generated mask is `spendCap.inputState`, the body has no `spendCap`.
  Live result through the provider (temporary test, see below): `PATCH ...?updateMask=spendCap.inputState` -> 400 bare. Probe P6 proves
  removal IS possible with `updateMask=spendCap` and no body. Finding H1.

### B4. Acceptance tests run (logs in /tmp/claude-0/-home-user-magic-modules/226a38d8-2f36-5156-86eb-097c301a2149/scratchpad/)

Command per test: `cd /home/user/tpgb && GOOGLE_OAUTH_ACCESS_TOKEN=proxy-injected GOOGLE_USE_DEFAULT_CREDENTIALS=true TF_LOG=DEBUG
make testacc TEST=./google-beta/services/billingbudgets TESTARGS='-run=<Name>$$'`, five launched concurrently first:

- `--- PASS: TestAccBillingBudgetsBudget_billingBudgetSpendCapExample (25.78s)` -- requests: 1 POST, 6 GET, 1 DELETE, no PATCH.
- `--- PASS: TestAccBillingBudgetsBudget_billingBudgetBasicExample (21.34s)` -- no PATCH, no spendCap anywhere.
- `--- PASS: TestAccBillingBudget_billingBudgetUpdate (66.61s)` (PLN-edited: lines 292/293, 338/339, 389/390, 438/439, 497/498 -> PLN, units 5). PATCH masks observed, none contain spendCap:
  `updateMask=budgetFilter.projects%2C...%2CbudgetFilter.subaccounts` (x1), `...%2CthresholdRules` (x2),
  `...%2CthresholdRules%2CnotificationsRule.pubsubTopic%2C...%2CnotificationsRule.enableProjectLevelRecipients` (x1). No regression.
- `--- FAIL: TestAccBillingBudget_spendCapUpdate (7.66s)` on the concurrent run:
  `Error creating Budget: googleapi: Error 400: Overlap detected with existing cost view '42cec8f9-...' (ID: Example Spend Cap Budgetyeto2wpftr) for project ${GOOGLE_PROJECT_NUMBER}, service services/C7E2-9256-1C43.`
  -- i.e. it collided with the SpendCapExample test running in parallel. Finding H2.
  Rerun alone: `--- PASS: TestAccBillingBudget_spendCapUpdate (27.61s)`; the single PATCH:
  `PATCH /v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/bce30a22-...?alt=json&updateMask=amount.specifiedAmount.currencyCode%2Camount.specifiedAmount.units%2Camount.specifiedAmount.nanos%2CspendCap.inputState`
  body `"spendCap":map[string]interface {}{"inputState":"CONFIGURED", "outputState":"CONFIGURED"}`.
- `TestAccBillingBudget_budgetFilterProjectsOrdering`: not completable here -- `--- FAIL ... Permission 'resourcemanager.projects.create' denied on organizations/${GOOGLE_ORG}` (needs project creation; unrelated to the change). Replaced by billingBudgetUpdate above.

### B5. New handwritten test

- It does not assert the mask; it relies on the apply not erroring plus `ExpectResourceAction(..., ResourceActionUpdate)` (correct use:
  PreApply plan check on step 3 ensures an in-place update, not a replace/no-op). ImportStateVerify covers `spend_cap.0.input_state`
  (no ignore list) and passed, so the import derivation is exercised.
- Could it pass without the hook? No. With the hook block deleted from the generated file (tpgb only, restored afterwards):
  `PATCH ...?updateMask=amount.specifiedAmount.currencyCode%2Camount.specifiedAmount.units%2Camount.specifiedAmount.nanos` ->
  `Step 3/4 error: ... googleapi: Error 400: Request contains an invalid argument.` `--- FAIL: TestAccBillingBudget_spendCapUpdate (21.06s)`.
  The test is load-bearing.
- Removal case through the provider (temporary file zz_review_tmp_test.go in tpgb, deleted after): step 2 drops the block ->
  `PATCH ...?updateMask=spendCap.inputState` -> `Step 2/2 error: ... Error 400: Request contains an invalid argument.`
  No test in the commit covers removal. Finding H1 / M4.
- `t.Parallel()` with a fixed project+service: see H2.

### B6. Generator / lint hygiene

- `cd mmv1 && go test ./...` -> all `ok` (api, product, resource, google, provider, test).
- `tools/template-check unused-tmpl --file-list <the two new templates>` -> exit 0.
- `gofmt -l google-beta/services/billingbudgets/` -> clean (the `make testacc` gofmtcheck/vet also passed on every run).
- Website doc regenerated: /home/user/tpgb/website/docs/r/billing_budget.html.markdown lines 590-597 carry the new text
  ("`AWAITING_NEXT_PERIOD` is only accepted while `output_state` is `ENFORCED`. ... on import derives it from `output_state`.").
- Breaking change for existing users: none. For budgets without a cap the flatten returns nil (block absent), identical to before the
  spend_cap feature; proven by the Basic and Update tests.
- Nit: the flattener hard-codes the three child fields; a future child added to `spendCap` in YAML would be silently dropped from state.

### B7. Upstream fit / alternative

Precedents: parent-level custom_flatten on NestedObjects is common (alloydb Cluster dataplex_config, identityplatform Config
email/phone/anonymous, secretmanager SecretVersion, etc.). `ignore_read` on a child plus `ignore_read_extra` is the documented route
(docs/content/develop/diffs.md "API field that is never included in the response") but generates `return d.Get("spend_cap.0.input_state")`,
which on import yields `""` for a Required field -> ImportStateVerify needs `ignore_read_extra`/`ImportStateVerifyIgnore` (an AGENTS.md
test-dodging flag) AND an imported budget would plan an update `"" -> "CONFIGURED"`. Deriving from `outputState` needs the sibling
value, which a child-level custom_flatten does not receive. So the two viable options are:
(a) this parent-level custom_flatten, or
(b) a `custom_code.decoder` of ~8 lines that sets `res["spendCap"]["inputState"]` from `d`/`outputState` when missing, leaving the
    generated flattener intact (no duplicated child handling, future children keep flowing).
I would merge (a) as written (it is the more familiar pattern for reviewers and keeps the derivation next to the field), provided the
findings below are fixed; (b) is the smaller equivalent and I would also accept it. `default_from_api` is not applicable (API never
returns the field).

---

## Findings

| Sev | File:line | Problem | Proposed fix |
|---|---|---|---|
| High H1 | mmv1/templates/terraform/pre_update/billing_budget.go.tmpl:15 (and Budget.yaml:568 `update_mask_fields`) | Removing the `spend_cap` block produces `updateMask=spendCap.inputState` with no `spendCap` in the body -> bare 400 (reproduced live). The API removes a cap with `updateMask=spendCap` and no body (probe P6). | In the hook, handle `d.HasChange("spend_cap") && !ok`: replace `spendCap.inputState` in `updateMask` with `spendCap` (and re-set the query param). Add a test step that removes the block and ImportStateVerify-checks it. If removal is intentionally unsupported, add a CustomizeDiff `ForceNew`/error and say so in the description -- silence is not acceptable. |
| High H2 | mmv1/third_party/terraform/services/billingbudgets/resource_billing_budget_test.go:697 (`t.Parallel()`), and generated SpendCapExample | Both spend-cap tests cap the same project+service; the API rejects a second cap with `400 Overlap detected with existing cost view`. Reproduced: the two tests collided on my first run. In CI they run in the same package in parallel. | Drop `t.Parallel()` from `TestAccBillingBudget_spendCapUpdate` is not enough (the generated example is parallel too). Options: fold the update step into the example's own test via a second sample step (`steps:` with an update), or make the handwritten test use a different eligible service than the sample, or serialize both through a package-level mutex. Document the one-cap-per-project+service constraint in the resource description. |
| Med M2 | pre_update hook / Budget.yaml:574 | `input_state = "AWAITING_NEXT_PERIOD"` while `output_state != ENFORCED` fails with `googleapi: Error 400: Request contains an invalid argument.` -- the user gets no hint. | Add `post_update_failure` (or wrap the error in the hook path) that, when `spend_cap` is set and the error is a 400, appends "spend_cap.input_state = AWAITING_NEXT_PERIOD is only accepted while output_state is ENFORCED; see spend cap docs". |
| Med M3 | custom_flatten/billing_budget_spend_cap.go.tmpl:27-33 | State value takes precedence over `outputState`, so a cap lifted server-side (outputState AWAITING_NEXT_PERIOD) leaves `input_state=CONFIGURED` in state; drift hidden, and the hook re-sends `inputState: CONFIGURED` on the next unrelated update, silently re-arming the cap. | Reorder: if `original["outputState"] == "AWAITING_NEXT_PERIOD"` set `AWAITING_NEXT_PERIOD` first, then fall back to `d.GetOk`, then `CONFIGURED`. Document the behaviour either way. |
| Med M4 | resource_billing_budget_test.go:696-716 | Test only proves "update does not error"; no coverage for removing the block or for `AWAITING_NEXT_PERIOD` validation. | Add a removal step (after H1) and, if ENFORCED cannot be reached in tests, at least a unit test of the hook's mask rewriting. |
| Low L5 | custom_flatten/billing_budget_spend_cap.go.tmpl:35-37 | Hard-coded child list; new children in YAML would be silently dropped. | Either switch to the decoder approach (B7 b) or add a comment that the list must be kept in sync. |
| Low L6 | Budget.yaml:556-566 (spend_cap description) | Does not mention the one-cap-per-project+service overlap rule or that removal/`AWAITING_NEXT_PERIOD` have server-side preconditions beyond the ENFORCED note. | Add one sentence each. |
| Nit | pre_update hook comment | "even when only other fields changed" -- true; also note the removal case once H1 is handled. | -- |

## Leftover GCP resources

None. Every budget created (tests and probes cd3282d4-..., 42cec8f9-..., bce30a22-..., f6b4cf3a-..., c891de87-..., e5bfaed4-..., 06f68c8a-...) was deleted;
final `curl https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets` -> `{}` (checked after each phase and at the end).
All amounts were 5-6 PLN.

## Changes outside /home/user/tpgb and the scratchpad

None. `git status` in /home/user/magic-modules is clean; no git write commands run anywhere.
In /home/user/tpgb (uncommitted, kept): additional PLN edits to `resource_billing_budget_test.go` lines 292/293, 338/339, 389/390, 438/439, 497/498
(`TestAccBillingBudget_billingBudgetUpdate` configs -> PLN, units 5). The generated resource file was temporarily edited for the no-hook experiment and
restored byte-for-byte from a backup (`hasInputState` count 3 before/after). The temporary `zz_review_tmp_test.go` was deleted.
Logs: /tmp/claude-0/-home-user-magic-modules/226a38d8-2f36-5156-86eb-097c301a2149/scratchpad/{TestAcc*.log, rerun-*.log, nohook-*.log, remove-*.log, create.json, body.json, resource_billing_budget.go.bak}.
