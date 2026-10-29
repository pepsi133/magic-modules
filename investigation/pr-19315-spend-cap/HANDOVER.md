# Handover: upstream PR 19315 (`google_billing_budget.spend_cap`)

Read this file first. It is enough to continue the work on a local machine from this branch, together with the
owner's local files in `<parent>`.

- Branch: `claude/great-galileo-1gggv5` on the fork `pepsi133/magic-modules`. It is a public draft. Never merge it.
- Owner: Robert Żegleń (rzeglen@gmail.com, GitHub `pepsi133`).
- Upstream PR: [GoogleCloudPlatform/magic-modules#19315](https://github.com/GoogleCloudPlatform/magic-modules/pull/19315),
  by DrFaust92 (Ilia Lazebnik), branch `DrFaust92:billingbudget-spend-cap`, head `b1edf518a`.
- Issue: [hashicorp/terraform-provider-google#28575](https://github.com/hashicorp/terraform-provider-google/issues/28575).
- The real identifiers (project, billing account, org) are kept in the owner's local `.env`, which sits outside the
  repository in the parent directory of the clone. Every file in the current history of this branch uses
  `${GOOGLE_PROJECT}`, `${GOOGLE_PROJECT_NUMBER}`, `${GOOGLE_ORG}`, `${GOOGLE_BILLING_ACCOUNT}` or
  `<other-project-N>` instead. The history was rewritten as a best-effort cleanup (section b, decision 10). The
  review files contain paths of the cloud sandbox (its home directory and its `/tmp`
  scratchpad). Those are not personal identifiers.

## a. Purpose and status (2026-10-29)

PR 19315 adds a `spend_cap` block to `google_billing_budget`. A maintainer blocked it because the generated test
`TestAccBillingBudgetsBudget_billingBudgetSpendCapExample` fails in upstream CI with a bare
`400 Request contains an invalid argument.` on create. We found that the PR's request shape is valid and that the
400 comes from the CI environment. Our inference is that the CI master billing account is a parent account. The evidence
is that CI creates subaccounts under it. That it is a reseller account is not proven. The step from "parent account"
to "not spend-cap eligible" is unverified: Google documents only the first-party requirement and the reseller
exclusion (section c). We also found three real bugs that would fail the PR right after the 400 is gone: a permadiff on
`input_state`, a wrong update mask on every update of a capped budget, and an update plan that the API refuses when a
cap is added to an existing budget. These are fixed on this branch, tested end to end on a real organization, and
reviewed adversarially in four rounds. The round-4 description fixes are done (`f08a4efea`). The variant A sample
test passed on the test organization on 2026-10-29 (`fix-test-results.md`, Round 6). The owner decided how to handle
the handwritten spend-cap tests: variant A runs them on their own project (Round 8), and variant B makes them opt-in
through `GOOGLE_SPEND_CAP_BILLING_ACCOUNT` (Round 7).

Current state (section g): `origin` holds unsigned versions of the three clean branches and the draft branch at
`fec7403b0`. Locally the clean branches are final and signed (fix `1aec53029c`, variant A `19bf3bf26e`, variant B
`c24fbe4d0b`). They and the draft branch wait for one set of pushes that needs the owner's approval: a normal push of
the draft branch and a force-push with lease of each clean branch. The draft branch must be pushed before any PR
draft is posted, because the drafts link Rounds 6 to 8, which are not on `origin` yet. Four PR drafts exist
locally, none posted (section f, "PR bodies"). The next session follows section i.

What remains (section g, "Other open items"):

- The owner's review, and the owner's approval for the pending pushes (the three signed clean branches and the
  draft branch).
- Whether `BILLING_ACCT` in CI is spend-cap eligible. Only maintainers can check.
- Revoking the project creator role from the test service account once the upstream drafts are decided
  (decision 12).
- The GitHub writes that are not done yet (fork PR, two upstream draft PRs, one comment, subscriptions). Each of them
  needs the owner's approval first. All four bodies are drafted locally (section f, "PR bodies").

## b. Branch anatomy

Base: `28366ed79` (upstream `main` at the point where PR 19315 branched).
Listed oldest first. "mmv1" means the commit changes provider code; "investigation" means only files in this directory.

| Commit | Author | Touches | Summary |
|---|---|---|---|
| `ef20c8beb` | Ilia (Ilia Lazebnik, DrFaust92) | mmv1 | **Upstream PR commit, untouched.** Adds `spend_cap` to `Budget.yaml` and the `billing_budget_spend_cap` sample. |
| `b1edf518a` | Ilia Lazebnik (DrFaust92) | mmv1 | **Upstream PR commit, untouched.** Fixes the sample service and makes `spend_basis` explicit. Head of PR 19315. |
| `2a441756e` | Claude | mmv1 | **Code fix 1.** Custom flatten for `input_state`; `pre_update` hook that adds `spendCap.inputState` to every mask; test `TestAccBillingBudget_spendCapUpdate`. |
| `5d93a7ccc` | Claude | mmv1 | **Code fix 2.** Mask `spendCap` on removal; one service per spend-cap test; descriptions. |
| `f5b84d80a` | Claude | mmv1 | **Code fix 3.** CustomizeDiff ForceNew when a cap is added; flatten simplified; test `TestAccBillingBudget_spendCapAdd`. |
| `96a871a60` | Claude | mmv1 | **Code fix 4.** CustomizeDiff split for unit testing; `TestUnitBillingBudget_spendCapAddedCustomizeDiff`; descriptions. |
| `4ce4e87fe` | Claude | investigation | The whole investigation directory: reports, probes, test results, reviews, handover, `.env.example`. |
| `f08a4efea` | Claude | mmv1 | **Code fix 5.** Round-4 description wording; unit-test case with no prior value. |
| later investigation-only commits (`fec7403b0` and after) | Claude | investigation | Test results, status and handover updates. |

The code fixes are `2a441756e`, `5d93a7ccc`, `f5b84d80a`, `96a871a60`, `f08a4efea`. They change only `mmv1/`, and all of them go to
the clean branch.

History rewrite: the branch was rewritten on 2026-10-28 to remove real identifiers. This is a best-effort cleanup.
Pre-rewrite commits may still be reachable on GitHub by SHA, and the owner decided not to ask for a purge
(decision 10). The old-to-new map is in the owner's local notes (`<parent>/notes/history-rewrite.md`). The reports and
reviews now name the rewritten SHAs. Do not repeat the old SHAs in any file of this directory.

Files changed under `mmv1/` relative to `b1edf518a`:

- `mmv1/products/billingbudgets/Budget.yaml`
- `mmv1/templates/terraform/constants/billing_budget.tmpl`
- `mmv1/templates/terraform/custom_flatten/billing_budget_spend_cap.go.tmpl` (new)
- `mmv1/templates/terraform/pre_update/billing_budget.go.tmpl` (new)
- `mmv1/third_party/terraform/services/billingbudgets/resource_billing_budget_test.go`
- `mmv1/third_party/terraform/services/billingbudgets/resource_billing_budget_internal_test.go` (new)

## c. Root cause and evidence

All of this was verified end to end on a real Google Cloud organization with a spend-cap-eligible billing account
(spend caps are created on it) in a non-USD currency. That it is self-serve is owner-stated. That it is first-party
and not a reseller account is inferred: the account has no parent and no subaccounts (`probe-findings.md`, line 9:
`masterBillingAccount` is empty and no subaccounts exist). It bills the test project directly.

### Why upstream CI fails (environmental, not the PR)

- The PR's request is valid. The exact body the provider sends for the sample is accepted (`probe-findings.md`,
  probe (g)). The only change is the currency, which must match the account.
- Of the inputs probed, four give the bare 400 with no details (`reviews/review-root-cause.md`, section A1):
  1. A currency that is not the account's currency (probes (h), R1, R2).
  2. A project in the filter that the budget's account does not bill, by ID or by number (`acctest-findings.md`
     section 3; `reviews/review-root-cause.md` N1 to N4).
  3. A spend cap `inputState` other than `CONFIGURED` on create (I1 to I3).
  4. An update mask on a capped budget without `spendCap.inputState` (U2).

  An account-level condition (eligibility) could not be provoked with the test account. It remains a candidate
  explanation for CI (unverified, `reviews/review-root-cause.md`, lines 72-76).
- Every other spend-cap rule fails with a descriptive message (thresholds, notifications, period, credits, service,
  overlap, and so on). So the PR's sample is not breaking a spend-cap field rule.
- Upstream, 11 of the 12 budget tests in the PR's CI pass in replay. The one that fails is the spend-cap sample.
  Source: the modular-magician comments of Oct 13 and Oct 26 on PR 19315, "Total Tests 12, Passed 11"
  (`reviews/review-root-cause.md`, lines 83-84). Most of the 11 use USD and `GOOGLE_PROJECT` on the master account
  (seven samples hard-code USD and six filter on `data.google_project`, same file, lines 80-82). So (1) and (2) do not
  explain the failure for regular budgets.
- `TestAccBillingBudget_billingFilterSubaccounts` passes in replay and creates a subaccount under the master account.
  So the CI master billing account can create subaccounts. Inference: it is a parent account. That it is a reseller
  account is not proven. The Google page (docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps, fetched
  2026-10-29) says: "Spend cap budgets are limited to first-party Google Cloud customers. Reseller accounts are out
  of scope." It says nothing about parent accounts or subaccounts. So the step from "parent account" to "not spend-cap eligible" is unverified.
- More inference evidence, from the CI setup at `upstream/main` `d8e3fb7c1` (unchanged at `da2594fac`): `.ci/infra/terraform/main.tf:17-22`
  bills the CI project to `var.billing_account_id`, not to the master account. `.ci/infra/terraform/variables.tf:13-14`
  describes the master account as the one "that will be modified during tests, including the creation of
  subaccounts".
- Conclusion (inference, unverified): the CI master billing account is not spend-cap eligible, or the CI project is
  billed through a subaccount rather than directly. No Google document states either rule. Only maintainers can
  confirm this, because only they can see the CI account.
- Other account-level causes are not ruled out (owner decision of 2026-10-29 to record them):
  - A spend cap may need the budget's account to bill the project directly. The CI project is billed by
    `BILLING_ACCT` (`main.tf:17-22`), not by the master account. Regular budgets on a parent account do filter on
    such projects, but spend caps may not.
  - Spend caps may not yet be available to the CI account.
  - Both variants also cover the direct-billing possibility. Variant A puts the budget and a directly billed project
    on the same account. Variant B requires an account that bills `GOOGLE_PROJECT`.
- Refuted: `notificationsRule.schemaVersion` (accepted and dropped by the API), the service ID, output-only fields,
  API version, IAM, and duplicate budgets (those give a descriptive error).

### Code change 1: custom flatten for `input_state` (permadiff)

- Problem: the API did not return `spendCap.inputState` in any response we observed. It returns only `outputState`
  (and `reconciling` when true).
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

- Problem: once a budget is a spend cap, the API rejected every PATCH we tried whose mask lacked `spendCap.inputState` (probe U2 in
`reviews/review-root-cause.md`; U1, U3 and U4, whose masks name `spendCap.inputState` or `spendCap`, returned 200). A mask that names `spendCap` is also accepted (U4). The generated code adds `spendCap.inputState` only when `spend_cap` itself changes. So changing only
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
  `400 FAILED_PRECONDITION "Cannot transition a regular budget to a spend cap budget."` The Google page
  (docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps, text checked on 2026-10-29) says the same: "You can't edit an existing
  alerts-only budget to convert it to a spend cap enforcement budget." (quoted in `reviews/review-fix-round2.md`, F1).
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
  quoted in `report.md` section 2 and the reviews. Round 4 found wording problems. They were fixed in `f08a4efea` (section g).

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
      - Update (2026-10-29, decision 13): no acceptance log is attached. The bodies carry the PASS lines only.
      - Wording update (2026-10-29): the parent-account point is an inference; see section g.
      - Each body says it builds on PR 19315, exists only as an example for it, and that PR 19315 has priority.
      - No review requests, no reviewers, no pinging maintainers.
   4. **One comment on GoogleCloudPlatform/magic-modules#19315.** Root cause with evidence; link to the fork PR for
      the fixes; links to variants A and B; ask the reviewer to pick based on which CI account is spend-cap
      eligible. Say the fix commits are ready to be taken. Ask for a `Co-authored-by` trailer with the owner's name
      if the idea is taken without the commits. Do not resolve threads.
   5. **Subscribe** to PR 19315, the fork PR and both drafts. Report only when a decision is needed.
3. **Ask the owner before EVERY GitHub write.** This covers PR creation, comments, and every push, including pushes
   to this draft branch (owner instruction of 2026-10-29, which replaces the earlier exception for this branch).
4. **Authorship for the clean branches.** Commits are authored by Robert Żegleń <rzeglen@gmail.com>. They stay
   SIGNED (owner decision of 2026-10-29, which replaces the earlier "unsigned" decision): the owner's commits are
   signed with an SSH key through an opportunistic signing wrapper. Agent commits stay unsigned. DrFaust92's
   `ef20c8beb` and `b1edf518a` keep their own signatures. The owner signs all commits at once, after the reviews.
   NO AI trailers, no AI session trailer, and no session URLs
   in any commit or PR body made locally. Add
   a `Co-authored-by` trailer for Ilia Lazebnik, with the email on `ef20c8beb`, to every commit that touches the
   PR's files (the exact trailer is in the section f recipe). DrFaust92's commits stay untouched at the base with full attribution.
5. **PR bodies and comments.** Any agent drafting them must first load and follow the `visual-pr` and `show-me`
   skills from the humanlayer repository (github.com/humanlayer/humanlayer), or local copies if installed.
   Finding (2026-10-29, agent-reported): `show-me` exists at
   `apps/riptide-humanlayer-claude-plugin/skills/show-me/SKILL.md` in that repository. `visual-pr` was not found
   there. Fallback until the owner confirms (owner item, section g): drafts follow `show-me` plus the upstream PR
   template.
6. **Public materials describe the test org only by properties** (first-party, self-serve, non-USD, spend-cap
   eligible), never by IDs. All IDs live in the owner's local `.env` (parent directory, outside the repository).
   Of these properties, self-serve is owner-stated, and first-party (non-reseller) is inferred from
   `probe-findings.md` line 9.
7. **PR bodies must state** the justification of each change (section c) and that everything was verified end to end
   on a real organization.
8. **Secrets.** Scan every commit for tokens, keys and real identifiers before pushing (section g, "Pre-push scan").
   The fork is public.
9. **Commit granularity (2026-10-29).** Keep all five fix commits on `fix/spend-cap-input-state-mask` as they are. Do
   not squash them. Each commit can then be cherry-picked on its own later.
10. **No GitHub Support purge (2026-10-29).** The identifiers are not secrets. The history rewrite is a best-effort
    cleanup. The old-to-new map stays in the owner's local notes.
11. **Signing (2026-10-29).** The owner's commits are signed (decision 4). The owner signs all of them at once,
    after the reviews.
12. **Project creator role (2026-10-29).** The test service account keeps `roles/resourcemanager.projectCreator` on
    the test organization until the upstream drafts are decided. Then the owner revokes it (section g).
13. **No acceptance log in the PR bodies (2026-10-29, main-session decision, the owner may override).** The bodies
    carry the PASS lines only. No acceptance log is attached, because the logs contain account identifiers.

## e. Local setup

Paths below use `<parent>` for the directory that holds the magic-modules clone, `.tools/` and `.env`.

### Tools and accounts

- Go 1.26 or newer. Locally it comes from `<parent>/.tools/env.sh`: run `. <parent>/.tools/env.sh` in every shell.
- `terraform`, `gcloud`, `gh`, `git`, `jq`, `curl`.
- No bazel: `make` must run with `USE_BAZEL=0` (the default inside a worktree; pass it explicitly elsewhere).
- Google CLA: done (owner-reported). It is signed with rzeglen@gmail.com (cla.developers.google.com). That email and
  the owner's second email are both added and verified on GitHub account `pepsi133` (owner-reported, 2026-10-29).
  The link of rzeglen@gmail.com to `pepsi133` is also confirmed by the pushed commit author resolving to `pepsi133`.
- IAM: Billing Account Administrator on the test billing account. It includes `billing.budgets.configureSpendCap`,
  per the Google spend-cap docs as summarized in `report.md` section 2 (IAM row).
  For variant A also `roles/resourcemanager.projectCreator` on the test organization (granted to the test service
  account on 2026-10-29, owner-reported).

### Checkouts

Fresh machine only. On this machine the clone and the worktrees already exist (section g).

```bash
. <parent>/.tools/env.sh
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
mkdir -p <parent>/.gcloud
export CLOUDSDK_CONFIG=<parent>/.gcloud             # isolated gcloud config, separate from your personal one
gcloud auth activate-service-account --key-file=<parent>/<service-account-key>.json
```

- `CLOUDSDK_CONFIG` can be any empty directory. Create it first.
- The real `.env` lives in `<parent>`, outside the repository, so git never sees it. If a copy ever has to sit inside
  the repo, add its path to `"$(git rev-parse --git-common-dir)/info/exclude"`. In a worktree `.git` is a file, so
  `.git/info/exclude` does not exist there. Do not edit the repo `.gitignore`.
- No ADC (owner decision). Export `GOOGLE_CREDENTIALS=<parent>/<service-account-key>.json` only in the shell that runs
  acceptance tests, and unset it afterwards. It is not in `.env`.
- `GOPROXY=direct` was needed only behind the cloud session's proxy. Do not set it locally unless downloads fail.

### Generate

The downstream checkouts are scratch output. Do not rely on, or record, their current state, because it changes with
every run. Before every test run, regenerate from the worktree of the branch under test (`<parent>/mm-spendcap`,
`<parent>/mm-fix`, `<parent>/mm-variant-a` or `<parent>/mm-variant-b`). Then apply the currency edit below if that
branch's tests use USD.

`make provider` cleans the downstream checkout first, so it erases the local PLN edits. Re-apply them after each
generation. The commands below generate from this draft branch. For another branch, `cd` into its worktree instead.

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

Check the result by hand. The spend-cap example uses 5. The basic example keeps units `100000`, because the second
sed matches only the spend-cap sample. `spendCapUpdate` uses 5, 6, 7. `spendCapAdd` uses 5. All of them use PLN,
including `billingBudgetUpdate`.

### Run the tests

The API allows one spend cap per project and service. The three spend-cap tests each own one service, so they can run
in parallel:

- `billing_budget_spend_cap` sample: `C7E2-9256-1C43` (Gemini Enterprise Agent Platform)
- `TestAccBillingBudget_spendCapUpdate`: `AEFD-7695-64FA` (Gemini API)
- `TestAccBillingBudget_spendCapAdd`: `152E-C115-5142` (Cloud Run)

Calling `go test` directly avoids make's `$` escaping:

```bash
cd "$TPGB"
export GOOGLE_CREDENTIALS=<parent>/<service-account-key>.json   # only for the test run
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

Add `TF_LOG=DEBUG` to capture requests. Before sharing a log, scan it. Run
`grep -nE 'ya2[9]|private[_]key|BEGIN PRIVAT[E]|AI[z]a|Beare[r]'`. A bracket with one letter matches only that
letter, so each pattern finds the same strings as the plain word. The brackets only stop this file from matching its
own scan. The same holds for the patterns in section f.

Expected PASS set on the draft branch and the fix branch:

- `TestUnitBillingBudget_spendCapAddedCustomizeDiff` (7 subtests since `f08a4efea`), beta and GA
- `TestAccBillingBudgetsBudget_billingBudgetSpendCapExample`
- `TestAccBillingBudget_spendCapUpdate`
- `TestAccBillingBudget_spendCapAdd`
- `TestAccBillingBudgetsBudget_billingBudgetBasicExample`, `TestAccBillingBudget_billingBudgetUpdate`,
  `TestBillingBudgetStateUpgradeV0` (regression)

Expected results per branch:

| Branch | Spend-cap tests | Currency edit | Notes |
|---|---|---|---|
| draft, fix | The set above passes. | Yes | Round 5. |
| variant A | All three create their own project. | No for the spend-cap tests (yes for the USD regression tests) | Run with `-parallel 1`, or one test at a time, if the billing account's project-link quota is low (Round 8). |
| variant B | The sample test is absent. The two handwritten tests SKIP unless `GOOGLE_SPEND_CAP_BILLING_ACCOUNT` is set. | Yes, when the variable is set | `go test` prints `ok` also when the tests skip. Check for `--- PASS`, not only `ok` (Round 7). |

Not expected to pass on a plain first-party account: `billingFilterSubaccounts` needs a billing account that can
create subaccounts. `budgetFilterProjectsOrdering` needs project-create rights and a billing account that can bill
the created projects. The test service account now has the project creator role. Neither test was run locally.

### Leftover budgets

Budgets are not swept (`exclude_sweeper: true`). A leaked cap blocks that project and service for later runs
(overlap error). Check before and after every run:

```bash
gcloud billing budgets list --billing-account="$GOOGLE_BILLING_ACCOUNT" --format='table(name,displayName,spendCap)'
gcloud billing budgets delete "<budget-id>" --billing-account="$GOOGLE_BILLING_ACCOUNT"
```

An `ENFORCED` cap cannot be deleted. Lift it first (PATCH `inputState=AWAITING_NEXT_PERIOD`).

## f. Clean-branch recipe

> **Done on 2026-10-29.** The three clean branches exist. `origin` has unsigned versions, and the signed local
> versions wait for a force-push (section g).
> This section is kept as the reference recipe. Do not re-run it on this machine, because the branches and the
> worktrees already exist. Every push, including a push of the draft branch, needs the owner's approval first.

### 1. Fork PR branch (`fix/spend-cap-input-state-mask`)

```bash
cd <parent>/magic-modules
git fetch drfaust92 billingbudget-spend-cap
git rev-parse drfaust92/billingbudget-spend-cap        # must be b1edf518a...; if not, stop and ask the owner
git worktree add ../mm-fix -b fix/spend-cap-input-state-mask b1edf518a
cd ../mm-fix
git config user.name  "Robert Żegleń"
git config user.email "rzeglen@gmail.com"
for c in 2a441756e 5d93a7ccc f5b84d80a 96a871a60 f08a4efea; do
  git diff "$c^" "$c" -- mmv1 | git apply --index
  { git log -1 --format=%B "$c" | grep -vE '^(Co-Authored-By: Claude|Claude-Sessio[n]:)'
    echo "Co-authored-by: Ilia Lazebnik <$(git log -1 --format=%ae ef20c8beb)>"
  } | git commit --author="Robert Żegleń <rzeglen@gmail.com>" -F -
done
git log --format='%h %an <%ae> %s' b1edf518a..HEAD        # author must be the owner
git diff --stat b1edf518a..HEAD                          # must list only mmv1/ files
```

- `git diff -- mmv1 | git apply` takes only the `mmv1/` part of each commit. After the history rewrite the five
  code-fix commits touch only `mmv1/` (`f08a4efea` included), so `git cherry-pick` works too.
- Squashing is declined (decision 9). Keep the five commits as they are, so each one can be cherry-picked later.
  The owner signs them (decision 4). The loop above does not sign, so the owner re-signs afterwards.
- The loop keeps the full original message of each commit, drops the AI trailer, and adds the `Co-authored-by`
  trailer. This loop reproduced the first pushed versions (`80599307a` to `1f1d3f329`). The signed commits that
  replace them have shorter messages and comments (section g), so the loop no longer reproduces the branch tip. The
  tip is the reference. Do not add AI trailers, an AI session trailer or session URLs.

Before pushing:

```bash
make provider USE_BAZEL=0 VERSION=beta OUTPUT_PATH="$TPGB" PRODUCT=billingbudgets
# re-apply the local currency edit (section e), then run the unit test and the three spend-cap tests
git log -p b1edf518a..HEAD | grep -nE 'ya2[9]|private[_]key|BEGIN PRIVAT[E]|AI[z]a|client[_]secret|Claude-Sessio[n]|claude[.]ai/code' || echo clean
git log -p b1edf518a..HEAD | grep -nE '[0-9A-F]{6}[-][0-9A-F]{6}[-][0-9A-F]{6}|[0-9]{10,}|gserviceaccoun[t]|/hom[e]/' \
  | grep -v '000000-000000-000000' || echo clean
git push -u origin fix/spend-cap-input-state-mask        # ask the owner first
```

The first regex finds tokens and keys. The second finds identifiers: billing-account-shaped IDs (the all-zero
placeholder is allowed), numbers of 10 or more digits (project numbers, org IDs), service account emails and absolute home
paths. They differ on purpose, so keep both. The brackets work as in section e. The `grep -v` drops a whole line, so
a real ID on the same line as the placeholder would be hidden. Check such lines by hand.

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
on a brand-new project is tested: on 2026-10-29 the generated variant A test passed on the test organization, with
its own project on the test billing account (`fix-test-results.md`, Round 6). No currency edit was needed, because
the sample has no `currency_code`.

Second commit on variant A (`19bf3bf26e`, signed, local, owner decision of 2026-10-29): `TestAccBillingBudget_spendCapUpdate`
and `TestAccBillingBudget_spendCapAdd` also create their own `google_project` (`tf-test-%{random_suffix}`, under
`ORG_ID`, billed to `BILLING_ACCT`, `deletion_policy = "DELETE"`). The budget is on `BILLING_ACCT`. `currency_code` is
omitted, with an HCL comment. Results: `fix-test-results.md`, Round 8.

### 3. Variant B branch (`spend-cap-variant-b`, on top of the fork PR branch)

The first commit (`b2d3f2ae18`) changes only the sample entry in `Budget.yaml`: `exclude_test: true` with a comment
that ends "maps, so this sample is excluded." The second commit extends that comment to name the handwritten
tests. At the branch tip `c24fbe4d0b` the entry reads:

```yaml
  - name: billing_budget_spend_cap
    primary_resource_id: budget
    # In CI this sample got a bare 400 on the master billing account. CI uses
    # that account to create subaccounts, so it is likely a parent account.
    # Google does not document whether parent accounts can hold spend caps.
    # The exact cause is not confirmed. Generated tests can only use the
    # billing accounts the generator maps, so this sample is excluded.
    # The handwritten spend cap tests run when GOOGLE_SPEND_CAP_BILLING_ACCOUNT
    # is set.
    exclude_test: true
    steps:
      ...unchanged...
```

Second commit on variant B (`c24fbe4d0b`, signed, local, owner decision of 2026-10-29):

- New variable `GOOGLE_SPEND_CAP_BILLING_ACCOUNT` with the getter `GetTestSpendCapBillingAccountFromEnv` in
  `mmv1/third_party/terraform/envvar/envvar_utils.go`.
- `TestAccBillingBudget_spendCapUpdate` and `TestAccBillingBudget_spendCapAdd` use it and skip when it is unset.
  The comments say the account must be first-party, that whether parent accounts or subaccounts can hold spend caps
  is not documented, and that the account must bill `GOOGLE_PROJECT` and use USD.
- The `Budget.yaml` sample comment is softened (snippet above).
- CI files are not changed. To run the two tests in CI, maintainers need a secret for the variable plus its
  registration in the magician variable lists and in TeamCity. The PR draft lists the files.
- To run the two tests locally, set `GOOGLE_SPEND_CAP_BILLING_ACCOUNT`. The tests use USD, so use a USD account, or
  set it to the test billing account and apply the local currency edit (section e). Results:
  `fix-test-results.md`, Round 7.

### PR bodies

Template: `.github/PULL_REQUEST_TEMPLATE.md`.

- The upstream example drafts (variants A and B) say `Related to hashicorp/terraform-provider-google#28575`, not
  `Fixes`. An example PR that must not be merged must not close the issue.
- They keep the real release-note block of PR 19315 (copied from its body, note the singular `billingbudget:`),
  with the line `Same release note as #19315.` above it:

  ````text
  Same release note as #19315.

  ```release-note:enhancement
  billingbudget: added `spend_cap` field to `google_billing_budget` resource
  ```
  ````

- Drafts, local files outside the repository, none posted: `<parent>/pr-drafts/fork-pr.md` (PR to DrFaust92's
  branch), `<parent>/pr-drafts/variant-a.md` and `<parent>/pr-drafts/variant-b.md` (upstream draft PRs), and
  `<parent>/pr-drafts/comment-19315.md` (the one comment). Section i says how to check and post them.

No session URLs or AI session lines in the bodies. Each body states the justification of each change
(section c) and that it was verified end to end on a real organization (properties only, no IDs). The upstream drafts say they build on PR 19315, exist only as examples for
it, and that PR 19315 has priority.

## g. Not done / open

### Local status (2026-10-29)

Done:

- The round-4 wording fixes below are applied in `f08a4efea`, items 1 to 6. Item 1 drops the unverified sentence
  "other fields cannot be changed without re-sending `CONFIGURED`" and says instead that an update made while the
  cap is lifted re-sends the current value. Item 5 follows the Google page: only display name, amount, project and
  service can change, and none of them while the cap is enforced.
- Tests after the fix: beta and GA, the unit test, the three spend-cap tests and the regression set all pass
  (`fix-test-results.md`, Round 5).
- Clean branches, authored by the owner, signed locally (decision 4), `Co-authored-by` Ilia on each commit, only
  `mmv1/`:
  - `fix/spend-cap-input-state-mask` on `b1edf518a`: the five code-fix commits. Its `mmv1/` tree differs from this
    draft branch's (`f08a4efea`) only in comments and `Budget.yaml` description strings; no code line differs
    (checked 2026-10-29), so the Round 5 results apply to it.
  - `spend-cap-variant-b` on the fix branch: `exclude_test: true` with the comment. Generated and vetted. A second
    commit `c24fbe4d0b` makes the handwritten spend-cap tests opt-in (`fix-test-results.md`, Round 7).
  - `spend-cap-variant-a` on the fix branch: own `google_project` on `BILLING_ACCT`, no `currency_code`. Generated,
    vetted and run: the sample test passed on the test organization on 2026-10-29 (`fix-test-results.md`, Round 6).
    The test service account was granted `roles/resourcemanager.projectCreator` on the test organization for this.
    A second commit `19bf3bf26e` moves the handwritten spend-cap tests to their own project
    (`fix-test-results.md`, Round 8).
- Branch heads, as of the commit that adds this table (2026-10-29). The pushes of 2026-10-29 (owner-approved, to
  `origin` = `pepsi133/magic-modules`) hold unsigned commits. Nothing was pushed after 2026-10-29 00:18; the `origin`
  column was re-read with `git ls-remote origin` on 2026-10-29 at 08:55. Compare with `git rev-parse origin/<branch>`.

  | Branch | `origin` (unsigned) | Local | Pending push |
  |---|---|---|---|
  | `claude/great-galileo-1gggv5` | `fec7403b0` | the commit that adds this table | normal push, 1 commit |
  | `fix/spend-cap-input-state-mask` | `1f1d3f329` | `1aec53029c` (signed) | force-push with lease |
  | `spend-cap-variant-a` | `3213aa619` | `19bf3bf26e` (signed) | force-push with lease |
  | `spend-cap-variant-b` | `b56bc934a` | `c24fbe4d0b` (signed) | force-push with lease |

  After the pending pushes, `origin` will hold the signed SHAs. Before signing, all 9 commits were rewritten with
  shorter code comments and commit messages. Checked line by line on 2026-10-29 (`git diff` of the tested commit
  against the signed one, Rounds 5 to 8): on the fix branch and on variant B the rewrite changed only comments
  (Go, template and YAML), commit messages and description strings in `Budget.yaml`; no code line differs. On
  variant A the same holds, plus two added HCL `#` comment lines inside the handwritten test configs (the
  `currency_code` note), so no code line differs there either. The owner then signed each rewritten commit; signing kept the tree, subject, author and
  full message of its unsigned predecessor. The `origin` commits (`80599307a`, `36f9cb2f9`, `916ae0476`,
  `24e61966a`, `1f1d3f329`; `3213aa619`; `b56bc934a`) differ from the signed ones in the same way, in comments,
  commit messages and `Budget.yaml` description strings, and the force-push replaces them.

  | Unsigned rewrite | Signed | Commit |
  |---|---|---|
  | `dcee26242` | `19d4c8f50d` | fix 1: input_state permadiff and update mask |
  | `c04845790` | `9753329267` | fix 2: spend_cap removal, cap overlap in tests, lifted caps |
  | `2a5de3775` | `98d683bd8c` | fix 3: force replacement when adding spend_cap, simpler flatten |
  | `310c68f29` | `1e0c5ace48` | fix 4: unit-test the custom diff, tighten descriptions |
  | `570e0630c` | `1aec53029c` | fix 5: description wording from review round 4 (fix branch tip) |
  | `e17407992` | `91a7f33fe3` | variant A, first commit: the sample on its own project |
  | `9065bc866` | `19bf3bf26e` | variant A, second commit: handwritten tests on their own project (tip) |
  | `fd53bd7ea` | `b2d3f2ae18` | variant B, first commit: exclude the sample from generated tests |
  | `a6f1b7c26` | `c24fbe4d0b` | variant B, second commit: opt-in eligible billing account (tip) |

- Pending pushes, all at once after the owner approves. Run the pre-push scan first. In `<parent>/magic-modules`:

  ```bash
  git push origin claude/great-galileo-1gggv5
  git push --force-with-lease=fix/spend-cap-input-state-mask:1f1d3f329 origin fix/spend-cap-input-state-mask
  git push --force-with-lease=spend-cap-variant-a:3213aa619 origin spend-cap-variant-a
  git push --force-with-lease=spend-cap-variant-b:b56bc934a origin spend-cap-variant-b
  ```

  The lease values are the `origin` tips read on 2026-10-29. The next session must re-read `git ls-remote origin`
  and use the fresh values.

- Push order: the draft branch must be pushed before any PR draft is posted, because the drafts link Rounds 6 to 8,
  which are not on `origin` yet.
- Pre-push scan, per pending branch, over the added lines and the commit messages of `origin/<b>..<b>`. Run it in
  `<parent>/magic-modules`:

  ```bash
  T='ya2[9]|private[_]key|BEGIN PRIVAT[E]|AI[z]a|client[_]secret|Claude-Sessio[n]|claude[.]ai/code'
  I='[0-9A-F]{6}[-][0-9A-F]{6}[-][0-9A-F]{6}|[0-9]{10,}|gserviceaccoun[t]|/hom[e]/'
  for b in claude/great-galileo-1gggv5 fix/spend-cap-input-state-mask spend-cap-variant-a spend-cap-variant-b; do
    echo "== $b"
    { git log -p --format= "origin/$b..$b" | grep '^+'; git log --format=%B "origin/$b..$b"; } \
      | grep -nE "$T|$I" | grep -v '000000-000000-000000' || echo clean
  done
  ```

  The regexes are those of section f, with the commit messages added. The prose in this file names the session
  trailer only in words. On the fix and variant branches the scan prints clean. On the draft branch, as of this
  commit, it shows three kinds of expected hits: GitHub comment IDs in `issuecomment-` URLs, paths of the cloud
  sandbox home directory in the review lines whose SHAs were replaced, and the signed SHA of fix 2 (`9753329267`),
  which is all digits and so matches the 10-digit identifier pattern. Check that every hit is one of these.

- Not done: no PR, no comment and no subscription exists yet. Each one still needs the owner's approval.
- Worktrees: `<parent>/mm-spendcap` (this branch), `<parent>/mm-fix`, `<parent>/mm-variant-a`,
  `<parent>/mm-variant-b`.

### Round-4 wording fixes (applied in `f08a4efea`)

Source: `reviews/review-fix-round4.md`.

| # | Where | Finding | Proposed fix |
|---|---|---|---|
| 1 | `Budget.yaml` `input_state`, lines ~586-590 vs ~594-595 | The two passages contradict each other about when to set `CONFIGURED` back after a lift. | Restore "After the next period starts, set it back to `CONFIGURED`", and state the trade-off for edits made while the cap is lifted. |
| 2 | `Budget.yaml` `input_state`, lines ~594-595 | "Re-applying `CONFIGURED` after a cap was lifted outside Terraform may re-activate the cap" is ambiguous: a plain re-apply sends nothing. | Replace with "Any later Terraform update of the budget re-sends `input_state = CONFIGURED`, which may re-activate a cap lifted outside Terraform." |
| 3 | `Budget.yaml` `spend_cap`, delete sentence (~570-571) | Does not say the lift must be applied before `terraform destroy`. | Add "apply `input_state = AWAITING_NEXT_PERIOD` before destroying". |
| 4 | `Budget.yaml` `spend_cap` (~574-575) | Two sentences say that adding a block replaces the budget. | Merge into one: "Adding a `spend_cap` block to an existing budget replaces the budget." |
| 5 | `Budget.yaml` `spend_cap` (~569) | "only `input_state` can be changed while enforced" conflicts with the Google page (name, amount, project and service are editable). | Reword so it does not contradict the page. |
| 6 | `resource_billing_budget_internal_test.go` | No case for a missing or nil `Before` value. | Optional: add case `before: nil, after: configured, forceNew: true`. |

### Other open items

- **Pre-rewrite commits on GitHub: closed (decision 10).** No purge request. The old-to-new map stays in
  `<parent>/notes/history-rewrite.md`.
- **Pending pushes (owner approval needed).** The draft branch (normal push) and the three signed clean branches
  (force-push with lease, commands above). Run the pre-push scan first (see above). Push the draft branch before any PR draft is
  posted.
- **All GitHub writes that remain** (each needs the owner's approval first):
  - Open the fork PR against `DrFaust92/magic-modules`, base `billingbudget-spend-cap` (follow decision 5).
  - Open the two upstream drafts. The bodies carry the PASS lines only, with no acceptance log (decision 13).
  - Fill the cross-links into the bodies that were posted first (`gh pr edit`, section i).
  - Post the comment on 19315. Subscriptions need no write (section i, step e).
- **PR drafting skills (owner item to confirm).** `visual-pr` was not found (decision 5). Until the owner confirms,
  drafts follow `show-me` plus the upstream PR template.
- **Is `BILLING_ACCT` in CI spend-cap eligible?** Unknown. Only maintainers can check. Variant A depends on it.
  - Inference, not verified: `TestAccBillingBudget_budgetFilterProjectsOrdering` puts a budget on
    `MASTER_BILLING_ACCT` with a filter on projects that `BILLING_ACCT` bills, and it passes. A budget filter accepts
    only projects that the budget's account bills (section c, input 2). So `BILLING_ACCT` is probably a subaccount of
    the master account. Whether a subaccount can hold spend caps is not documented: Google documents only the
    first-party requirement and the reseller exclusion, and neither says anything about subaccounts. So the
    eligibility of `BILLING_ACCT` is unverified. This is a risk for variant A that only maintainers can check.
  - Other account-level causes are not ruled out either (section c): spend caps may need direct billing, which
    both variants provide, or may not yet be available to the CI account.
- **Variant wording: fixed in the signed commits.** The pushed unsigned commits `b56bc934a` and `3213aa619` state as
  fact that the CI master billing account is a parent account. The signed commits `b2d3f2ae18`, `c24fbe4d0b`,
  `91a7f33fe3` and `19bf3bf26e` say "likely", "not confirmed" and "not documented" in their messages and comments. The force-push
  replaces `origin`'s `b56bc934a` and `3213aa619`.
- **Handwritten spend-cap tests in CI: closed (owner decision, 2026-10-29).** `TestAccBillingBudget_spendCapUpdate`
  and `TestAccBillingBudget_spendCapAdd` used `GetTestMasterBillingAccountFromEnv` and `data "google_project"`, so
  they would likely hit the same 400 in CI. The owner decided: variant A moves them to their own project on
  `BILLING_ACCT` (`19bf3bf26e`, Round 8). Variant B makes them opt-in through `GOOGLE_SPEND_CAP_BILLING_ACCOUNT`
  (`c24fbe4d0b`, Round 7). Both commits are local and need the owner's approval to push. The evidence below led to
  this decision.
  - Upstream CI evidence, read at `upstream/main` `d8e3fb7c1` (the cited files are unchanged at `da2594fac`):
    - The CI service account setup `.ci/infra/terraform/main.tf` grants these roles at organization level
      (`google_organization_iam_member`): `roles/billing.user` (:48-52), `roles/billing.viewer` (:54-58),
      `roles/billing.projectManager` (:138-142), `roles/resourcemanager.projectCreator` (:144-148) and
      `roles/resourcemanager.projectDeleter` (:150-154). Only `roles/billing.admin` (:192-196) and
      `roles/logging.configWriter` (:198-202) are on the master billing account
      (`google_billing_account_iam_member`). The README says there is no automation and an administrator runs the
      configuration locally, so the live state may differ.
    - The same file bills the CI project to `var.billing_account_id`, not to the master account (:17-22).
      `variables.tf:13-14` describes the master account as the one used for "the creation of subaccounts". This
      fits the inference above that `BILLING_ACCT` is probably a subaccount of the master account and not the master
      account itself.
    - Creating a `google_project` under `ORG_ID` billed to `BILLING_ACCT` is an established CI pattern: about 80
      handwritten test files and more than 100 sample templates do it. Counted with `git grep -l` at
      `upstream/main`: 79 `_test.go` files under `mmv1/third_party/terraform` contain `resource "google_project"`,
      `GetTestOrgFromEnv` and `GetTestBillingAccountFromEnv`. 114 files under `mmv1/templates/terraform/samples`
      contain `resource "google_project"` with `billing_account` set from `TestEnvVars "billing_acct"` or
      `TestEnvVars "billing_account"`. These are file-level counts. `envvar_utils.go:242-243` says `BILLING_ACCT` "is also
      the billing account used for creating new projects". No upstream test bills a project to
      `MASTER_BILLING_ACCT`.
    - In billingbudgets, `TestAccBillingBudget_budgetFilterProjectsOrdering` (`resource_billing_budget_test.go:544`)
      already creates two projects under `ORG_ID` billed to `BILLING_ACCT`, with the budget on
      `MASTER_BILLING_ACCT`. It passed in VCR recording on 2026-09-17
      (https://github.com/GoogleCloudPlatform/magic-modules/pull/19076#issuecomment-5718931726).
  - Options that were considered: (a) move the two tests to their own project on `BILLING_ACCT` (taken in variant A),
    and (b) leave them and say in the PR bodies that they need a first-party billing account (replaced in variant B
    by the opt-in variable).
- **Cleanup: revoke the project creator role** once the upstream drafts are decided (decision 12). The owner runs:

  ```bash
  gcloud organizations remove-iam-policy-binding "$GOOGLE_ORG" \
    --member="serviceAccount:<test-service-account-email>" --role=roles/resourcemanager.projectCreator
  ```

- **Optional owner action: free project-link quota.** The test billing account has a low project-link quota, which
  made parallel project creations fail in Round 8. Besides the test project it bills two placeholder projects. The
  owner may unlink them to free quota.
- **Cleanup: the variant A test projects** (Rounds 6 and 8) are in `DELETE_REQUESTED`. Google Cloud purges them after 30
  days (owner-reported for Round 6, agent-reported for Round 8). No action is needed, but they count toward the
  project quota until then.
- **Re-arm after a lift is untestable** without real spend that enforces a cap. Whether re-sending `CONFIGURED`
  re-activates a lifted cap is unverified (round 2 F2, round 3 F2, round 4 F2).
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
- `fix-test-results.md`: verification of each code fix, rounds 1 to 5, the variant A sample run in round 6, the
  variant B opt-in tests in round 7 and the variant A handwritten tests in round 8.
- `.env.example`: variable names for the local `.env`.
- `reviews/review-root-cause.md`: adversarial review of the root cause, with 40 API probes.
- `reviews/review-fix.md`: review round 1 of code fix 1, now `2a441756e` (removal bug, test overlap).
- `reviews/review-fix-round2.md`: review round 2 of code fix 2, now `5d93a7ccc` (add-cap refusal, flatten order).
- `reviews/review-fix-round3.md`: review round 3 of code fix 3, now `f5b84d80a` (CustomizeDiff, GA run, docs).
- `reviews/review-fix-round4.md`: review round 4 of code fix 4, now `96a871a60` (unit test mutations, open wording
  fixes).
- `reviews/pr-conventions.md`: upstream PR conventions (template, release notes, CLA, stacking, drafts).

## i. Turnover to the next session

The next session starts by reading this file. Before any GitHub write it checks three things, in this order.

1. **The four pushes are done.** In `<parent>/magic-modules`, run `git fetch origin`. Then `origin/<b>` must equal the
   local signed head for each branch in the section g table (draft branch, fix, variant A, variant B). If not, stop
   and ask the owner.
2. **The four drafts in `<parent>/pr-drafts/` are correct** against the pushed branches: `fork-pr.md`,
   `variant-a.md`, `variant-b.md` and `comment-19315.md`.
   - Every SHA, link, test result and CI citation checks out.
   - The TODO links are the only gaps.
   - No identifiers and no @-mentions.
   - The framing follows section d.
   - Fix any problem in the drafts, and report it.
3. **Ask the owner to approve each GitHub write, one at a time,** in the order below. Before each one, show the final
   text and the exact `gh` command. After each approval, run only that one command, confirm the result URL, fill
   that URL into the later drafts, and ask for the next.
   - (a) The fork PR to `DrFaust92/magic-modules`, base `billingbudget-spend-cap`, from
     `pepsi133:fix/spend-cap-input-state-mask` (`fork-pr.md`).
   - (b) The variant A draft PR to `GoogleCloudPlatform/magic-modules`, base `main`, with `gh pr create --draft`,
     after filling its TODO(fork-PR-link) (`variant-a.md`).
   - (c) The variant B draft PR, likewise, with both links filled (`variant-b.md`).
   - (a') `gh pr edit <fork PR> --body-file <file>`, to fill TODO(variant-A-link) and TODO(variant-B-link) in the
     fork PR body, now that (b) and (c) exist.
   - (b') `gh pr edit <variant A PR> --body-file <file>`, to fill TODO(variant-B-link) in the variant A body, now
     that (c) exists.
   - (d) The comment on #19315, with all three links filled (`comment-19315.md`).
   - (e) Subscriptions (decision 2.5), a check and no write. Authoring a PR or a comment subscribes the author, so the
     owner is subscribed to the fork PR and both drafts by authorship, and to #19315 by the comment in (d). To check
     one, run `gh api graphql -f query='{repository(owner:"<owner>",name:"magic-modules"){pullRequest(number:<n>){viewerSubscription}}}'`.
     It must print `SUBSCRIBED`.

The GitHub writes are exactly (a), (b), (c), (a'), (b') and (d), each after its own approval. There is no other
GitHub write. Report only when a decision is needed.
