# Handover: upstream PR 19315 (`google_billing_budget.spend_cap`)

Read this file first. It is enough to continue the work on a local machine from this branch alone.

- Branch: `claude/great-galileo-1gggv5` on the fork `pepsi133/magic-modules`. It is a public draft. Never merge it.
- Owner: Robert Żegleń (rzeglen@gmail.com, GitHub `pepsi133`).
- Upstream PR: [GoogleCloudPlatform/magic-modules#19315](https://github.com/GoogleCloudPlatform/magic-modules/pull/19315),
  by DrFaust92 (Ilia Lazebnik), branch `DrFaust92:billingbudget-spend-cap`, head `b1edf518a`.
- Issue: [hashicorp/terraform-provider-google#28575](https://github.com/hashicorp/terraform-provider-google/issues/28575).
- All real identifiers (project, billing account, org) live only in the owner's local `.env`, which sits outside the
  repository in the parent directory of the clone. Every committed file
  uses `${GOOGLE_PROJECT}`, `${GOOGLE_PROJECT_NUMBER}`, `${GOOGLE_ORG}`, `${GOOGLE_BILLING_ACCOUNT}` or
  `<other-project-N>` instead.

## a. Purpose and status (2026-10-28)

PR 19315 adds a `spend_cap` block to `google_billing_budget`. A maintainer blocked it because the generated test
`TestAccBillingBudgetsBudget_billingBudgetSpendCapExample` fails in upstream CI with a bare
`400 Request contains an invalid argument.` on create. We found that the PR's request shape is valid and that the
400 comes from the CI environment: the CI master billing account is a parent (reseller-style) account, and spend
caps exclude those. We also found three real bugs that would fail the PR right after the 400 is gone: a permadiff on
`input_state`, a wrong update mask on every update of a capped budget, and an update plan that the API refuses when a
cap is added to an existing budget. These are fixed on this branch, tested end to end on a real organization, and
reviewed adversarially in four rounds. What remains: the round-4 description fixes, the clean branches, and every
GitHub write (fork PR, two upstream draft PRs, one comment, subscriptions). Each GitHub write needs the owner's
approval first.

## b. Branch anatomy

Base: `28366ed79` (upstream `main` at the point where PR 19315 branched).
Listed oldest first. "mmv1" means the commit changes provider code; "investigation" means only files in this directory.

| Commit | Author | Touches | Summary |
|---|---|---|---|
| `ef20c8beb` | Ilia Lazebnik (DrFaust92) | mmv1 | **Upstream PR commit, untouched.** Adds `spend_cap` to `Budget.yaml` and the `billing_budget_spend_cap` sample. |
| `b1edf518a` | Ilia Lazebnik (DrFaust92) | mmv1 | **Upstream PR commit, untouched.** Fixes the sample service and makes `spend_basis` explicit. Head of PR 19315. |
| `2a441756e` | Claude | mmv1 | **Code fix 1.** Custom flatten for `input_state`; `pre_update` hook that adds `spendCap.inputState` to every mask; test `TestAccBillingBudget_spendCapUpdate`. |
| `5d93a7ccc` | Claude | mmv1 | **Code fix 2.** Mask `spendCap` on removal; one service per spend-cap test; descriptions. |
| `f5b84d80a` | Claude | mmv1 | **Code fix 3.** CustomizeDiff ForceNew when a cap is added; flatten simplified; test `TestAccBillingBudget_spendCapAdd`. |
| `96a871a60` | Claude | mmv1 | **Code fix 4.** CustomizeDiff split for unit testing; `TestUnitBillingBudget_spendCapAddedCustomizeDiff`; descriptions. |
| (this commit) | Claude | investigation | The whole investigation directory: reports, probes, test results, reviews, handover, `.env.example`. |

The code fixes are `2a441756e`, `5d93a7ccc`, `f5b84d80a`, `96a871a60`. They change only `mmv1/`, and all of them go to
the clean branch.

History rewrite (2026-10-28): the branch was rewritten to remove real identifiers from old commits. The code-fix
commits kept their content and lost only their `investigation/` parts. The investigation commits were squashed into
one. The reports and reviews still name the old SHAs. Use this map:

| Old SHA | New SHA |
|---|---|
| `cc69ec67b` | `2a441756e` |
| `c3a311883` | `5d93a7ccc` |
| `1c847590d` | `f5b84d80a` |
| `fa51fc864` | `96a871a60` |
| `653070aa6`, `942f37d7a`, `9d3b20b7d`, `4576291e4`, `965502a5d` | squashed into this commit |
Files changed under `mmv1/` relative to `b1edf518a`:

- `mmv1/products/billingbudgets/Budget.yaml`
- `mmv1/templates/terraform/constants/billing_budget.tmpl`
- `mmv1/templates/terraform/custom_flatten/billing_budget_spend_cap.go.tmpl` (new)
- `mmv1/templates/terraform/pre_update/billing_budget.go.tmpl` (new)
- `mmv1/third_party/terraform/services/billingbudgets/resource_billing_budget_test.go`
- `mmv1/third_party/terraform/services/billingbudgets/resource_billing_budget_internal_test.go` (new)

## c. Root cause and evidence

All of this was verified end to end on a real Google Cloud organization with a first-party, self-serve,
spend-cap-eligible billing account in a non-USD currency. The account has no parent and no subaccounts, and it bills
the test project directly.

### Why upstream CI fails (environmental, not the PR)

- The PR's request is valid. The exact body the provider sends for the sample is accepted (`probe-findings.md`,
  probe (g)). The only change is the currency, which must match the account.
- The API returns the bare 400 (no details) for only four inputs (`reviews/review-root-cause.md`, section A1):
  1. A currency that is not the account's currency (probes (h), R1, R2).
  2. A project in the filter that the budget's account does not bill, by ID or by number (`acctest-findings.md`
     section 3; `reviews/review-root-cause.md` N1 to N4).
  3. A spend cap `inputState` other than `CONFIGURED` on create (I1 to I3).
  4. An update mask on a capped budget without `spendCap.inputState` (U2).
- Every other spend-cap rule fails with a descriptive message (thresholds, notifications, period, credits, service,
  overlap, and so on). So the PR's sample is not breaking a spend-cap field rule.
- Upstream, 11 of 12 budget tests pass in replay, all with USD and `GOOGLE_PROJECT` on the master account. So (1) and
  (2) do not explain the failure for regular budgets.
- `TestAccBillingBudget_billingFilterSubaccounts` passes in replay and creates a subaccount under the master account.
  So the CI master billing account is a parent (reseller-style) account. Google's docs say spend caps are "limited to
  first-party Google Cloud customers and Cloud Billing accounts" and that reseller accounts are out of scope.
- Conclusion: the CI master billing account is not spend-cap eligible (or the CI project is billed through a
  subaccount rather than directly). Only maintainers can confirm this, because only they can see the CI account.
- Refuted: `notificationsRule.schemaVersion` (accepted and dropped by the API), the service ID, output-only fields,
  API version, IAM, and duplicate budgets (those give a descriptive error).

### Code change 1: custom flatten for `input_state` (permadiff)

- Problem: the API never returns `spendCap.inputState`. It returns only `outputState` (and `reconciling` when true).
  The generated flatten returned the empty API value, so every plan after apply wanted `+ input_state = "CONFIGURED"`.
- Fix: `custom_flatten/billing_budget_spend_cap.go.tmpl`. Use the API value if it is ever present, else the value
  from state or config, else `CONFIGURED` (import).
- Why not `ignore_read`: it would leave `input_state` empty on import for a required field, so ImportStateVerify would
  need an ignore flag (a test-dodging flag under the repo ground rules) and imported budgets would show a diff.
- Proof: `acctest-findings.md` section 2 (test fails with the non-empty plan before the fix);
  `fix-test-results.md` "Results" (all three steps pass after the fix, including import verify).
- Without it: `billingBudgetSpendCapExample` fails at step 1/3 with "the non-refresh plan was not empty"
  (reproduced again in `reviews/review-root-cause.md` A3, run 1).

### Code change 2: `pre_update` hook for the update mask

- Problem: once a budget is a spend cap, the API rejects any PATCH whose mask lacks `spendCap.inputState` (or
  `spendCap`). The generated code adds `spendCap.inputState` only when `spend_cap` itself changes. So changing only
  `amount` or `display_name` on a capped budget failed. Removing the block sent `spendCap.inputState` with no
  `spendCap` in the body, which also failed; the API clears a cap only when the mask names `spendCap`.
- Fix: `pre_update/billing_budget.go.tmpl`. When the cap is set and the mask is not empty, append
  `spendCap.inputState`. When the block was removed, replace `spendCap.inputState` with `spendCap`.
- Proof: `probe-findings.md` probes (c-u1) and (c2); `fix-test-results.md` "Update test" and Round 2/3 PATCH lines;
  `reviews/review-root-cause.md` U1 to U4.
- Without it: `TestAccBillingBudget_spendCapUpdate` fails at the amount-only step with the bare 400
  (`reviews/review-fix.md` B5, hook deleted). With the removal branch broken, it fails at the removal step
  (`reviews/review-fix-round2.md` R4).

### Code change 3: CustomizeDiff ForceNew when a cap is added

- Problem: the API refuses to turn an alerts-only budget into a capped one:
  `400 FAILED_PRECONDITION "Cannot transition a regular budget to a spend cap budget."` Google's page says the same.
  The provider planned this as an in-place update. `immutable: true` is wrong here: removal and lifting a cap are
  valid in-place updates.
- Fix: `billingBudgetSpendCapAddedCustomizeDiff` in `constants/billing_budget.tmpl`, registered with `custom_diff` in
  `Budget.yaml`. It forces replacement only when an existing budget goes from no cap to a cap.
- Proof: `reviews/review-fix-round2.md` R1 (API refusal), `fix-test-results.md` Round 3 (replace step: DELETE then
  POST, no PATCH) and Round 4 (unit test, 6 subtests, beta and GA).
- Without it: `TestAccBillingBudget_spendCapAdd` fails with "expected Replace, got action(s): [update]"
  (`reviews/review-fix-round3.md` T3). Unit-test mutations fail as expected (`fix-test-results.md` Round 4;
  `reviews/review-fix-round4.md` check 2).

### Code change 4: descriptions

- `spend_cap`: one cap per project and service; no delete while enforced; removing the block converts to an
  alerts-only budget; adding the block replaces the budget.
- `input_state`: `AWAITING_NEXT_PERIOD` only while `ENFORCED`; the API does not return the field; import uses
  `CONFIGURED`.
- Sources: the Discovery document (rev 20261018) and docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps,
  quoted in `report.md` section 2 and the reviews. Round 4 found wording problems that are still open (section g).

## d. Decisions made by the owner

These are the owner's decisions. Follow them as written.

1. **Sample stays unchanged on this draft branch.** No billing-account change and no `exclude_test` here.
   Maintainers choose between the variants.
2. **The five-step plan.**
   1. Finish the code fixes on this branch [done]. Run tests on own infrastructure with a local PLN edit only.
      Run an adversarial review before anything leaves the fork [done, 4 rounds].
   2. **"PR to the PR" (priority).** Make a clean branch on `pepsi133/magic-modules`, based on
      `DrFaust92:billingbudget-spend-cap`, holding only the code-fix commits. Open a PR against
      `DrFaust92/magic-modules`, base `billingbudget-spend-cap`. The body has the root cause, the evidence, links to
      this draft branch and this investigation directory, the test results, and an offer to adjust.
   3. **Two upstream DRAFT PRs** on `GoogleCloudPlatform/magic-modules`. Each one is DrFaust92's two commits plus the
      code fixes.
      - Variant A: the sample moves to `BILLING_ACCT` with its own `google_project` (`org_id` ORG_ID,
        `billing_account` BILLING_ACCT, `deletion_policy` DELETE). The budget filters on that project.
        `currency_code` is omitted (the schema allows it: `default_from_api`).
      - Variant B: the sample stays on `MASTER_BILLING_ACCT` with `exclude_test: true` and an adjacent comment (spend
        caps need a first-party billing account; the CI master account is a parent account). Attach the passing
        acceptance log as manual proof.
      - Each body says it builds on PR 19315, exists only as an example for it, and that PR 19315 has priority.
      - No review requests, no reviewers, no pinging maintainers.
   4. **One comment on GoogleCloudPlatform/magic-modules#19315.** Root cause with evidence; link to the fork PR for
      the fixes; links to variants A and B; ask the reviewer to pick based on which CI account is spend-cap
      eligible. Say the fix commits are ready to be taken. Ask for a `Co-authored-by` trailer with the owner's name
      if the idea is taken without the commits. Do not resolve threads.
   5. **Subscribe** to PR 19315, the fork PR and both drafts. Report only when a decision is needed.
3. **Ask the owner before EVERY GitHub write.** This covers PR creation, comments, and pushes to anything other than
   this draft branch.
4. **Authorship for the clean branches.** Commits are authored by Robert Żegleń <rzeglen@gmail.com>. They stay
   UNSIGNED (later owner decision; this replaces the earlier "signed" instruction). NO AI trailers, no
   `Claude-Session` trailer, and no session URLs in any commit or PR body made locally. Add
   `Co-authored-by: Ilia Lazebnik <ilia.lazebnik@gmail.com>` to every commit that touches the PR's files. DrFaust92's commits stay untouched at the base with full attribution.
5. **PR bodies and comments.** Any agent drafting them must first load and follow the `visual-pr` and `show-me`
   skills from the humanlayer repository (github.com/humanlayer/humanlayer), or local copies if installed.
6. **Public materials describe the test org only by properties** (first-party, self-serve, non-USD, spend-cap
   eligible), never by IDs. All IDs live in the owner's local `.env` (parent directory, outside the repository).
7. **PR bodies must state** the justification of each change (section c) and that everything was verified end to end
   on a real organization.
8. **Secrets.** Scan every commit for tokens and keys before pushing. The fork is public.

## e. Local setup

Paths below use `<parent>` for the directory that holds the magic-modules clone, `.tools/` and `.env`.

### Tools and accounts

- Go 1.26 or newer. Locally it comes from `<parent>/.tools/env.sh`: run `. <parent>/.tools/env.sh` in every shell.
- `terraform`, `gcloud`, `gh`, `git`, `jq`, `curl`.
- No bazel: `make` must run with `USE_BAZEL=0` (the default inside a worktree; pass it explicitly elsewhere).
- Sign the Google CLA with rzeglen@gmail.com (cla.developers.google.com). The email must also be verified on GitHub
  account `pepsi133` (see section g).
- IAM: Billing Account Administrator on the test billing account (includes `billing.budgets.configureSpendCap`).

### Checkouts

```bash
cd <parent>
git clone https://github.com/pepsi133/magic-modules.git
cd magic-modules
git remote add upstream https://github.com/GoogleCloudPlatform/magic-modules.git
git remote add drfaust92 https://github.com/DrFaust92/magic-modules.git
git fetch origin && git fetch upstream && git fetch drfaust92
git worktree add ../mm-spendcap claude/great-galileo-1gggv5   # work in a worktree, per AGENTS.md

mkdir -p "$GOPATH/src/github.com/hashicorp" && cd "$GOPATH/src/github.com/hashicorp"
git clone https://github.com/hashicorp/terraform-provider-google-beta.git
git -C terraform-provider-google-beta checkout 7e21030c       # matches mm base 28366ed79
git clone https://github.com/hashicorp/terraform-provider-google.git
git -C terraform-provider-google checkout 4abc5c96            # matches mm base 28366ed79
```

`OUTPUT_PATH` must end in `terraform-provider-google` or `terraform-provider-google-beta`, or the generator drops the
copyright headers. The `$GOPATH/src/github.com/hashicorp/...` layout already satisfies this. If a checkout ever lives
under another name (the cloud session used `tpgb`), point a symlink with the right name at it and use the symlink as
`OUTPUT_PATH`.

```bash
export TPGB="$GOPATH/src/github.com/hashicorp/terraform-provider-google-beta"
export TPG="$GOPATH/src/github.com/hashicorp/terraform-provider-google"
```

### Environment and auth

```bash
. <parent>/.tools/env.sh
set -a; . <parent>/.env; set +a                     # template: investigation/pr-19315-spend-cap/.env.example
export CLOUDSDK_CONFIG=<parent>/.gcloud             # isolated gcloud config, separate from your personal one
gcloud auth activate-service-account --key-file=<path-to-service-account-key.json>
```

- The real `.env` lives in `<parent>`, outside the repository, so git never sees it. If a copy ever has to sit inside
  the repo, add its path to `.git/info/exclude`. Do not edit the repo `.gitignore`.
- No ADC (owner decision). Export `GOOGLE_CREDENTIALS=<path-to-service-account-key.json>` only in the shell that runs
  acceptance tests, and unset it afterwards.
- `GOPROXY=direct` was needed only behind the cloud session's proxy. Do not set it locally unless downloads fail.

### Generate

`make provider` cleans the downstream checkout first, so it erases the local PLN edits. Re-apply them after each
generation.

```bash
cd <parent>/mm-spendcap
make provider USE_BAZEL=0 VERSION=beta OUTPUT_PATH="$TPGB" PRODUCT=billingbudgets
make provider USE_BAZEL=0 VERSION=ga   OUTPUT_PATH="$TPG"  PRODUCT=billingbudgets
```

### LOCAL-ONLY currency edit

The committed tests use USD. On a non-USD account every budget create with USD fails with the bare 400. Edit only the
downstream copies, never `mmv1/`. Replace `PLN` with your account's currency.

```bash
cd "$TPGB/google-beta/services/billingbudgets"   # GA: cd "$TPG/google/services/billingbudgets"
sed -i 's/currency_code = "USD"/currency_code = "PLN"/' resource_billing_budget_generated_test.go resource_billing_budget_test.go
sed -i 's/units         = "100"/units         = "5"/'   resource_billing_budget_generated_test.go
sed -i -e 's/"units":\( *\)"100"/"units":\1"5"/' -e 's/"units":\( *\)"200"/"units":\1"6"/' \
       -e 's/"units":\( *\)"300"/"units":\1"7"/' -e 's/specified_amount.0.units", "300"/specified_amount.0.units", "7"/' \
       resource_billing_budget_test.go
git diff --stat        # only these two test files may differ from the generated output
```

Check the result by hand: the spend-cap example and basic example use 5; `spendCapUpdate` uses 5, 6, 7; `spendCapAdd`
uses 5; `billingBudgetUpdate` uses PLN.

### Run the tests

The API allows one spend cap per project and service. The three spend-cap tests each own one service, so they can run
in parallel:

- `billing_budget_spend_cap` sample: `C7E2-9256-1C43` (Gemini Enterprise Agent Platform)
- `TestAccBillingBudget_spendCapUpdate`: `AEFD-7695-64FA` (Gemini API)
- `TestAccBillingBudget_spendCapAdd`: `152E-C115-5142` (Cloud Run)

Calling `go test` directly avoids make's `$` escaping:

```bash
cd "$TPGB"
export GOOGLE_CREDENTIALS=<path-to-service-account-key.json>   # only for the test run
go test ./google-beta/services/billingbudgets/ -run '^TestUnit' -v
TF_ACC=1 TF_ACC_REFRESH_AFTER_APPLY=1 go test ./google-beta/services/billingbudgets/ -v -timeout 60m \
  -run '^TestAccBillingBudget(sBudget_billingBudgetSpendCapExample|_spendCapUpdate|_spendCapAdd)$'
# regression
TF_ACC=1 TF_ACC_REFRESH_AFTER_APPLY=1 go test ./google-beta/services/billingbudgets/ -v -timeout 60m \
  -run '^TestAccBillingBudget(sBudget_billingBudgetBasicExample|_billingBudgetUpdate)$|^TestBillingBudgetStateUpgradeV0$'
unset GOOGLE_CREDENTIALS
```

With make, `$` must reach make as `$$`, so write `\$\$` inside double quotes:

```bash
make testacc TEST=./google-beta/services/billingbudgets \
  TESTARGS="-run='^TestAccBillingBudget(sBudget_billingBudgetSpendCapExample|_spendCapUpdate|_spendCapAdd)\$\$'"
```

A bare `$$` in the shell expands to the shell PID and runs no tests.

Add `TF_LOG=DEBUG` to capture requests. Before sharing a log, scan it. The brackets in the patterns here and in
section f only stop this file from matching its own scan; the regex is the same. Run `grep -nE 'ya2[9]|private[_]key|BEGIN PRIVAT[E]|AI[z]a|Bearer'`.

Expected PASS set:

- `TestUnitBillingBudget_spendCapAddedCustomizeDiff` (6 subtests), beta and GA
- `TestAccBillingBudgetsBudget_billingBudgetSpendCapExample`
- `TestAccBillingBudget_spendCapUpdate`
- `TestAccBillingBudget_spendCapAdd`
- `TestAccBillingBudgetsBudget_billingBudgetBasicExample`, `TestAccBillingBudget_billingBudgetUpdate`,
  `TestBillingBudgetStateUpgradeV0` (regression)

Not expected to pass on a plain first-party account: tests that need subaccounts
(`billingFilterSubaccounts`) or project creation rights (`budgetFilterProjectsOrdering`).

### Leftover budgets

Budgets are not swept (`exclude_sweeper: true`). A leaked cap blocks that project and service for later runs
(overlap error). Check before and after every run:

```bash
gcloud billing budgets list --billing-account="$GOOGLE_BILLING_ACCOUNT" --format='table(name,displayName,spendCap)'
gcloud billing budgets delete "<budget-id>" --billing-account="$GOOGLE_BILLING_ACCOUNT"
```

An `ENFORCED` cap cannot be deleted. Lift it first (PATCH `inputState=AWAITING_NEXT_PERIOD`).

## f. Clean-branch recipe

Do this only after the round-4 description fixes are committed on this draft branch (section g). Add that commit's
SHA to the list below. Ask the owner before each push.

### 1. Fork PR branch (`fix/spend-cap-input-state-mask`)

```bash
cd <parent>/magic-modules
git fetch drfaust92 billingbudget-spend-cap
git rev-parse drfaust92/billingbudget-spend-cap        # must be b1edf518a...; if not, stop and ask the owner
git worktree add ../mm-fix -b fix/spend-cap-input-state-mask b1edf518a
cd ../mm-fix
git config user.name  "Robert Żegleń"
git config user.email "rzeglen@gmail.com"
for c in 2a441756e 5d93a7ccc f5b84d80a 96a871a60; do     # add the round-4 commit here
  git diff "$c^" "$c" -- mmv1 | git apply --index
  git commit --author="Robert Żegleń <rzeglen@gmail.com>" -F - <<MSG
$(git log -1 --format=%s "$c")

Co-authored-by: Ilia Lazebnik <ilia.lazebnik@gmail.com>
MSG
done
git log --format='%h %an <%ae> %s' b1edf518a..HEAD        # author must be the owner
git diff --stat b1edf518a..HEAD                          # must list only mmv1/ files
```

- `git diff -- mmv1 | git apply` takes only the `mmv1/` part of each commit. After the history rewrite the four
  code-fix commits touch only `mmv1/`, so `git cherry-pick` works too. Check that a later commit (for example the
  round-4 fix) does not also touch `investigation/`.
- Optional: squash into 1 to 3 logical commits (for example: flatten + mask; ForceNew on add + tests; descriptions).
  Keep the author and the `Co-authored-by` trailer on each one. Commits stay unsigned.
- Rewrite commit subjects if you like. Do not add AI trailers, a `Claude-Session` trailer or session URLs.

Before pushing:

```bash
make provider USE_BAZEL=0 VERSION=beta OUTPUT_PATH="$TPGB" PRODUCT=billingbudgets
# re-apply the local currency edit (section e), then run the unit test and the three spend-cap tests
git log -p b1edf518a..HEAD | grep -nE 'ya2[9]|private[_]key|BEGIN PRIVAT[E]|AI[z]a|client[_]secret|Claude-Sessio[n]|claude[.]ai/code' || echo clean
git push -u origin fix/spend-cap-input-state-mask        # ask the owner first
```

Then open the PR against `DrFaust92/magic-modules`, base `billingbudget-spend-cap` (ask first; follow decision 5).

### 2. Variant A branch (`spend-cap-variant-a`, on top of the fork PR branch)

Change `mmv1/templates/terraform/samples/services/billingbudgets/billing_budget_spend_cap.tf.tmpl`:

- Keep `data "google_billing_account" "account"`.
- Replace `data "google_project" "project" {}` with the pattern from
  `samples/services/identityplatform/identity_platform_config_minimal.tf.tmpl`:

  ```hcl
  resource "google_project" "project" {
    project_id      = "{{index $.ResourceIdVars "project_id"}}"
    name            = "{{index $.ResourceIdVars "project_id"}}"
    org_id          = "{{index $.TestEnvVars "org_id"}}"
    billing_account = "{{index $.TestEnvVars "billing_acct"}}"
    deletion_policy = "DELETE"
  }
  ```

- In the budget: `projects = ["projects/${google_project.project.number}"]`.
- In `amount.specified_amount`: delete `currency_code`, keep `units = "100"`.

Change the sample entry in `mmv1/products/billingbudgets/Budget.yaml` (key `resource_id_vars`, formerly `vars`):

```yaml
  - name: billing_budget_spend_cap
    primary_resource_id: budget
    steps:
      - name: billing_budget_spend_cap
        resource_id_vars:
          display_name: Example Spend Cap Budget
          project_id: spend-cap        # test value is tf-test-spend-cap<10 chars>; project IDs max 30 chars
        test_vars_overrides:
          display_name: '"Example Spend Cap Budget" + randomSuffix'
        test_env_vars:
          billing_acct: BILLING_ACCT
          org_id: ORG_ID
```

Notes: the service API does not need to be enabled for the cap to be created (`probe-findings.md`, H5). A spend cap
on a brand-new project was not tested (no project-create rights in the cloud session). Run the generated test on
your org before pushing.

### 3. Variant B branch (`spend-cap-variant-b`, on top of the fork PR branch)

Change only the sample entry in `Budget.yaml`:

```yaml
  - name: billing_budget_spend_cap
    primary_resource_id: budget
    # Spend caps need a first-party billing account. The CI master billing
    # account is a parent account, which the API rejects for spend caps.
    exclude_test: true
    steps:
      ...unchanged...
```

Attach the passing acceptance log (redacted) to the PR body as manual proof.

### PR bodies

Template: `.github/PULL_REQUEST_TEMPLATE.md`. Include:

```
Fixes hashicorp/terraform-provider-google#28575
```

```release-note:enhancement
billingbudgets: added `spend_cap` field to `google_billing_budget` resource
```

No session URLs or `Claude-Session` lines in the bodies. Each body states the justification of each change
(section c) and that it was verified end to end on a real organization (properties only, no IDs). The upstream drafts say they build on PR 19315, exist only as examples for
it, and that PR 19315 has priority.

## g. Not done / open

### First local task: description wording fixes from review round 4 (not yet applied)

The code and the unit test passed mutation testing in round 4 and need no change. Only the wording below is open.
Source: `reviews/review-fix-round4.md`. Apply on this draft branch, regenerate, re-run the tests, then build the
clean branch.

| # | Where | Finding | Proposed fix |
|---|---|---|---|
| 1 | `Budget.yaml` `input_state`, lines ~586-590 vs ~594-595 | The two passages contradict each other about when to set `CONFIGURED` back after a lift. | Restore "After the next period starts, set it back to `CONFIGURED`", and state the trade-off for edits made while the cap is lifted. |
| 2 | `Budget.yaml` `input_state`, lines ~594-595 | "Re-applying `CONFIGURED` after a cap was lifted outside Terraform may re-activate the cap" is ambiguous: a plain re-apply sends nothing. | Replace with "Any later Terraform update of the budget re-sends `input_state = CONFIGURED`, which may re-activate a cap lifted outside Terraform." |
| 3 | `Budget.yaml` `spend_cap`, delete sentence (~570-571) | Does not say the lift must be applied before `terraform destroy`. | Add "apply `input_state = AWAITING_NEXT_PERIOD` before destroying". |
| 4 | `Budget.yaml` `spend_cap` (~574-575) | Two sentences say that adding a block replaces the budget. | Merge into one: "Adding a `spend_cap` block to an existing budget replaces the budget." |
| 5 | `Budget.yaml` `spend_cap` (~569) | "only `input_state` can be changed while enforced" conflicts with the Google page (name, amount, project and service are editable). | Reword so it does not contradict the page. |
| 6 | `resource_billing_budget_internal_test.go` | No case for a missing or nil `Before` value. | Optional: add case `before: nil, after: configured, forceNew: true`. |

### Other open items

- **Owner's email not yet verified on GitHub.** rzeglen@gmail.com must be verified on account `pepsi133` before any
  clean branch is pushed. Otherwise commits are not attributed to the account and the CLA check fails.
- **All GitHub writes**: the fork PR, the two upstream drafts, the comment on 19315, and the subscriptions. Each needs
  the owner's approval first.
- **Is `BILLING_ACCT` in CI spend-cap eligible?** Unknown. Only maintainers can check. Variant A depends on it.
- **Handwritten spend-cap tests in CI (question for the owner).** `TestAccBillingBudget_spendCapUpdate` and
  `TestAccBillingBudget_spendCapAdd` use `GetTestMasterBillingAccountFromEnv` and `data "google_project"`. Neither
  variant changes them, so they would likely hit the same 400 in CI. The owner's plan does not cover this yet.
  Decide before opening the drafts: move them the same way in each variant, or leave them and say so in the bodies.
- **Re-arm after a lift is untestable** without real spend that enforces a cap. Whether re-sending `CONFIGURED`
  re-activates a lifted cap is unverified (round 2 F2, round 3 F2, round 4 F2).
- **GA acceptance tests** were run only for `spendCapAdd` and `spendCapUpdate` (plus the GA unit test). The spend-cap
  example and the regression tests ran on beta only.
- **Sweeper and overlap.** `exclude_sweeper: true` means a leaked cap blocks later runs on the same project and
  service. Delete it by hand (section e). A sweeper is a possible follow-up (round 3 F6).

## h. File index

- `HANDOVER.md`: this file.
- `README.md`: short overview from the first commit. Its H1 hypothesis (`schemaVersion`) was later refuted.
- `report.md`: first report: PR files, API research, generated request body, hypotheses H1 to H6. Superseded on H1.
- `probe.sh`: probe script with a gcloud token (USD bodies); reads the IDs from the environment.
- `probe-proxy.sh`: the probe script actually run (proxy-injected auth, currency from `SPEND_CAP_CURRENCY`); reads
  the IDs from the environment.
- `probe-results-2026-10-28.txt`: raw output of `probe-proxy.sh` plus one control run (redacted).
- `probe-findings.md`: probe results and verdicts on H1 to H6; update-mask findings.
- `acctest-findings.md`: acceptance runs before the fix (USD 400, PLN permadiff), project-billing-link probe, CI wiring,
  sample fix proposal.
- `fix-test-results.md`: verification of each code fix, rounds 1 to 4.
- `.env.example`: variable names for the local `.env`.
- `reviews/review-root-cause.md`: adversarial review of the root cause, with 40 API probes.
- `reviews/review-fix.md`: review round 1 of `cc69ec67b` (removal bug, test overlap).
- `reviews/review-fix-round2.md`: review round 2 of `c3a311883` (add-cap refusal, flatten order).
- `reviews/review-fix-round3.md`: review round 3 of `1c847590d` (CustomizeDiff, GA run, docs).
- `reviews/review-fix-round4.md`: review round 4 of `fa51fc864` (unit test mutations, open wording fixes).
- `reviews/pr-conventions.md`: upstream PR conventions (template, release notes, CLA, stacking, drafts).
