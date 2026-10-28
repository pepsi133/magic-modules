# Adversarial review, round 3: commit 1c847590d (branch claude/great-galileo-1gggv5)

Scope: `git show 1c847590d -- mmv1/` on top of cc69ec67b and c3a311883 (change set b1edf518a..1c847590d, 5 files under mmv1/). No edits were made in /home/user/magic-modules (`git status --short` is empty at the end) and no git write commands were run anywhere.

## Attempts

### T1. CustomizeDiff correctness

Generated registration, /home/user/tpgb/google-beta/services/billingbudgets/resource_billing_budget.go:149-152 (identical in GA at /home/user/tpg/google/services/billingbudgets/resource_billing_budget.go:149-152):

```go
		CustomizeDiff: customdiff.All(
			billingBudgetSpendCapAddedCustomizeDiff,
			tpgresource.DefaultProviderDeletionPolicy("DELETE"),
		),
```

Function (generated line 71-80, from mmv1/templates/terraform/constants/billing_budget.tmpl:23-35):

```go
func billingBudgetSpendCapAddedCustomizeDiff(_ context.Context, d *schema.ResourceDiff, meta interface{}) error {
	if d.Id() == "" {
		return nil
	}
	o, n := d.GetChange("spend_cap")
	if len(o.([]interface{})) == 0 && len(n.([]interface{})) > 0 {
		return d.ForceNew("spend_cap")
	}
	return nil
}
```

Case analysis:

| Case | o / n | Result | Evidence |
|---|---|---|---|
| New resource | `d.Id()==""` | returns nil, no ForceNew | guard on line 72; all create steps planned as create (3 POSTs at the start of the beta log) |
| Existing, block kept, other field changes | 1 / 1 | nil, in-place | beta log line 4717: `PATCH ...?updateMask=amount.specifiedAmount.currencyCode,amount.specifiedAmount.units,amount.specifiedAmount.nanos,spendCap.inputState`; plancheck ResourceActionUpdate passed |
| Existing, block removed (+ amount change) | 1 / 0 | nil, in-place | beta log line 6720: `PATCH ...?updateMask=amount.specifiedAmount.currencyCode,amount.specifiedAmount.units,amount.specifiedAmount.nanos,spendCap`; `spend_cap.# = 0`, `units = 7` (PLN edit of 300) checked; plancheck Update passed |
| Existing, block added | 0 / 1 | ForceNew | beta log lines 3475/3519: `DELETE .../budgets/ca48a148-...` then `POST .../budgets`; plancheck ResourceActionReplace passed |
| Existing, block in both, `input_state` changes | 1 / 1 | nil | by construction (lengths only); the pre_update hook adds `spendCap.inputState` to the mask |
| `spend_cap {}` | n/a | never reaches CustomizeDiff | `input_state` is `Required: true` (generated line 508-511); Terraform rejects the config at validation ("The argument "input_state" is required") |
| import then plan, config has `spend_cap { input_state = "CONFIGURED" }` | 1 / 1 | nil, no diff | ImportStateVerify steps pass in all three tests (see T3/T4) |

Type assertions: `ResourceDiff.GetChange` -> `getChange` -> `get` -> `finalizeResult` (terraform-plugin-sdk v2.40.1, helper/schema/resource_diff.go:634-645): `if result.Value == nil && schema != nil { result.Value = result.ValueOrZero(schema) }`, and `Schema.ZeroValue()` -> `TypeList.Zero()` -> `[]interface{}{}`. So an unset list is `[]interface{}{}`, never a nil interface, and `o.([]interface{})` cannot panic for a key that is in the schema. The existing mmv1 precedent (mmv1/templates/terraform/constants/spanner_database.go.tmpl:71-75) nevertheless nil-guards before asserting; see finding F4 (low). A wholly unknown list (`dynamic "spend_cap"` with unknown `for_each`) yields the zero value with `Computed: true`, so no ForceNew is planned and the apply fails at the API with FAILED_PRECONDITION; this is the same outcome as before the commit, acceptable.

Direct API confirmation of the premise (scratchpad r3-api-probe.log): an alerts-only budget PATCHed with body `{"spendCap":{"inputState":"CONFIGURED"}}` and `updateMask=spendCap.inputState` (and separately `updateMask=spendCap`) returns

```
{"error": {"code": 400, "message": "Cannot transition a regular budget to a spend cap budget.", "status": "FAILED_PRECONDITION"}}
```

### T2. GA provider

- `git clone --depth 200 https://github.com/hashicorp/terraform-provider-google.git /home/user/tpg`; checked out `4abc5c96 databasemigrationservice: add database to postgres samples (#19524) (#30271)`, the GA commit matching the magic-modules base 28366ed79 (same #19524 PR; beta checkout is 7e21030c, the beta mirror of the same PR).
- Symlink: `/home/user/terraform-provider-google -> /home/user/tpg`.
- `cd /home/user/magic-modules && make provider VERSION=ga OUTPUT_PATH=/home/user/terraform-provider-google PRODUCT=billingbudgets` -> `Provider generation process finished for ga` (scratchpad tpg-generate.log, `gen exit=0`). Generated files changed in GA: resource_billing_budget.go, _generated_meta.yaml, _generated_test.go, resource_billing_budget_test.go, website/docs/r/billing_budget.html.markdown.
- `go build ./google/services/billingbudgets/...` -> `build exit=0`; `go vet ./google/services/billingbudgets/...` -> `vet exit=0`; `gofmt -l google/services/billingbudgets/` -> empty (scratchpad tpg-build.log).
- Presence in GA: `billingBudgetSpendCapAddedCustomizeDiff` at lines 71 and 150, `flattenBillingBudgetsBudgetSpendCap` at 1435, pre_update removal branch `updateMask[i] = "spendCap"` at 940.
- GA acceptance run with the same PLN edits (tpgb's edited handwritten test file copied over with the import path rewritten; the only diff lines against the GA-generated file are `currency_code`/`units` lines, verified): `make testacc TEST=./google/services/billingbudgets TESTARGS="-run='TestAccBillingBudget_spendCapAdd$|TestAccBillingBudget_spendCapUpdate$'"`:

```
--- PASS: TestAccBillingBudget_spendCapAdd (28.04s)
--- PASS: TestAccBillingBudget_spendCapUpdate (42.35s)
ok  	github.com/hashicorp/terraform-provider-google/google/services/billingbudgets	42.454s
```

GA log shows the same request shapes: DELETE+POST for the replacement (lines 2521/2623), PATCH with `...,spendCap.inputState` (2762) and `...,spendCap` (4914).

### T3. Beta run, three tests in one invocation, plus negative control

`cd /home/user/tpgb && GOOGLE_OAUTH_ACCESS_TOKEN=proxy-injected GOOGLE_USE_DEFAULT_CREDENTIALS=true TF_LOG=DEBUG make testacc TEST=./google-beta/services/billingbudgets TESTARGS="-run='TestAccBillingBudget_spendCapAdd$|TestAccBillingBudget_spendCapUpdate$|TestAccBillingBudgetsBudget_billingBudgetSpendCapExample$'"` (scratchpad r3-beta-spendcap.log):

```
--- PASS: TestAccBillingBudgetsBudget_billingBudgetSpendCapExample (32.86s)
--- PASS: TestAccBillingBudget_spendCapAdd (40.29s)
--- PASS: TestAccBillingBudget_spendCapUpdate (57.22s)
ok  	github.com/hashicorp/terraform-provider-google-beta/google-beta/services/billingbudgets	57.334s
```

Note: a first invocation written with `$$` in a plain shell expanded to the PID and ran "no tests to run"; the quoted run above uses `\$\$` so make receives `$$`.

Negative control (tpgb only): backed up the generated file to resource_billing_budget.go.bak, deleted the line `billingBudgetSpendCapAddedCustomizeDiff,` (registration became `customdiff.All(tpgresource.DefaultProviderDeletionPolicy("DELETE"))`), reran spendCapAdd (scratchpad r3-beta-negative.log):

```
--- FAIL: TestAccBillingBudget_spendCapAdd (16.47s)
    resource_billing_budget_test.go:783: Step 2/3 error: Pre-apply plan check(s) failed:
        google_billing_budget.budget - expected Replace, got action(s): [update]
exit=2
```

It fails at the plan check, before the apply, so the API FAILED_PRECONDITION is not reached by the test itself; the API-level refusal is shown by the direct probe in T1. The test's budget was destroyed by the framework (DELETE at log line 1177). Restore: `cp resource_billing_budget.go.bak $F` -> `RESTORED`, `grep -n "billingBudgetSpendCapAddedCustomizeDiff,"` -> `150:`, `cmp` -> `cmp identical`.

### T4. Flatten simplification

Generated flatten (tpgb resource_billing_budget.go:1448-1455): the only branches are `original["inputState"]` (API), `d.GetOk("spend_cap.0.input_state")` (state/config), else `"CONFIGURED"`; no `outputState` reference remains in the input_state resolution (`outputState` is only copied to `output_state` on line 1457). Direct API probe (scratchpad r3-api-probe2.log) confirms the API never returns `inputState`: `POST spendCap field: {'outputState': 'CONFIGURED'}`, `GET spendCap field: {'outputState': 'CONFIGURED'}`, so the first branch is future-proofing only.

Import of a capped budget: covered by the `ImportState: true, ImportStateVerify: true` steps (resource_billing_budget_test.go step 2 and 4 of spendCapUpdate, step 3 of spendCapAdd, and the generated example test), all PASS in beta and GA; the import path hits the `else { inputState = "CONFIGURED" }` branch and ImportStateVerify finds no difference against the `CONFIGURED` config.

### T5. Descriptions

Read /home/user/tpgb/website/docs/r/billing_budget.html.markdown lines 368-383 (`spend_cap`) and 592-616 (`input_state`). Checked against https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps (the URL in the brief, cloud.google.com/billing/docs/how-to/spend-cap, redirects to docs.cloud.google.com and 404s; the budgets-spend-caps page is the one linked from the description) and the v1 discovery document.

Correct and verified:
- "A spend cap cannot be added to an existing budget. Adding the block replaces the budget." Public doc: "You can't edit an existing alerts-only budget to convert it to a spend cap enforcement budget."; API probe above.
- "Removing the spend_cap block converts the budget back to an alerts-only budget." Discovery: "To convert a spend cap budget to a regular budget, specify `spend_cap` in the `update_mask` and omit `spend_cap` from the budget in the request."; test verified.
- "While output_state is ENFORCED, only input_state can be changed." Discovery, verbatim.
- "Set AWAITING_NEXT_PERIOD only while output_state is ENFORCED; in any other state the API returns a generic 400 INVALID_ARGUMENT." Probe: from `outputState: CONFIGURED`, PATCH `inputState=AWAITING_NEXT_PERIOD` -> `"message": "Request contains an invalid argument.", "status": "INVALID_ARGUMENT"`.
- "The API rejects a spend cap budget whose project and service match an existing spend cap budget." Public doc: "We have a deduplication policy that prevents users from creating more than one budget with the same scope."

Misleading / incomplete (see findings F1, F2, F5):
- "After the next period starts the API resets output_state to CONFIGURED; set input_state back to CONFIGURED then ..." implies the user may wait until the next period. The discovery doc says for `AWAITING_NEXT_PERIOD`: "Not allowed if the spend cap is in state `AWAITING_NEXT_PERIOD`" and for `CONFIGURED`: "If the spend cap is in state `AWAITING_NEXT_PERIOD`, `input_state` must be set to `CONFIGURED`". So the user must set `CONFIGURED` back before any other update of the budget, already while the cap is lifted, not only after the next period; otherwise the re-sent `AWAITING_NEXT_PERIOD` is rejected.
- "A cap lifted outside Terraform ... does not produce a diff on this field." True, but the consequence is unstated: the next Terraform update of any field re-sends `input_state = CONFIGURED`, which the discovery doc describes as "valid when updating (`UpdateBudget`) to activate the spend cap". That may silently re-activate a cap someone lifted in the console. Not verifiable here (needs a cap that is actually enforced, which needs real spend). Record as ambiguity.
- The public doc also says "You can't delete a spend cap budget while it's enforced." That matters for Terraform (destroy and the new replacement path both fail while enforced) and is not mentioned.
- Rendering: mmv1 collapses the blank line inside the description, so the `input_state` entry renders as one 15-line paragraph that mixes API behaviour, Terraform behaviour and HTTP details.

### T6. Upstream fit (b1edf518a..1c847590d -- mmv1/)

- custom_diff vs ForceNew on the field: `immutable: true` on `spendCap` would also force replacement on removal and on `input_state` changes (needed to lift a cap), so a conditional `ForceNew` in a CustomizeDiff is the right tool and is exactly what docs/content/best-practices/immutable-fields.md prescribes ("call `diff.ForceNew` inside a `CustomizeDiff` if the appropriate conditions to allow update in place are not met"). The same page says "Any `CustomizeDiff` function like this must be thoroughly unit tested." There is no unit test (finding F3). The function takes `*schema.ResourceDiff`, so it cannot be driven by `tpgresource.ResourceDiffMock` (mmv1/third_party/terraform/tpgresource/resource_test_utils.go:85) as spanner_database and container do.
- `%{service}` parameterisation: fine; follows `acctest.Nprintf` conventions, and the comment on TestAccBillingBudget_spendCapUpdate documents which service each test owns. Service IDs are stable public SKUs.
- Test count: three spend-cap acceptance tests at 30-60 s each are cheap. TestAccBillingBudget_spendCapAdd could be folded into spendCapUpdate as a final "re-add, expect Replace" step after the removal step, which would drop one test and one reserved service with no coverage loss (optional, finding F7).
- CI risk specific to this resource: Budget.yaml has `exclude_sweeper: true`, and the API deduplicates one spend cap per project+service. A test that fails between create and destroy leaves a capped budget that permanently blocks that project+service for every later run until someone deletes it by hand. Also, if GA and beta nightlies run against the same project and billing account concurrently, the same three services collide between the two providers (finding F6).
- Upstream PR #19315 (fetched from the public PR page; the GitHub API is not reachable from this session): title "billingbudgets: add spend_cap to google_billing_budget", open, author DrFaust92, release note "billingbudget: added `spend_cap` field to `google_billing_budget` resource". The latest reviewer comment reports the example test failing on the CI account with "Error creating Budget: googleapi: Error 400: Request contains an invalid argument." and the author asks whether MASTER_BILLING_ACCT is spend-cap eligible. If the CI billing account is not eligible, all three tests here fail in CI regardless of this change set (finding F8).
- Release note: b1edf518a is the PR author's last commit, so this change set sits on #19315 before it merges; `spend_cap` has never shipped, so there is no user-visible bug to note and the single `release-note:enhancement` covers it (the product prefix there should be `billingbudgets`, the folder name, per docs/content/code-review/release-notes.md). Only if this lands as a separate PR after #19315 merges does it need `release-note:bug` ("billingbudgets: fixed updates of `google_billing_budget` with `spend_cap` and the perma-diff on `spend_cap.input_state`") plus a `release-note:note` that adding `spend_cap` now replaces the budget.
- Description length: the `input_state` text is long for an mmv1 field description and includes HTTP status wording; a maintainer is likely to ask for the shorter text in F1.

## Findings

| # | Severity | File:line | Finding and proposed fix |
|---|---|---|---|
| F1 | medium (doc correctness) | mmv1/products/billingbudgets/Budget.yaml:581-590 (`input_state` description) | "After the next period starts ... set `input_state` back to `CONFIGURED` then" implies waiting is fine; the discovery doc rejects `AWAITING_NEXT_PERIOD` as soon as the cap is in state `AWAITING_NEXT_PERIOD`, so every other update during the lifted period fails too. Replace lines 581-590 with: "The desired state of the spend cap. Must be `CONFIGURED` on create. Set to `AWAITING_NEXT_PERIOD` to lift an enforced cap until the next period starts; the API accepts it only while `output_state` is `ENFORCED` and otherwise returns `INVALID_ARGUMENT`. Set it back to `CONFIGURED` before changing any other field of the budget, because every update of a capped budget re-sends this field and `AWAITING_NEXT_PERIOD` is rejected once the cap is no longer enforced." |
| F2 | medium (ambiguity, unverifiable here) | mmv1/products/billingbudgets/Budget.yaml:591-594; mmv1/templates/terraform/custom_flatten/billing_budget_spend_cap.go.tmpl:23-25 | With the simplified flatten, a cap lifted in the console is invisible on `input_state`; the next Terraform update of any field re-sends `input_state = CONFIGURED`, which the API documents as "valid ... to activate the spend cap", i.e. it may silently re-enforce the lifted cap. Either verify against an enforced cap, or state it: append to the description "If the cap was lifted outside Terraform (`output_state` is `AWAITING_NEXT_PERIOD`), the next update made by Terraform sends `CONFIGURED`, which re-activates the cap." |
| F3 | medium (maintainer requirement) | mmv1/templates/terraform/constants/billing_budget.tmpl:23-35 | No unit test for the CustomizeDiff; docs/content/best-practices/immutable-fields.md requires one. Split into `func billingBudgetSpendCapAdded(d tpgresource.TerraformResourceDiff) error` (the `GetChange`/`ForceNew` part) called from the `*schema.ResourceDiff` wrapper that keeps the `d.Id() == ""` guard, and add `TestBillingBudgetSpendCapAddedCustomizeDiff` in mmv1/third_party/terraform/services/billingbudgets/resource_billing_budget_test.go using `tpgresource.ResourceDiffMock{Before: ..., After: ...}` for the four cases (none->none, none->block, block->none, block->block) asserting `IsForceNew`. |
| F4 | low | mmv1/templates/terraform/constants/billing_budget.tmpl:30-31 | `o.([]interface{})` / `n.([]interface{})` are unchecked. Safe for a schema key in SDK 2.40.1 (zero value is `[]interface{}{}`), but the in-repo precedent (constants/spanner_database.go.tmpl:71-75) nil-guards. Use `oldCap, _ := o.([]interface{}); newCap, _ := n.([]interface{})`. |
| F5 | low (doc completeness) | mmv1/products/billingbudgets/Budget.yaml:569-573 | Add after "only `input_state` can be changed.": "The budget cannot be deleted while `output_state` is `ENFORCED`; lift the cap first." (public doc: "You can't delete a spend cap budget while it's enforced"). Relevant because the new replacement path deletes the budget. |
| F6 | medium (CI robustness) | mmv1/products/billingbudgets/Budget.yaml:41 (`exclude_sweeper: true`) and the three test service IDs | A failed run leaves a capped budget that blocks its project+service for all later runs (dedup policy, no sweeper); GA and beta suites sharing one project would also collide on the same services. Mitigation: a sweeper for `google_billing_budget` filtered to `display_name` prefix `tf-test`/`Example Spend Cap Budget`, or at least a note in the test comment; consider different services per provider if the suites share a project. |
| F7 | low (optional) | mmv1/third_party/terraform/services/billingbudgets/resource_billing_budget_test.go:757-790 | TestAccBillingBudget_spendCapAdd can become the final two steps of TestAccBillingBudget_spendCapUpdate (after removal: `testAccBillingBudget_spendCap(contextRemoved)` with `ExpectResourceAction(..., ResourceActionReplace)`, then import). Drops one test and the Cloud Run service reservation. |
| F8 | high (external, blocks CI) | upstream PR #19315 review thread | The reviewer reports the spend-cap example failing on the CI billing account with 400 INVALID_ARGUMENT at create. If MASTER_BILLING_ACCT is not spend-cap eligible, all three tests fail in CI. Not fixable in this change set; must be resolved with the maintainers before merge. Do not skip the tests. |
| F9 | low (release note) | PR description | Keep a single `release-note:enhancement` in #19315 with product prefix `billingbudgets` (folder name). A `release-note:bug` is needed only if this lands as a separate PR after #19315 merges. |

## Verdict

Needs changes (documentation and testing), not broken. The code does what it claims: the CustomizeDiff forces replacement exactly when a block is added to an existing budget and nowhere else, the flatten gives `CONFIGURED` on import and no perma-diff, and the pre_update hook produces the masks the API needs; beta (3/3) and GA (2/2) acceptance tests pass, GA builds, vets and is gofmt-clean, and the negative control fails as expected. Before upstreaming: F1 (misleading `input_state` text), F3 (unit test the CustomizeDiff, a stated maintainer requirement), and settle F8 with the maintainers; F2 should be verified or documented.

## Leftover GCP resources

None. `GET https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets` returned `{}` before the runs, after the beta run, after the negative control, after each probe (both probe budgets deleted: `DELETE` -> `{}`), and after the GA run. All amounts used were 5-7 PLN.

## Changes outside /home/user/tpgb, /home/user/tpg and the scratchpad

- /home/user/terraform-provider-google: new symlink -> /home/user/tpg (required by T2).
- /home/user/review-fix-round3.md: this report.
- Transient logs created under /home/user during the run (tpg-clone.log, tpg-generate.log, tpg-build.log, r3-*.log, resource_billing_budget.go.bak, tpg-test.go.generated) were moved into the scratchpad at the end; nothing else under /home/user was touched. /home/user/magic-modules: no changes (`git status --short` empty, no stash, no git write commands).
- Inside the allowed areas: /home/user/tpg is a fresh clone at 4abc5c96 with the GA generation output plus the PLN test edits in google/services/billingbudgets/resource_billing_budget_test.go (uncommitted); /home/user/tpgb generated file was modified for the negative control and restored byte-identical.
