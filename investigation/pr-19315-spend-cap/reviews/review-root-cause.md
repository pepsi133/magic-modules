# Adversarial review: investigation/pr-19315-spend-cap (branch claude/great-galileo-1gggv5)

Reviewer: independent, read-only on the repo; fresh API probes against the test billing account (PLN,
first-party, no subaccounts) from project `${GOOGLE_PROJECT}` (${GOOGLE_PROJECT_NUMBER}). Date 2026-10-28.
Raw probe output: `/tmp/claude-0/-home-user-magic-modules/226a38d8-2f36-5156-86eb-097c301a2149/scratchpad/review-probe.out`
and `.../review-probe2.out`; scripts `review-probe.sh`, `review-probe2.sh` in the same directory; acceptance logs
`pln-run.log` (unpatched) and `pln-run-fixed.log` (flatten patched), patch `input_state_flatten.patch`.

## Verdicts

| Claim | Verdict | One-line reason |
|---|---|---|
| C1 request shape valid; upstream 400 environmental | **holds** | Provider-shaped body creates fine in PLN; every spend-cap *field* violation I could provoke returns a *descriptive* 400, never the bare one. |
| C2 bare 400 = (a) currency mismatch, (b) project not billed by the account, for regular budgets too | **holds, and strengthened** | Reproduced both; closed the artifact's open caveat: a project billed elsewhere given by **number** is rejected with the bare 400 (not silently dropped). |
| C3 existing USD project samples pass upstream so (a)/(b) are excluded; parent-account hypothesis strongest | **holds (premise now evidenced, conclusion still unproven)** | PR CI: 12 tests, 11 passed in replay incl. `billingFilterSubaccounts` (creates a `google_billing_subaccount` under MASTER) and `budgetFilterProjectsOrdering` (projects billed by `BILLING_ACCT`, budget on MASTER). MASTER is demonstrably a parent account. But the artifact did not find these two tests and its "neither (a) nor (b)" needs a refinement: MASTER accepts projects billed by a *subaccount* for regular budgets, so the spend-cap failure may be "project billed via subaccount, not directly" rather than "parent accounts unsupported". Same fix either way. |
| C4 permadiff: API never returns `spendCap.inputState` | **holds** | Reproduced (run 1, FAIL on non-refresh plan). Generated flatten is `return v` (line 1385-1387). |
| C5 update bug: every PATCH on a spend cap needs `spendCap.inputState` in the mask; generated code adds it only on `HasChange("spend_cap")` | **holds** | Code lines 872-874; API probe U2 (mask `amount.*` only) → bare 400, U1 (same + `spendCap.inputState`) → 200. |
| C6 fix: own `google_project` on `BILLING_ACCT`, omit `currency_code`, custom flatten/ignore_read, pre_update mask | **holds with findings** | With *only* the flatten patched, the PLN test passes all 3 steps (create, import verify, identity import). `currency_code` omission accepted by API and schema (`default_from_api`). Precedent for project-on-BILLING_ACCT exists in a handwritten test the artifact missed. Billing-link propagation for a *spend cap* on a brand-new project remains untested. |

## Attempts

### A1. Re-derive C2(a)/(b) and probe other inputs (`review-probe.sh`, `review-probe2.sh`)

All bodies: `services/C7E2-9256-1C43`, `EXCLUDE_ALL_CREDITS`, MONTH, PLN 5, thresholds 0.5/0.8/1.0 CURRENT_SPEND,
`notificationsRule.enableProjectLevelRecipients=true`, `spendCap.inputState=CONFIGURED`, unless stated. Each 200 was
deleted and re-GET returned 404.

| Probe | Variation | HTTP | Message |
|---|---|---|---|
| R1 | regular budget, USD, billed project by number | 400 | bare `Request contains an invalid argument.` |
| R2 | spend cap, USD | 400 | bare |
| R3 | regular budget, USD, **no project filter** (shape of `billing_budget_basic`) | 400 | bare |
| F6 | regular budget, EUR, no filter | 400 | bare |
| A2 | spend cap, `currencyCode: "pln"` (lowercase) | 400 | bare |
| A3 | spend cap, **no currencyCode** | 200 | stored as PLN |
| A4 | spend cap, PLN units 100 | 200 | |
| **N1** | spend cap, foreign project **by number** `projects/570399209098` (Google's landsat project, exists, billed elsewhere) | 400 | bare |
| **N2** | regular budget, same foreign number | 400 | bare |
| N3 | spend cap, foreign number `projects/17877902519` (cloud-samples-data) | 400 | bare |
| N4 | spend cap, unbilled org project by ID `<other-project-4>` | 400 | bare |
| F5 | regular budget, USD, billed project by ID | 400 | bare (currency) |
| T1 | one threshold 0.5 | 400 | `Spend Caps must have exactly three thresholds: 50%, 80%, and 100%` |
| T2 | no thresholdRules | 400 | same descriptive message |
| T3 | three thresholds with **no spendBasis** | 200 | API fills `CURRENT_SPEND` |
| F3 | 0.5 FORECASTED_SPEND + 0.8 + 1.0 | 400 | thresholds message |
| E1 | notificationsRule **absent** | 400 | `Spend Caps must have project level notifications enabled` |
| E2 | notificationsRule `{}` | 400 | same |
| E3 | notificationsRule `{schemaVersion:"1.0"}` only | 400 | same (so `schemaVersion` is not the trigger; H1 of report.md stays refuted) |
| E4 | + `disableDefaultIamRecipients:false` explicit | 200 | |
| P1 | **calendarPeriod absent** (what the provider actually sends, since MONTH is diff-suppressed) | 200 | API fills MONTH |
| F4 | calendarPeriod QUARTER | 400 | `Spend Cap budget must have a monthly time period` |
| P2 | INCLUDE_ALL_CREDITS | 400 | `Spend Cap cannot select credits` |
| P3 | two projects (both billed) | 400 | `Spend Cap must be limited to a single project` |
| S1 | service 6F81-5844-456A (Compute) | 400 | `Service ... is not supported for spend caps ... sublist: [152E-C115-5142, 29E7-DA93-CA13, AEFD-7695-64FA, C7E2-9256-1C43]` |
| S2 | no services | 400 | `Spend Cap must be limited to a single service` |
| S3 | bogus service | 400 | descriptive as S1 |
| O1 | ownershipScope BILLING_ACCOUNT | 400 | `Spend Caps cannot have ownership scope specified` |
| A1 | lastPeriodAmount | 400 | `Spend Cap must not use last periods spend` |
| F1 | labels set | 400 | `Spend Caps cannot have label filters` |
| F2 | subaccounts set | 400 | `Spend Caps cannot have subaccount filters` |
| I1 | inputState AWAITING_NEXT_PERIOD on create | 400 | bare |
| I2 | inputState ENFORCED on create | 400 | bare |
| I3 | `spendCap: {}` on create | 400 | bare |
| I4 | inputState + outputState + reconciling in create body | 200 | output-only fields tolerated |
| D1 | second spend cap with identical scope | 400 | `Overlap detected with existing cost view ... FAILED_PRECONDITION` (descriptive; rules out H6 as the bare-400 cause) |
| D2 | regular budget with the same scope as an existing spend cap | 400 | same overlap message (regular budgets are blocked too) |
| U1 | PATCH mask `amount.specifiedAmount.{currencyCode,units,nanos},spendCap.inputState`, body incl. `outputState`,`reconciling` (provider-shaped) | 200 | output-only fields in PATCH body are harmless |
| U2 | PATCH mask `amount.specifiedAmount.*` only | 400 | bare (C5) |
| U3 | PATCH mask `spendCap.inputState`, CONFIGURED no-op | 200 | |
| U4 | PATCH mask `spendCap`, body `{}` | 200 | converts to a regular budget (`spendCap` gone on GET) |

Conclusion for A1: of everything the provider could plausibly send, the **only** inputs that yield the detail-less 400 are
(a) a currency that is not the account's, (b) a project (ID or number) that the account does not bill, (c) a spend-cap
`inputState` other than CONFIGURED on create, (d) an update mask without `spendCap.inputState`. Every spend-cap-specific
rule is enforced with a descriptive message. The PR sample sends CONFIGURED, so for the upstream *create* only (a), (b)
or an account-level condition I cannot provoke (eligibility) remain.

### A2. C3's premise and the parent-account hypothesis

- Repo: all 8 samples in `mmv1/products/billingbudgets/Budget.yaml` use `billing_acct: MASTER_BILLING_ACCT`; none has
  `exclude_test`/`skip_test` (grep lines 41-139 show only `exclude_sweeper: true` at line 41). Six samples filter on
  `data.google_project.project.number`; seven hard-code USD. No `t.Skip` in `resource_billing_budget_test.go`.
- Upstream PR CI (WebFetch of github.com/GoogleCloudPlatform/magic-modules/pull/19315; the GitHub API and `gh` are scoped to the
  fork only in this session): modular-magician on Oct 13 and Oct 26 2026: "Total Tests 12, Passed 11, Skipped 0, Affected 1",
  replay found 1 affected test, recording of `TestAccBillingBudgetsBudget_billingBudgetSpendCapExample` "❌ Error". 12 =
  8 generated + 4 handwritten tests. The VCR matcher (`mmv1/third_party/terraform/acctest/vcr_utils.go:292-340`) requires
  method + URL + JSON-DeepEqual body, so a replay pass means a cassette recorded a 200 for a body containing
  `"currencyCode":"USD"` and `projects/<GOOGLE_PROJECT number>` on MASTER. Caveat: a replay pass proves a past nightly recording
  passed, not that it passes today.
- The two tests the artifact did not weigh:
  - `TestAccBillingBudget_billingFilterSubaccounts` (`resource_billing_budget_test.go:131-213`) creates
    `google_billing_subaccount` with `master_billing_account = MASTER`. Its replay pass is direct evidence that MASTER is a
    parent (reseller-type) account, replacing the artifact's inference from the envvar comment.
  - `TestAccBillingBudget_budgetFilterProjectsOrdering` (`:544-640`) creates two `google_project`s with
    `billing_account = GOOGLE_BILLING_ACCOUNT` and budgets them on MASTER with `last_period_amount`, no sleep. Given N2 (a
    project billed by a foreign account is rejected for regular budgets), its pass means MASTER == BILLING_ACCT or
    BILLING_ACCT is a subaccount of MASTER (the discovery text for `subaccounts` says a parent budget "includes usage from
    the parent account and all subaccounts"). So "GOOGLE_PROJECT is billed by MASTER" in the regular-budget sense is
    established, but possibly only transitively.
- Docs (WebFetch of docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps and /budget-api-spend-cap): only
  "Spend cap budgets are limited to first-party Google Cloud customers and Cloud Billing accounts. Reseller accounts are
  out of scope." Nothing on parent/master/subaccount/invoiced/country eligibility, and no error codes other than
  FAILED_PRECONDITION for edits while enforced. Discovery `spendCap` text (rev 20261018) adds nothing on eligibility.
  So 400-vs-403-vs-FAILED_PRECONDITION for an ineligible account is **undocumented**; cannot be settled from here.

### A3. C4/C5 in generated code (`/home/user/tpgb/google-beta/services/billingbudgets/resource_billing_budget.go`)

- Lines 1385-1387: `func flattenBillingBudgetsBudgetSpendCapInputState(...) { return v }` → nil when the API omits it.
- Lines 872-874: `if d.HasChange("spend_cap") { updateMask = append(updateMask, "spendCap.inputState") }`; no other branch adds it.
- Lines 1859-1874: expander emits `inputState`, `outputState`, `reconciling` when non-empty (U1 shows that is harmless).
- Run 1 (unpatched, PLN edit only): `--- FAIL ... (13.57s)`, step 1/3 "non-refresh plan was not empty", plan shows
  `+ input_state = "CONFIGURED"` plus `+ credit_types = []`, `+ resource_ancestors = []`, `+ subaccounts = []`.
- Run 2 (tpgb flatten patched as in `input_state_flatten.patch`: return `v` if non-nil, else `d.Get("spend_cap.0.input_state")`,
  else `"CONFIGURED"`): `--- PASS: TestAccBillingBudgetsBudget_billingBudgetSpendCapExample (20.43s)`. The three
  `budget_filter` empty-list lines disappear, confirming the artifact's unverified "display noise" guess. Patch reverted.

### A4. C6 details

- Billing-link propagation: `budgetFilterProjectsOrdering` creates projects on BILLING_ACCT and budgets them immediately on
  MASTER without `time_sleep`, and passes. That is the closest precedent; a *spend cap* on a just-created project was not
  tested (cannot create projects with this credential; `cloudresourcemanager v3 projects:search` on the org returns `{}`).
- Precedent for BILLING_ACCT: no sample or test puts the *budget* on BILLING_ACCT; `GetTestBillingAccountFromEnv` appears
  only as the project's billing account (`resource_billing_budget_test.go:550`). `envvar_utils.go:119-129`:
  BILLING_ACCT "will be charged for the infrastructure used during testing ... also the billing account used for creating
  new projects"; MASTER "will be modified to test billing-related functionality ... expected to have more permissions ...
  and support subaccounts".
- `currency_code`: `Budget.yaml:425-429` `currencyCode` is `default_from_api: true` (Optional+Computed); description says
  "currencyCode is optional. If specified, it must match". Probe A3 confirms the API accepts omission. The handwritten
  `TestAccBillingBudget_billingBudgetCurrencycode` already omits it.
- `ignore_read`: `AGENTS.md:21-23` forbids `ignore_read`/`ImportStateVerifyIgnore` "without an adjacent comment justifying
  the API behavior". A justified comment ("API never returns spendCap.inputState") satisfies it, but the custom flatten is
  better: it keeps step 2 (ImportStateVerify) meaningful, and run 2 shows the flatten alone makes import verify pass.

### A5. Things the artifact may have missed

- VCR determinism: `data.google_project` number is stable per CI project; with the proposed own-`google_project` sample the
  number comes from the recorded project-create response, so replay is self-consistent (same pattern as
  `budgetFilterProjectsOrdering`). No issue found.
- `calendarPeriod` absent in POST (provider diff-suppresses MONTH): accepted (P1). No issue.
- `reconciling`: absent on GET when false; flatten returns nil → state false; never observed true in ~15 creates. Low risk.
- `output_state` on PATCH: harmless (U1).
- `enable_project_level_recipients` vs `at_least_one_of` on `all_updates_rule`: forces `monitoring_notification_channels = []`
  in config; API returns no such field; no diff observed in either run. No issue.
- `inputState` validation: `AWAITING_NEXT_PERIOD` in config on a non-enforced cap → bare 400 (I1), not covered by any test.
- Overlap: a leaked spend cap (sweeper excluded) blocks **regular** budgets on the same project+service too (D2) with a
  descriptive FAILED_PRECONDITION. Not the upstream cause, but a hazard for the shared CI project if the sample ever leaks;
  one more reason to budget a throwaway project.
- Nothing found that would make the upstream test fail after C6 beyond the untested account-eligibility question.

## Findings (file, line, proposed fix)

1. `acctest-findings.md:333` — "A billed-elsewhere project given *by number* was not tested ... possible that a number for
   a project billed elsewhere is also dropped". Now tested: rejected with the bare 400 (N1, N2, N3). Replace the caveat with
   this result and drop the alternative "regular budget would pass (filtering nothing)".
2. `acctest-findings.md:498` and `:521` — "No existing sample ... creates a google_project and then budgets on it" and the
   "open policy question" about BILLING_ACCT. `resource_billing_budget_test.go:544-640` already creates projects on
   BILLING_ACCT and budgets them on MASTER, in the same test package. Cite it; the policy question reduces to "the budget
   itself must move to BILLING_ACCT because MASTER is a parent".
3. `acctest-findings.md:510`, `probe-findings.md:70`, `report.md` H3 — the parent-account premise rests on the envvar
   comment. Cite `TestAccBillingBudget_billingFilterSubaccounts` (creates a subaccount under MASTER; passed in replay per
   the PR's CI comments, 11/12) as the evidence.
4. `acctest-findings.md:21` — "assumed passing in CI; not verified here". Verifiable from the PR page: 11 of 12 tests
   passed in replay on both CI runs (Oct 13, Oct 26). Add that, with the caveat that a replay pass reflects a past recording.
5. `acctest-findings.md:281` — "most likely display noise ... not verified". Verified: with only the flatten patched the
   plan is empty and all three steps pass. State it.
6. `acctest-findings.md:~505-512` — "neither H4 nor H2 explains" should be refined: `budgetFilterProjectsOrdering` passing
   means MASTER accepts projects billed by BILLING_ACCT (likely as a subaccount). So an extra candidate is "spend caps
   require the project to be billed *directly* by the budget's account, not via a subaccount", distinct from "parent
   accounts are ineligible". Both are unprovable here and lead to the same fix.
7. `report.md:12`, `:261`, `:294` and `README.md:12` — still present H1 (`schemaVersion`) as the top hypothesis although
   `probe-findings.md` refutes it (and E3 shows `schemaVersion` alone does not even change the message). Add a banner at the
   top of `report.md` and `README.md` pointing to the refutation, or rewrite the TL;DR.
8. `acctest-findings.md:564` — `time_sleep` suggestion is speculative; note the precedent test needs none, but that a
   spend cap on a fresh project is untested.
9. `acctest-findings.md:579-580` — `ignore_read` option: add that `AGENTS.md:21-23` requires an adjacent justification
   comment, and that the flatten approach was verified to pass ImportStateVerify.
10. Resource (PR code, not the artifact) — `mmv1/products/billingbudgets/Budget.yaml` `spendCap.inputState`: setting
    `AWAITING_NEXT_PERIOD` on a non-enforced cap yields the bare 400 (I1); worth documenting in the field description.
11. Minor: the artifact's error table never records that spend-cap field violations return descriptive messages. That is
    the strongest evidence for C1 and should be stated explicitly (see A1 table).

## Leftover GCP resources

None. `GET /v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets` → `{}` after both probe scripts and after both acceptance runs.
Budgets created and deleted (all PLN, units 5-7): 1d12075f, 318bce94, bc2f5717, 1ee302fe, ea978a70, c3be785a, 114ff588,
c26c5d92, plus two by the acceptance runs (963668c6 and one in run 2), each confirmed 404 after delete.

## Changes outside /home/user/tpgb and the scratchpad

- `/home/user/review-root-cause.md` (this file). Nothing else. `/home/user/magic-modules` and `/home/user/mm-spendcap`
  are clean (`git status --short` empty); no git write commands run. In `/home/user/tpgb` the `input_state` flatten was
  patched for run 2 and then restored byte-for-byte from the saved copy; the pre-existing PLN test edit is untouched.
