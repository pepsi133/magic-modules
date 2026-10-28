> Date: 2026-10-28. Source: upstream PR 19315 head commit b1edf518a48760d6b34e011092970a0d98f67945.

# PR #19315 (`google_billing_budget.spend_cap`): why the create call returns 400

PR head: `DrFaust92:billingbudget-spend-cap` @ `b1edf518a48760d6b34e011092970a0d98f67945`, checked out as worktree
`/home/user/mm-spendcap` (branch `spendcap-investigation`).
Failing test: `TestAccBillingBudgetsBudget_billingBudgetSpendCapExample`. The error is
`Error creating Budget: googleapi: Error 400: Request contains an invalid argument.`

## TL;DR

1. **Most likely cause, confirmed in the generated code:** the provider always sends `notificationsRule.schemaVersion = "1.0"`.
   It does this because `all_updates_rule.schema_version` has `default_value: "1.0"`. The spend-cap API guide says the only
   `notificationsRule` field allowed is `enableProjectLevelRecipients=true`, and that "All other `NotificationsRule`
   parameters are unsupported." The documented create example sends only `enableProjectLevelRecipients`.
2. The CI project (`data.google_project`, which is `GOOGLE_PROJECT`) is probably **not linked to `GOOGLE_MASTER_BILLING_ACCOUNT`**.
   It is most likely billed by `GOOGLE_BILLING_ACCOUNT`, and spend caps appear to need the project's own billing account.
3. **The billing account is not eligible.** In the CI code, `MASTER_BILLING_ACCT` is described as the account that supports
   subaccounts, which means it is reseller- or parent-style. The docs limit spend caps to "first-party Google Cloud
   customers and Cloud Billing accounts" and say reseller accounts are out of scope. This is the author's question.

The following are ruled out by evidence:
- Output-only fields in the POST body.
- Needing to set `CONFIGURED` through an update instead of on create.
- A v1/v1beta1 mismatch.
- A wrong service ID.

## 1. Changed files (quoted in full / relevant hunk)

Commits on top of upstream main: `ef20c8beb billingbudgets: add spend_cap to google_billing_budget` and
`b1edf518a billingbudgets: correct spend cap sample service and make spend_basis explicit`.
The branch base is older than current main, so `git diff --stat` against a newer main also shows unrelated DMS files.
The PR itself touches only the two files below.

### `mmv1/templates/terraform/samples/services/billingbudgets/billing_budget_spend_cap.tf.tmpl` (new, full)

```hcl
data "google_billing_account" "account" {
  billing_account = "{{index $.TestEnvVars "billing_acct"}}"
}

data "google_project" "project" {
}

resource "google_billing_budget" "{{$.PrimaryResourceId}}" {
  billing_account = data.google_billing_account.account.id
  display_name    = "{{index $.ResourceIdVars "display_name"}}"

  budget_filter {
    projects               = ["projects/${data.google_project.project.number}"]
    services               = ["services/C7E2-9256-1C43"] # Gemini Enterprise Agent Platform
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
    calendar_period        = "MONTH"
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = "100"
    }
  }

  threshold_rules {
    threshold_percent = 0.5
    spend_basis       = "CURRENT_SPEND"
  }
  threshold_rules {
    threshold_percent = 0.8
    spend_basis       = "CURRENT_SPEND"
  }
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = []
    enable_project_level_recipients  = true
  }

  spend_cap {
    input_state = "CONFIGURED"
  }
}
```

### `mmv1/products/billingbudgets/Budget.yaml` (+51 lines; added sample and property)

```yaml
  - name: billing_budget_spend_cap
    primary_resource_id: budget
    steps:
      - name: billing_budget_spend_cap
        resource_id_vars:
          display_name: Example Spend Cap Budget
        test_vars_overrides:
          display_name: '"Example Spend Cap Budget" + randomSuffix'
        test_env_vars:
          billing_acct: MASTER_BILLING_ACCT
...
  - name: spendCap
    type: NestedObject
    description: |
      The spend cap configured for this budget. When set, usage of the
      budget's service is paused once spend exceeds the budget amount, until
      the next period or until the cap is lifted. Spend cap budgets must
      filter on exactly one project and one eligible service, use
      `EXCLUDE_ALL_CREDITS`, a `MONTH` calendar period, a `specified_amount`,
      threshold rules of 0.5, 0.8 and 1.0 on `CURRENT_SPEND`, and
      `enable_project_level_recipients = true`. See
      https://cloud.google.com/billing/docs/how-to/budgets-spend-caps.

      While `output_state` is `ENFORCED`, only `input_state` can be changed.
    update_mask_fields:
      - spendCap.inputState
    properties:
      - name: inputState
        type: Enum
        description: |
          The desired state of the spend cap. Must be `CONFIGURED` on create.
          Set to `AWAITING_NEXT_PERIOD` to lift an enforced cap until the next
          period starts.
        required: true
        enum_values:
          - CONFIGURED
          - AWAITING_NEXT_PERIOD
      - name: outputState
        type: Enum
        description: |
          The actual resting state of the spend cap.
        output: true
        enum_values:
          - STATE_UNSPECIFIED
          - CONFIGURED
          - ENFORCED
          - AWAITING_NEXT_PERIOD
      - name: reconciling
        type: Boolean
        description: |
          Whether the server is processing a state transition.
        output: true
```

The rest of `Budget.yaml` is unchanged. These existing properties matter here:
- `all_updates_rule.schema_version`: `default_value: "1.0"`, with custom flatten `default_if_empty`.
- `disable_default_iam_recipients` and `enable_project_level_recipients`: `default_value: false`.
- `budget_filter.credit_types_treatment`: `default_value: INCLUDE_ALL_CREDITS`.
- `all_updates_rule`: `at_least_one_of` covering `pubsub_topic` and `monitoring_notification_channels`. This is why the sample
  sets `monitoring_notification_channels = []`.

## 2. API research

### Sources
- Discovery documents, fetched 2026-10-28 (revision `20261018`):
  - `https://billingbudgets.googleapis.com/$discovery/rest?version=v1`
  - `...version=v1beta1`
- Product guide: https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps. The old cloud.google.com URL returns a 301 to this one.
- API guide: https://docs.cloud.google.com/billing/docs/how-to/budget-api-spend-cap
- REST reference: https://cloud.google.com/billing/docs/reference/budget/rest/v1/billingAccounts.budgets
- Release notes:
  - Cloud Billing release notes, 2026-07-27: "spend cap budgets are now available for a limited set of services (Preview)".
  - Google Cloud cross-product release notes, 2026-10-13: spend caps are GA for a limited set of services, in the console and the Budget API.
    - https://docs.cloud.google.com/billing/docs/release-notes
    - https://finopsweekly.com/news/gcp-updates-2026-07-30

### API version
`spendCap` / `GoogleCloudBillingBudgetsV1SpendCap` exists **only in v1**. The string `spendCap` does not appear anywhere in the
v1beta1 Discovery document. The provider's `product.yaml` uses `https://billingbudgets.googleapis.com/v1/`, so the version is correct.

### `SpendCap` schema (v1 Discovery, verbatim)
- `inputState` (enum `STATE_UNSPECIFIED | CONFIGURED | ENFORCED | AWAITING_NEXT_PERIOD`):
  "Required. The desired state specified by the user. Valid values for mutation:
  - `CONFIGURED`: Must be set when creating a spend cap (`CreateBudget`). Also valid when updating (`UpdateBudget`) to activate
    the spend cap. If the spend cap is in state `AWAITING_NEXT_PERIOD`, `input_state` must be set to `CONFIGURED`.
  - `AWAITING_NEXT_PERIOD`: Valid only when updating (`UpdateBudget`) to explicitly lift an enforced cap. Not allowed if the spend
    cap is in state `AWAITING_NEXT_PERIOD`.

  Supplying any other value will result in an INVALID_ARGUMENT error."
- `outputState` (same enum, `readOnly: true`): "Output only. The actual resting state of the spend cap."
- `reconciling` (bool, `readOnly: true`): "Output only. Indicates whether the server is actively processing a state transition or async workflow."
- `Budget.spendCap`: "When `spend_cap` is set, strict field restrictions apply to the budget (see field-level comments on
  `ownership_scope`, `budget_filter`, `amount`, `threshold_rules`, and `notifications_rule`).
  When `spend_cap.output_state` is `ENFORCED`, only `spend_cap.input_state` can be modified in an `UpdateBudget` request ...;
  modifying any other budget field while enforced will fail with `FAILED_PRECONDITION`.
  If the existing resource is a spend cap and an `update_mask` is supplied in an `UpdateBudget` request, `spend_cap` or
  `spend_cap.input_state` must be specified in the update mask.
  To convert a spend cap budget to a regular budget, specify `spend_cap` in the `update_mask` and omit `spend_cap` from the
  budget in the request."

### Documented restrictions when `spendCap` is set

| Area | Restriction (source) |
|---|---|
| Eligible services | Exactly one, from this list (guide): Gemini API `AEFD-7695-64FA` (generativelanguage.googleapis.com); Gemini Enterprise Agent Platform (formerly Vertex AI) `C7E2-9256-1C43` (aiplatform.googleapis.com); Cloud Run `152E-C115-5142` (run.googleapis.com); Cloud Run functions `29E7-DA93-CA13` (cloudfunctions.googleapis.com). Discovery: "services filter must be set and must contain exactly one service from this list". |
| projects | "Must be set when `spend_cap` is set; must contain exactly one project." Guide: folders, orgs, labels, and multi-project or multi-service budgets are out of scope. The API guide example uses `projects/<project-id>` in the request and gets `projects/<number>` back. |
| resourceAncestors, labels, subaccounts, creditTypes | "Not supported when `spend_cap` is set; must be empty." |
| creditTypesTreatment | "Must be set to `EXCLUDE_ALL_CREDITS`." Costs are gross and estimated. |
| period | `calendarPeriod` must be `MONTH` (or unset, which defaults to MONTH). `customPeriod`, QUARTER, and YEAR are not supported. |
| amount | `specifiedAmount` must be >= 0, and `lastPeriodAmount` is not supported. The currency code, if given, must match the billing account's currency. |
| thresholdRules | Exactly three rules at 0.5, 0.8, and 1.0. `spendBasis` must be `CURRENT_SPEND` or `BASIS_UNSPECIFIED`. FORECASTED_SPEND is not supported. |
| notificationsRule | Must be set. `enableProjectLevelRecipients` must be `true`, and `disableDefaultIamRecipients` must be false or unset. `pubsubTopic` and `monitoringNotificationChannels` must be empty. API guide: **"All other `NotificationsRule` parameters are unsupported."** The documented create body contains only `notificationsRule.enableProjectLevelRecipients = true`, with no `schemaVersion`. |
| ownershipScope | `OWNERSHIP_SCOPE_UNSPECIFIED` or `ALL_USERS`. `BILLING_ACCOUNT` is not supported. |
| Create vs update | `inputState=CONFIGURED` **must be set on CreateBudget**, so creating with the cap set is the intended path. `AWAITING_NEXT_PERIOD` is valid only on update. |
| Billing account eligibility | "Spend cap budgets are limited to first-party Google Cloud customers and Cloud Billing accounts." Reseller billing accounts are out of scope. The docs do not distinguish self-serve from invoiced accounts. |
| Project/account link | Not stated directly. The guide says that "if a project moves to another billing account, its spend caps are deleted on the old account and must be re-created on the new one". This implies the project must be billed by the budget's billing account. This is an inference. |
| Duplicates | "deduplication policy that prevents users from creating more than one budget with the same scope". |
| IAM | Billing account level: `billing.budgets.configureSpendCap`, included in Billing Account Administrator, or in Billing Account Costs Manager plus project Editor. Project level: `billing.resourcebudgets.configureSpendCap` plus `resourcemanager.projects.get` and `billing.resourcebudgets.read`/`write`. An IAM gap would normally return 403, not 400. |
| Enforced | Edits and deletes are blocked while `ENFORCED`. You lift the cap with `inputState=AWAITING_NEXT_PERIOD`, or it lifts automatically at the next month. Recovery takes up to 1 hour. |
| Launch stage | Preview on 2026-07-27, then GA for a limited set of services on 2026-10-13 (release notes). |

## 3. Sample vs restrictions, and what the provider actually sends

I generated the GA provider for `billingbudgets` only (`go run . --output <scratchpad>/gen --version ga --product billingbudgets`)
and read `resource_billing_budget.go`.
`resourceBillingBudgetsBudgetCreate` builds the POST body from the expanders. Each sub-expander drops values where
`tpgresource.IsEmptyValue` is true, so the following hold:

- `spendCap`: the expander also tries `output_state` and `reconciling`. On create they are unknown or zero (`""` and `false`), so they are
  dropped. **The POST sends only `{"inputState":"CONFIGURED"}`.**
- `notificationsRule`:
  - `schema_version` has schema `Default: "1.0"`, so it is non-empty and **always sent**.
  - `monitoring_notification_channels = []` is empty and dropped.
  - `disable_default_iam_recipients=false` is dropped.
  - `enable_project_level_recipients=true` is sent.
- `budgetFilter`: `labels` goes through a custom expand that returns an empty map, which is dropped. `customPeriod` and the other filters are not sent.
- `ownershipScope` is not sent.

Effective POST body (to `https://billingbudgets.googleapis.com/v1/billingAccounts/<MASTER>/budgets`):

```json
{
  "displayName": "Example Spend Cap Budget<suffix>",
  "budgetFilter": {
    "projects": ["projects/<GOOGLE_PROJECT number>"],
    "creditTypesTreatment": "EXCLUDE_ALL_CREDITS",
    "services": ["services/C7E2-9256-1C43"],
    "calendarPeriod": "MONTH"
  },
  "amount": {"specifiedAmount": {"currencyCode": "USD", "units": "100"}},
  "thresholdRules": [
    {"thresholdPercent": 0.5, "spendBasis": "CURRENT_SPEND"},
    {"thresholdPercent": 0.8, "spendBasis": "CURRENT_SPEND"},
    {"thresholdPercent": 1.0, "spendBasis": "CURRENT_SPEND"}
  ],
  "notificationsRule": {"schemaVersion": "1.0", "enableProjectLevelRecipients": true},
  "spendCap": {"inputState": "CONFIGURED"}
}
```

Line-by-line comparison with the docs:

| Sample line | Rule | Verdict |
|---|---|---|
| `billing_account = MASTER_BILLING_ACCT` | First-party, non-reseller account; the project should be billed by it | **Suspect** (H2, H3) |
| `projects = ["projects/${number}"]` (CI `GOOGLE_PROJECT`) | Exactly one project | OK in shape. Suspect if the project is not on MASTER (H2) |
| `services = ["services/C7E2-9256-1C43"]` | One eligible service | OK. Matches the guide table for Gemini Enterprise Agent Platform |
| `credit_types_treatment = "EXCLUDE_ALL_CREDITS"` | Required value | OK |
| `calendar_period = "MONTH"` | MONTH or unset | OK |
| `specified_amount { currency_code = "USD", units = "100" }` | Specified, >= 0, currency must match the account | OK if MASTER is billed in USD. Other samples on MASTER use USD and pass, so low risk |
| 3 x `threshold_rules` 0.5/0.8/1.0 `CURRENT_SPEND` | Exactly these | OK |
| `all_updates_rule { monitoring_notification_channels = [], enable_project_level_recipients = true }` | Only `enableProjectLevelRecipients=true` allowed | **Violates: provider adds `schemaVersion: "1.0"`** (H1) |
| `spend_cap { input_state = "CONFIGURED" }` | CONFIGURED on create | OK. The output-only subfields are not sent on create |

### Problems in the resource design (separate from the 400)

- **Update mask.** The API requires `spend_cap` or `spend_cap.input_state` in **every** `update_mask` once the budget is a spend cap.
  The generated Update adds `spendCap.inputState` only when `d.HasChange("spend_cap")`. Changing only `amount` (the API guide's
  own example uses `updateMask=amount.specifiedAmount,spendCap.inputState`) will therefore be rejected. This needs a custom
  `pre_update`/encoder that always appends `spendCap.inputState` when `spend_cap` is set. The same applies to the documented
  conversion to a regular budget: remove `spend_cap` and send it in the mask, with an empty body field.
- **Output-only fields on PATCH.** On PATCH the expander will send `spendCap.outputState` taken from state, for example `"CONFIGURED"`.
  `reconciling=false` is dropped. The mask limits what is applied, so this is probably harmless, but output-only fields should
  not be sent. Fix with `url_param_only`-style handling, or a custom expand that emits only `inputState`.
- **`schema_version` default.** The default `"1.0"` has to be suppressed whenever `spend_cap` is set. Option: an encoder that deletes
  `notificationsRule.schemaVersion` when `spendCap` is present and `pubsubTopic` is empty. The Update path also sends
  `notificationsRule.schemaVersion` in its mask when `all_updates_rule` changes.

## 4. Ranked hypotheses for `400 INVALID_ARGUMENT` on create

Common setup for the commands below. Use the same credentials as CI. `x-goog-user-project` is needed with user ADCs.

```bash
export BILLING_ACCOUNT_ID=XXXXXX-XXXXXX-XXXXXX   # the MASTER billing account
export PROJECT_ID=my-project                    # CI GOOGLE_PROJECT
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
export TOKEN=$(gcloud auth print-access-token)
API=https://billingbudgets.googleapis.com/v1/billingAccounts/$BILLING_ACCOUNT_ID/budgets
```

A successful create in any test below makes a real spend-cap budget, so delete it afterwards with
`curl -X DELETE -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT_ID" https://billingbudgets.googleapis.com/v1/<name from response>`.
Because of the dedupe policy, delete it before running the next create.

### H1 (most likely; confirmed in code): `notificationsRule.schemaVersion: "1.0"` is rejected for spend caps
- Evidence:
  - The generated create always sends `schemaVersion` (schema `Default: "1.0"`, non-empty).
  - The API guide says that, for spend caps, "All other `NotificationsRule` parameters are unsupported" besides
    `enableProjectLevelRecipients`.
  - The documented create body omits `schemaVersion`.
  - The Discovery field descriptions do not list `schemaVersion` explicitly, which is why this stays a hypothesis until H1 is tested.
- Test: a single create using the documented body, which omits `schemaVersion`. If this succeeds and the provider-shaped body
  (the same command with `"schemaVersion": "1.0"` added) fails with 400, H1 is confirmed.
  ```bash
  curl -sS -X POST "$API" -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT_ID" \
    -H "Content-Type: application/json" -d '{
    "displayName": "spendcap-h1",
    "budgetFilter": {"projects": ["projects/'"$PROJECT_NUMBER"'"], "services": ["services/C7E2-9256-1C43"],
                     "creditTypesTreatment": "EXCLUDE_ALL_CREDITS", "calendarPeriod": "MONTH"},
    "amount": {"specifiedAmount": {"currencyCode": "USD", "units": "100"}},
    "thresholdRules": [{"thresholdPercent": 0.5, "spendBasis": "CURRENT_SPEND"},
                       {"thresholdPercent": 0.8, "spendBasis": "CURRENT_SPEND"},
                       {"thresholdPercent": 1.0, "spendBasis": "CURRENT_SPEND"}],
    "notificationsRule": {"enableProjectLevelRecipients": true},
    "spendCap": {"inputState": "CONFIGURED"}
  }'
  ```
- Provider fix if confirmed: drop `schemaVersion` from the body when `spendCap` is set. Use a custom encoder or a `custom_expand`
  for `schema_version`, plus matching handling in the update encoder. Keep the `default_if_empty` flatten so there is no diff.

### H2: the CI project is not billed by `GOOGLE_MASTER_BILLING_ACCOUNT`
- Evidence:
  - The sample scopes the budget to `data.google_project.project`, which is `GOOGLE_PROJECT`.
  - In `mmv1/third_party/terraform/envvar/envvar_utils.go`, `GOOGLE_BILLING_ACCOUNT` is "the billing account that will be charged
    for the infrastructure used during testing", while MASTER is "the billing account that will be modified to test
    billing-related functionality ... support[s] subaccounts". These are separate secrets in `.ci/gcb-*.yml`.
  - Normal budgets (for example `billing_budget_notify_project_recipient`) accept any project number. Spend caps, however,
    enforce pausing on that project's usage, and the guide says caps are deleted when the project moves billing accounts.
    This implies the project must be paid by the budget's account.
- Test:
  ```bash
  gcloud billing projects describe $PROJECT_ID --format='value(billingAccountName)'
  ```
  If the result is not `billingAccounts/$BILLING_ACCOUNT_ID`, H2 is plausible. To confirm, run the H1 command with a project
  that *is* linked to that account.
- Provider/test fix if confirmed: create a project in the test linked to the target account, or point the sample at
  `BILLING_ACCT` with `GOOGLE_PROJECT`. A project created inside the test would also need the eligible service's API
  (aiplatform) enabled, which is likely but not documented.

### H3: the billing account is not eligible (reseller/parent account with subaccounts, or not first-party)
- Evidence:
  - The docs say: "limited to first-party Google Cloud customers and Cloud Billing accounts", "Reseller billing accounts are out of scope".
  - In CI, MASTER is specifically the account that supports subaccounts, which is a reseller/partner-style parent.
  - The author also reports that eligibility is limited. The exact error code for an ineligible account is not documented.
    INVALID_ARGUMENT is plausible, but it could also be FAILED_PRECONDITION or PERMISSION_DENIED.
- Test:
  ```bash
  gcloud billing accounts list --filter="masterBillingAccount=billingAccounts/$BILLING_ACCOUNT_ID" --format='value(name)'
  ```
  Any output means the account has subaccounts, so it is reseller-style and likely ineligible. Also run
  `gcloud billing accounts describe $BILLING_ACCOUNT_ID` and check `masterBillingAccount` (set if it is itself a subaccount)
  and `currencyCode`.
  Definitive check: run the H1 body (without `schemaVersion`) against this account with a project linked to it. A 400 there
  means the account or project is ineligible. Running the same command against a known first-party self-serve account would
  then succeed.
- Answer to the author's question: this cannot be answered from public sources. It needs a maintainer with access to the CI
  billing account, either to run the commands above or to check the private debug log for an `ErrorInfo`/`BadRequest` field
  violation.

### H4: currency mismatch (`currencyCode: "USD"`)
- Evidence: the docs say the currency must match the account's currency. Every other `Budget` sample on MASTER uses USD and
  passes, so this is unlikely.
- Test:
  ```bash
  gcloud billing accounts describe $BILLING_ACCOUNT_ID --format='value(currencyCode)'
  ```
  The result should be `USD`.

### H5: service ID or service-not-in-use
- Evidence: `C7E2-9256-1C43` exactly matches the guide's table for Gemini Enterprise Agent Platform (aiplatform), so this is
  unlikely. The docs do not mention whether the API must be enabled on the project.
- Test:
  ```bash
  gcloud services list --enabled --project=$PROJECT_ID --filter='config.name=aiplatform.googleapis.com'
  ```
  Alternatively, rerun the H1 command with `services/AEFD-7695-64FA` (Gemini API) or `services/152E-C115-5142` (Cloud Run).

### H6: a duplicate budget with the same scope already exists
- Evidence: the docs mention a dedupe policy. `exclude_sweeper: true` means leaked budgets on MASTER are never swept. This is
  unlikely because earlier attempts would also have failed, and a duplicate would more likely return ALREADY_EXISTS.
- Test:
  ```bash
  gcloud billing budgets list --billing-account=$BILLING_ACCOUNT_ID --format=json \
    | jq '.[] | select(.spendCap != null) | {name, budgetFilter}'
  ```

### Ruled out
- **Output-only `outputState`/`reconciling` sent on create.** The generated expander drops them because they are empty on create.
- **Must be created without a cap and then updated.** The docs say `CONFIGURED` "Must be set when creating a spend cap (`CreateBudget`)".
- **Field only in v1beta1.** It is only in **v1**, and the provider uses v1.
- **IAM.** A missing `billing.budgets.configureSpendCap` permission would normally return 403 PERMISSION_DENIED, not 400.
  You can still verify it with:
  ```bash
  gcloud billing accounts get-iam-policy $BILLING_ACCOUNT_ID
  ```
  The CI service account should have `roles/billing.admin`.

## Suggested next steps for the PR

1. Have the maintainer run H1 and the H2/H3 checks with CI credentials, or read the private debug log for the response's
   `details[].fieldViolations` (the field name is usually included).
2. Make `schemaVersion` omitted when `spend_cap` is set (H1). If H2 or H3 is confirmed, change the sample so it uses an eligible
   first-party account and a project billed by it. If no such CI account exists, mark the sample `exclude_test: true` and keep a
   handwritten test that is skipped without an opt-in env var. Per the repo ground rules, any skip must carry a comment
   justifying it.
3. Fix the update mask (always include `spendCap.inputState` when the cap is set) and stop sending `outputState` on PATCH.
