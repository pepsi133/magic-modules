# Spend-cap acceptance test runs and project-billing-link probe (2026-10-28)

Provider: `terraform-provider-google-beta` at `7e21030c`, with `billingbudgets` generated from PR head `b1edf518`.
Account: the test billing account (first-party, PLN). In this environment `GOOGLE_BILLING_ACCOUNT` and
`GOOGLE_MASTER_BILLING_ACCOUNT` are the same account. `GOOGLE_PROJECT` is `${GOOGLE_PROJECT}`
(number `${GOOGLE_PROJECT_NUMBER}`), and that project is billed by this account.
Nothing under `mmv1/` was changed. The PLN run used a local edit to the generated test file in the downstream checkout only.

## TL;DR

1. **The test as generated (USD 100) FAILS on create** with the bare `400 Request contains an invalid argument.`
   This is the same error upstream CI reports.
2. **With PLN 5, create succeeds, but the test still FAILS on a permadiff.** The API never returns
   `spendCap.inputState`, so `spend_cap.0.input_state` reads back empty. The post-apply plan therefore wants to set
   `input_state = "CONFIGURED"` again. Once the 400 is fixed, the PR will fail upstream on this next.
3. **H2 (project billed by a different account) gives the same bare 400, but the rule is not specific to spend caps.**
   A *regular* budget whose filter names a project billed elsewhere fails with the identical 400. Projects billed by
   the account but invisible to the caller succeed. Project refs that do not resolve (a bogus ID or a random number)
   are **silently dropped** from the filter, and the create returns 200.
4. **Currency mismatch is not specific to spend caps either.** A regular budget in USD on this PLN account also fails
   with the bare 400. The existing upstream budget samples hard-code USD on `MASTER_BILLING_ACCT` (assumed passing in
   CI; not verified here), so MASTER is most likely billed in USD. That would make H4 an unlikely cause of the upstream
   failure; see section 4.

## 1. Test as generated (USD 100): FAIL

`/home/user/spendcap-usd.log`, excerpt (proxy and response transport headers removed). The provider omits
`calendarPeriod` because the `MONTH` value is diff-suppressed against the default; the API fills it in (see the PLN
response).

```
POST /v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets?alt=json HTTP/1.1
Host: billingbudgets.googleapis.com
Content-Length: 555
Content-Type: application/json

{
 "amount": {
  "specifiedAmount": {
   "currencyCode": "USD",
   "units": "100"
  }
 },
 "budgetFilter": {
  "creditTypesTreatment": "EXCLUDE_ALL_CREDITS",
  "projects": [
   "projects/${GOOGLE_PROJECT_NUMBER}"
  ],
  "services": [
   "services/C7E2-9256-1C43"
  ]
 },
 "displayName": "Example Spend Cap Budgetepyw73zsjd",
 "notificationsRule": {
  "enableProjectLevelRecipients": true,
  "schemaVersion": "1.0"
 },
 "spendCap": {
  "inputState": "CONFIGURED"
 },
 "thresholdRules": [
  {
   "spendBasis": "CURRENT_SPEND",
   "thresholdPercent": 0.5
  },
  {
   "spendBasis": "CURRENT_SPEND",
   "thresholdPercent": 0.8
  },
  {
   "spendBasis": "CURRENT_SPEND",
   "thresholdPercent": 1
  }
 ]
}

HTTP/1.1 400 Bad Request

7f
{
  "error": {
    "code": 400,
    "message": "Request contains an invalid argument.",
    "status": "INVALID_ARGUMENT"
  }
}
322:    resource_billing_budget_generated_test.go:507: Step 1/3 error: Error running apply: exit status 1
323-        
324-        Error: Error creating Budget: googleapi: Error 400: Request contains an invalid argument.
```

Result: `--- FAIL: TestAccBillingBudgetsBudget_billingBudgetSpendCapExample (5.72s)` in step 1/3 (create). No budget
was created.

## 2. PLN 5 (local edit of the generated test only): FAIL (permadiff), create OK

The only edit was in `google-beta/services/billingbudgets/resource_billing_budget_generated_test.go` in the downstream
checkout: `currency_code = "PLN"`, `units = "5"`. Log: `/home/user/spendcap-pln.log`. Excerpt: the POST, the 200
response, and the read-after-create GET, which shows `spendCap.outputState`.

```
POST /v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets?alt=json HTTP/1.1
Host: billingbudgets.googleapis.com
Content-Length: 553
Content-Type: application/json

{
 "amount": {
  "specifiedAmount": {
   "currencyCode": "PLN",
   "units": "5"
  }
 },
 "budgetFilter": {
  "creditTypesTreatment": "EXCLUDE_ALL_CREDITS",
  "projects": [
   "projects/${GOOGLE_PROJECT_NUMBER}"
  ],
  "services": [
   "services/C7E2-9256-1C43"
  ]
 },
 "displayName": "Example Spend Cap Budgetj0nvyjfhe0",
 "notificationsRule": {
  "enableProjectLevelRecipients": true,
  "schemaVersion": "1.0"
 },
 "spendCap": {
  "inputState": "CONFIGURED"
 },
 "thresholdRules": [
  {
   "spendBasis": "CURRENT_SPEND",
   "thresholdPercent": 0.5
  },
  {
   "spendBasis": "CURRENT_SPEND",
   "thresholdPercent": 0.8
  },
  {
   "spendBasis": "CURRENT_SPEND",
   "thresholdPercent": 1
  }
 ]
}

HTTP/1.1 200 OK

377
{
  "name": "billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/833d5a7f-855c-44ff-b210-991f37f5cb6e",
  "displayName": "Example Spend Cap Budgetj0nvyjfhe0",
  "budgetFilter": {
    "projects": [
"projects/${GOOGLE_PROJECT_NUMBER}"
    ],
    "services": [
"services/C7E2-9256-1C43"
    ],
    "creditTypesTreatment": "EXCLUDE_ALL_CREDITS",
    "calendarPeriod": "MONTH"
  },
  "amount": {
    "specifiedAmount": {
      "currencyCode": "PLN",
      "units": "5"
    }
  },
  "thresholdRules": [
    {
      "thresholdPercent": 0.5,
      "spendBasis": "CURRENT_SPEND"
    },
    {
      "thresholdPercent": 0.8,
      "spendBasis": "CURRENT_SPEND"
    },
    {
      "thresholdPercent": 1,
      "spendBasis": "CURRENT_SPEND"
    }
  ],
  "notificationsRule": {
    "enableProjectLevelRecipients": true
  },

GET /v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/833d5a7f-855c-44ff-b210-991f37f5cb6e?alt=json HTTP/1.1
Host: billingbudgets.googleapis.com
HTTP/1.1 200 OK

377
{
  "name": "billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/833d5a7f-855c-44ff-b210-991f37f5cb6e",
  "displayName": "Example Spend Cap Budgetj0nvyjfhe0",
  "budgetFilter": {
    "projects": [
"projects/${GOOGLE_PROJECT_NUMBER}"
    ],
    "services": [
"services/C7E2-9256-1C43"
    ],
    "creditTypesTreatment": "EXCLUDE_ALL_CREDITS",
    "calendarPeriod": "MONTH"
  },
  "amount": {
    "specifiedAmount": {
      "currencyCode": "PLN",
      "units": "5"
    }
  },
  "thresholdRules": [
    {
      "thresholdPercent": 0.5,
      "spendBasis": "CURRENT_SPEND"
    },
    {
      "thresholdPercent": 0.8,
      "spendBasis": "CURRENT_SPEND"
    },
    {
      "thresholdPercent": 1,
      "spendBasis": "CURRENT_SPEND"
    }
  ],
  "notificationsRule": {
    "enableProjectLevelRecipients": true
```

Post-apply (non-refresh) plan, which is the failure:

```
resource_billing_budget_generated_test.go:507: Step 1/3 error: After applying this test step, the non-refresh plan was not empty.
    stdout:
    
    
    Terraform used the selected providers to generate the following execution
    plan. Resource actions are indicated with the following symbols:
      ~ update in-place
    
    Terraform will perform the following actions:
    
      # google_billing_budget.budget will be updated in-place
      ~ resource "google_billing_budget" "budget" {
            id              = "billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/833d5a7f-855c-44ff-b210-991f37f5cb6e"
            name            = "833d5a7f-855c-44ff-b210-991f37f5cb6e"
            # (4 unchanged attributes hidden)
    
          ~ budget_filter {
              + credit_types           = []
              + resource_ancestors     = []
              + subaccounts            = []
                # (5 unchanged attributes hidden)
            }
    
          ~ spend_cap {
              + input_state  = "CONFIGURED"
                # (2 unchanged attributes hidden)
            }
```

Destroy (CheckDestroy GET returns 404):

```
DELETE /v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/833d5a7f-855c-44ff-b210-991f37f5cb6e?alt=json HTTP/1.1
Host: billingbudgets.googleapis.com
HTTP/1.1 200 OK
GET /v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/833d5a7f-855c-44ff-b210-991f37f5cb6e?alt=json HTTP/1.1
Host: billingbudgets.googleapis.com
HTTP/1.1 404 Not Found
```

Result: `--- FAIL: TestAccBillingBudgetsBudget_billingBudgetSpendCapExample (11.33s)` in step 1/3, with "After applying
this test step, the non-refresh plan was not empty." Steps 2 (import verify) and 3 (identity import) were not reached.
After the run, `GET .../billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets` returned `{}`.

Diagnosis of the diff:
- `spend_cap.input_state`: the generated `flattenBillingBudgetsBudgetSpendCapInputState` returns the API value as-is.
  The API returns only `outputState` (and `reconciling` when it is true), never `inputState`. This is a real permadiff
  and has to be fixed in the PR (section 6).
- `budget_filter.credit_types/resource_ancestors/subaccounts = []`: these are shown as additions inside a block that is
  being updated anyway. They are most likely display noise that comes with the `spend_cap` change. The regular budget
  examples do not show them. This was **not verified** here, because the resource code was not patched (out of scope);
  re-check after the `input_state` fix.

## 3. H2 probe: project billed by a different account (curl, PLN body as in probe-proxy.sh variant (c))

Finding a project not billed by the test billing account:
- `gcloud projects list` and `cloudresourcemanager v1 projects` / `v3 projects:search` return only
  `${GOOGLE_PROJECT}`.
- Every other candidate returns 403 on both `cloudresourcemanager v1/projects/<id>` and `cloudbilling .../billingInfo`.
- `GET cloudbilling v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/projects` lists the projects this account bills:
  `<other-project-2>`, `<other-project-1>`, `${GOOGLE_PROJECT}`.
- So `<other-project-4>`, `<other-project-3>` and `<other-project-5>` are org projects **not billed
  by this account**.
- Their project numbers are not readable, so the filter uses the documented `projects/{project_id}` form. A control
  confirms the API resolves this form to the number: `projects/${GOOGLE_PROJECT}` is stored as
  `projects/${GOOGLE_PROJECT_NUMBER}`.
- `<other-project-1>` and `<other-project-2>` are a useful second control. They are billed by the account but also
  return 403 to the caller, which separates "billed by the account" from "visible to the caller".

Body template (only `displayName`, `budgetFilter.projects`, and the presence of `spendCap` vary):
`services/C7E2-9256-1C43`, `EXCLUDE_ALL_CREDITS`, `MONTH`, PLN 5, thresholds 0.5/0.8/1.0 `CURRENT_SPEND`,
`notificationsRule.enableProjectLevelRecipients=true`, plus `spendCap.inputState=CONFIGURED` for the "spendcap" kind.

| Probe | Project ref | Billed by the test billing account? | Spend cap | Result |
|---|---|---|---|---|
| ctl-regular-id | `projects/${GOOGLE_PROJECT}` | yes | no | **200**, stored as `projects/${GOOGLE_PROJECT_NUMBER}` |
| ctl-spendcap-billed-number | `projects/${GOOGLE_PROJECT_NUMBER}` | yes | yes | **200**, outputState CONFIGURED |
| ctl-spendcap-billed-id | `projects/${GOOGLE_PROJECT}` | yes | yes | **200**, outputState CONFIGURED |
| h2-spendcap-unbilled | `projects/<other-project-4>` | no | yes | **400** bare INVALID_ARGUMENT |
| h2-spendcap-unbilled | `projects/<other-project-3>` | no | yes | **400** bare INVALID_ARGUMENT |
| h2-spendcap-unbilled | `projects/<other-project-5>` | no | yes | **400** bare INVALID_ARGUMENT |
| h3-regular-unbilled (task 3) | `projects/<other-project-4>` | no | no | **400** bare INVALID_ARGUMENT |
| h3-regular-unbilled (task 3) | `projects/<other-project-3>` | no | no | **400** bare INVALID_ARGUMENT |
| h3-regular-unbilled (task 3) | `projects/<other-project-5>` | no | no | **400** bare INVALID_ARGUMENT |
| ctl-spendcap-billed-invisible | `projects/<other-project-1>` | yes (caller gets 403) | yes | **200**, stored as `projects/<other-project-1-number>` |
| ctl-regular-billed-invisible | `projects/<other-project-1>` | yes (caller gets 403) | no | **200** |
| ctl-spendcap-billed-invisible | `projects/<other-project-2>` | yes (caller gets 403) | yes | **200**, stored as `projects/<other-project-2-number>` |
| ctl-regular-billed-invisible | `projects/<other-project-2>` | yes (caller gets 403) | no | **200** |
| ctl-spendcap-nonexistent | `projects/does-not-exist-zz-<ts>` | n/a | yes | **200**, `projects` **dropped** from the stored filter |
| ctl-regular-nonexistent | `projects/does-not-exist-zz-<ts>` | n/a | no | **200**, `projects` dropped |
| ctl-spendcap-random-number | `projects/123456789012` | n/a | yes | **200**, `projects` dropped, outputState CONFIGURED |
| ctl-regular-random-number | `projects/123456789012` | n/a | no | **200**, `projects` dropped |
| ctl-regular-usd-billed | `projects/${GOOGLE_PROJECT_NUMBER}`, **USD** | yes | no | **400** bare INVALID_ARGUMENT |

Every created budget was deleted right away (DELETE 200, then GET 404). The budget list was `{}` before and after.

Interpretation:
- **H2 is real but not specific to spend caps.** Naming an existing project that the budget's billing account does not
  bill gives the same detail-less 400 for any budget, with or without `spendCap`.
- Caller visibility is not the factor: projects the caller cannot read still work if the account bills them.
- **Caveat:** for the unbilled projects only the `projects/{id}` form was testable, because their numbers are not
  readable. A billed-elsewhere project given *by number* was not tested. Unknown numbers are silently dropped, so it is
  possible that a number for a project billed elsewhere is also dropped rather than rejected. If so, a regular budget
  would pass (filtering nothing), while a spend cap would probably still fail or behave differently.
- Side finding: a spend cap whose single project ref is dropped is still created with `outputState: CONFIGURED`, even
  though the filter then has **no project**. The "exactly one project" rule is not enforced after resolution.

<details><summary>H2/H3 probe output, verbatim</summary>

```
===== ctl-regular-id (regular, projects/${GOOGLE_PROJECT}) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-ctl-regular-id-1793211081","budgetFilter":{"projects":["projects/${GOOGLE_PROJECT}"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true}}
<<< HTTP 200
{"name":"billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/5ce3b805-5d0a-4a7d-9098-d7a1194717f1","displayName":"h2-ctl-regular-id-1793211081","budgetFilter":{"projects":["projects/${GOOGLE_PROJECT_NUMBER}"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"etag":"1793211082841289"}
>>> DELETE billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/5ce3b805-5d0a-4a7d-9098-d7a1194717f1
<<< HTTP 200
>>> GET billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/5ce3b805-5d0a-4a7d-9098-d7a1194717f1 (expect 404)
<<< HTTP 404
===== ctl-spendcap-billed-number (spendcap, projects/${GOOGLE_PROJECT_NUMBER}) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-ctl-spendcap-billed-number-1793211093","budgetFilter":{"projects":["projects/${GOOGLE_PROJECT_NUMBER}"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"spendCap":{"inputState":"CONFIGURED"}}
<<< HTTP 200
{"name":"billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/07258cdc-e4a7-4d69-9a9b-62bde7e43680","displayName":"h2-ctl-spendcap-billed-number-1793211093","budgetFilter":{"projects":["projects/${GOOGLE_PROJECT_NUMBER}"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"etag":"1793211094769882","spendCap":{"outputState":"CONFIGURED"}}
>>> DELETE billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/07258cdc-e4a7-4d69-9a9b-62bde7e43680
<<< HTTP 200
>>> GET billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/07258cdc-e4a7-4d69-9a9b-62bde7e43680 (expect 404)
<<< HTTP 404
===== ctl-spendcap-billed-id (spendcap, projects/${GOOGLE_PROJECT}) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-ctl-spendcap-billed-id-1793211095","budgetFilter":{"projects":["projects/${GOOGLE_PROJECT}"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"spendCap":{"inputState":"CONFIGURED"}}
<<< HTTP 200
{"name":"billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/9109fcfc-fe1e-44f0-a24c-b8aeb7e19949","displayName":"h2-ctl-spendcap-billed-id-1793211095","budgetFilter":{"projects":["projects/${GOOGLE_PROJECT_NUMBER}"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"etag":"1793211096847673","spendCap":{"outputState":"CONFIGURED"}}
>>> DELETE billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/9109fcfc-fe1e-44f0-a24c-b8aeb7e19949
<<< HTTP 200
>>> GET billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/9109fcfc-fe1e-44f0-a24c-b8aeb7e19949 (expect 404)
<<< HTTP 404
===== h2-spendcap-unbilled (spendcap, projects/<other-project-4>) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-h2-spendcap-unbilled-1793211097","budgetFilter":{"projects":["projects/<other-project-4>"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"spendCap":{"inputState":"CONFIGURED"}}
<<< HTTP 400
{"error":{"code":400,"message":"Request contains an invalid argument.","status":"INVALID_ARGUMENT"}}
===== h3-regular-unbilled (regular, projects/<other-project-4>) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-h3-regular-unbilled-1793211098","budgetFilter":{"projects":["projects/<other-project-4>"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true}}
<<< HTTP 400
{"error":{"code":400,"message":"Request contains an invalid argument.","status":"INVALID_ARGUMENT"}}
===== h2-spendcap-unbilled (spendcap, projects/<other-project-3>) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-h2-spendcap-unbilled-1793211098","budgetFilter":{"projects":["projects/<other-project-3>"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"spendCap":{"inputState":"CONFIGURED"}}
<<< HTTP 400
{"error":{"code":400,"message":"Request contains an invalid argument.","status":"INVALID_ARGUMENT"}}
===== h3-regular-unbilled (regular, projects/<other-project-3>) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-h3-regular-unbilled-1793211099","budgetFilter":{"projects":["projects/<other-project-3>"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true}}
<<< HTTP 400
{"error":{"code":400,"message":"Request contains an invalid argument.","status":"INVALID_ARGUMENT"}}
===== h2-spendcap-unbilled (spendcap, projects/<other-project-5>) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-h2-spendcap-unbilled-1793211099","budgetFilter":{"projects":["projects/<other-project-5>"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"spendCap":{"inputState":"CONFIGURED"}}
<<< HTTP 400
{"error":{"code":400,"message":"Request contains an invalid argument.","status":"INVALID_ARGUMENT"}}
===== h3-regular-unbilled (regular, projects/<other-project-5>) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-h3-regular-unbilled-1793211100","budgetFilter":{"projects":["projects/<other-project-5>"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true}}
<<< HTTP 400
{"error":{"code":400,"message":"Request contains an invalid argument.","status":"INVALID_ARGUMENT"}}
===== ctl-spendcap-billed-invisible (spendcap, projects/<other-project-1>) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-ctl-spendcap-billed-invisible-1793211100","budgetFilter":{"projects":["projects/<other-project-1>"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"spendCap":{"inputState":"CONFIGURED"}}
<<< HTTP 200
{"name":"billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/29a8503f-0247-4349-b56b-3be221f1d16e","displayName":"h2-ctl-spendcap-billed-invisible-1793211100","budgetFilter":{"projects":["projects/<other-project-1-number>"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"etag":"1793211101141271","spendCap":{"outputState":"CONFIGURED"}}
>>> DELETE billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/29a8503f-0247-4349-b56b-3be221f1d16e
<<< HTTP 200
>>> GET billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/29a8503f-0247-4349-b56b-3be221f1d16e (expect 404)
<<< HTTP 404
===== ctl-regular-billed-invisible (regular, projects/<other-project-1>) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-ctl-regular-billed-invisible-1793211101","budgetFilter":{"projects":["projects/<other-project-1>"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true}}
<<< HTTP 200
{"name":"billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/daa95f3f-d286-4bea-9bc1-93f8e7f5e77d","displayName":"h2-ctl-regular-billed-invisible-1793211101","budgetFilter":{"projects":["projects/<other-project-1-number>"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"etag":"1793211102563585"}
>>> DELETE billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/daa95f3f-d286-4bea-9bc1-93f8e7f5e77d
<<< HTTP 200
>>> GET billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/daa95f3f-d286-4bea-9bc1-93f8e7f5e77d (expect 404)
<<< HTTP 404
===== ctl-spendcap-billed-invisible (spendcap, projects/<other-project-2>) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-ctl-spendcap-billed-invisible-1793211103","budgetFilter":{"projects":["projects/<other-project-2>"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"spendCap":{"inputState":"CONFIGURED"}}
<<< HTTP 200
{"name":"billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/aa168550-0b32-4a20-87f2-e18d47dd63a5","displayName":"h2-ctl-spendcap-billed-invisible-1793211103","budgetFilter":{"projects":["projects/<other-project-2-number>"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"etag":"1793211104631386","spendCap":{"outputState":"CONFIGURED"}}
>>> DELETE billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/aa168550-0b32-4a20-87f2-e18d47dd63a5
<<< HTTP 200
>>> GET billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/aa168550-0b32-4a20-87f2-e18d47dd63a5 (expect 404)
<<< HTTP 404
===== ctl-regular-billed-invisible (regular, projects/<other-project-2>) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-ctl-regular-billed-invisible-1793211105","budgetFilter":{"projects":["projects/<other-project-2>"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true}}
<<< HTTP 200
{"name":"billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/c87eb385-39dc-4492-87d3-ec5bc501aac1","displayName":"h2-ctl-regular-billed-invisible-1793211105","budgetFilter":{"projects":["projects/<other-project-2-number>"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"etag":"1793211106063730"}
>>> DELETE billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/c87eb385-39dc-4492-87d3-ec5bc501aac1
<<< HTTP 200
>>> GET billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/c87eb385-39dc-4492-87d3-ec5bc501aac1 (expect 404)
<<< HTTP 404
===== ctl-spendcap-nonexistent (spendcap, projects/does-not-exist-zz-1793211106) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-ctl-spendcap-nonexistent-1793211106","budgetFilter":{"projects":["projects/does-not-exist-zz-1793211106"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"spendCap":{"inputState":"CONFIGURED"}}
<<< HTTP 200
{"name":"billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/d84720d4-432d-4ef1-9eb0-6f9c3af4d501","displayName":"h2-ctl-spendcap-nonexistent-1793211106","budgetFilter":{"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"etag":"1793211107396958","spendCap":{"outputState":"CONFIGURED"}}
>>> DELETE billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/d84720d4-432d-4ef1-9eb0-6f9c3af4d501
<<< HTTP 200
>>> GET billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/d84720d4-432d-4ef1-9eb0-6f9c3af4d501 (expect 404)
<<< HTTP 404
===== ctl-regular-nonexistent (regular, projects/does-not-exist-zz-1793211108) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-ctl-regular-nonexistent-1793211108","budgetFilter":{"projects":["projects/does-not-exist-zz-1793211108"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true}}
<<< HTTP 200
{"name":"billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/c160d840-32f6-4223-af4e-748f25bd5fdf","displayName":"h2-ctl-regular-nonexistent-1793211108","budgetFilter":{"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"etag":"1793211108573455"}
>>> DELETE billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/c160d840-32f6-4223-af4e-748f25bd5fdf
<<< HTTP 200
>>> GET billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/c160d840-32f6-4223-af4e-748f25bd5fdf (expect 404)
<<< HTTP 404
===== ctl-spendcap-random-number (spendcap, projects/123456789012) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-ctl-spendcap-random-number-1793211135","budgetFilter":{"projects":["projects/123456789012"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"spendCap":{"inputState":"CONFIGURED"}}
<<< HTTP 200
{"name":"billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/0ee6ef70-0e86-4dc3-a861-24eb367ac71f","displayName":"h2-ctl-spendcap-random-number-1793211135","budgetFilter":{"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"etag":"1793211136125154","spendCap":{"outputState":"CONFIGURED"}}
>>> DELETE billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/0ee6ef70-0e86-4dc3-a861-24eb367ac71f
<<< HTTP 200
>>> GET billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/0ee6ef70-0e86-4dc3-a861-24eb367ac71f (expect 404)
<<< HTTP 404
===== ctl-regular-random-number (regular, projects/123456789012) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-ctl-regular-random-number-1793211137","budgetFilter":{"projects":["projects/123456789012"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true}}
<<< HTTP 200
{"name":"billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/e3434823-319b-44a9-81e4-f3444d75bb8f","displayName":"h2-ctl-regular-random-number-1793211137","budgetFilter":{"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"PLN","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true},"etag":"1793211137826287"}
>>> DELETE billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/e3434823-319b-44a9-81e4-f3444d75bb8f
<<< HTTP 200
>>> GET billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets/e3434823-319b-44a9-81e4-f3444d75bb8f (expect 404)
<<< HTTP 404
===== ctl-regular-usd-billed (regular, projects/${GOOGLE_PROJECT_NUMBER}) =====
>>> POST https://billingbudgets.googleapis.com/v1/billingAccounts/${GOOGLE_BILLING_ACCOUNT}/budgets
>>> body: {"displayName":"h2-ctl-regular-usd-billed-1793211161","budgetFilter":{"projects":["projects/${GOOGLE_PROJECT_NUMBER}"],"services":["services/C7E2-9256-1C43"],"creditTypesTreatment":"EXCLUDE_ALL_CREDITS","calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"USD","units":"5"}},"thresholdRules":[{"thresholdPercent":0.5,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":0.8,"spendBasis":"CURRENT_SPEND"},{"thresholdPercent":1.0,"spendBasis":"CURRENT_SPEND"}],"notificationsRule":{"enableProjectLevelRecipients":true}}
<<< HTTP 400
{"error":{"code":400,"message":"Request contains an invalid argument.","status":"INVALID_ARGUMENT"}}
```

</details>

## 4. How upstream CI wires the billing accounts and projects

- `mmv1/products/billingbudgets/Budget.yaml`: **every** budget sample (basic, lastperiod, filter, notify,
  notify_project_recipient, customperiod, spend_cap, optional) uses `billing_acct: MASTER_BILLING_ACCT`.
  Handwritten `resource_billing_budget_test.go` also uses `GetTestMasterBillingAccountFromEnv`.
- Samples that filter by project: customperiod, filter, lastperiod, notify, notify_project_recipient, spend_cap. All of
  them use `data "google_project" "project" {}` (that is, `GOOGLE_PROJECT`) and `projects/${...number}`, and none
  creates its own project. basic and optional have no project filter.
- Currency: basic, customperiod, filter, notify, notify_project_recipient, optional and spend_cap hard-code
  `currency_code = "USD"`. lastperiod and the handwritten Currencycode test omit it.
- `mmv1/third_party/terraform/envvar/envvar_utils.go`:
  - `GOOGLE_BILLING_ACCOUNT` (`BILLING_ACCT`) is "the billing account that will be charged for the infrastructure used
    during testing ... also the billing account used for creating new projects".
  - `GOOGLE_MASTER_BILLING_ACCOUNT` (`MASTER_BILLING_ACCT`) is "the billing account that will be modified to test
    billing-related functionality ... expected to have more permissions granted to the test user and support
    subaccounts".
  - Neither is tied to `GOOGLE_PROJECT` in code. Nothing in `acctest` links `GOOGLE_PROJECT` to MASTER, and nothing
    guarantees that MASTER bills it.
- No existing sample under `mmv1/templates/terraform/samples` creates a `google_project` and then budgets on it; the
  only files that mention `google_billing_budget` are the billingbudgets samples and tests. The project-creation
  pattern itself is common: 118 sample templates create `resource "google_project"` with `billing_account`. For example,
  `identityplatform/identity_platform_config_minimal.tf.tmpl` uses `org_id: ORG_ID`, `billing_acct: BILLING_ACCT` and
  `deletion_policy = "DELETE"`.

What this implies for the upstream 400, given the results above:
- Existing project-filtered USD samples on MASTER presumably pass in CI. A currency mismatch or a project billed
  elsewhere (in ID form) fails for *regular* budgets too, so either MASTER is billed in USD and resolves
  `GOOGLE_PROJECT`, or project numbers billed elsewhere are dropped silently (untested caveat above).
- In the first case, neither H4 nor H2 (as tested) explains a 400 that only the spend-cap sample hits. The remaining
  candidates are:
  - H3: MASTER is a parent/subaccount-capable (reseller-style) account, and the docs exclude those from spend caps.
  - The spend-cap-specific check that the single project is billed by this account, in case project numbers billed
    elsewhere are dropped for regular budgets but still checked for spend caps.
- Both point to the same fix: do not run the spend-cap sample on MASTER against `GOOGLE_PROJECT`.

**Could the sample create its own project linked to `BILLING_ACCT` and filter on it?** Yes. This is a well-trodden
pattern (`google_project` + `org_id = ORG_ID` + `billing_account = BILLING_ACCT` + `deletion_policy = "DELETE"`), and
`BILLING_ACCT` is by definition the account that new test projects are billed to. It is the robust fix. It guarantees
that the project in the filter is billed by the budget's account. It also keeps the cap away from the shared
`GOOGLE_PROJECT`; at 100 USD the cap is unlikely to enforce, but if it did, it would pause a service CI depends on.

Open policy question for maintainers: `BILLING_ACCT` is described as the account that pays for testing, while MASTER
is the one meant to be modified by billing tests. Creating budgets on `BILLING_ACCT` therefore goes against that
convention, even though budgets are harmless metadata. It has to be first-party for spend caps; that is not verifiable
from here.

## 5. Recommended concrete fix for the sample

```hcl
data "google_billing_account" "account" {
  billing_account = "{{index $.TestEnvVars "billing_acct"}}"   # billing_acct: BILLING_ACCT (not MASTER_BILLING_ACCT)
}

resource "google_project" "project" {
  project_id      = "{{index $.ResourceIdVars "project_id"}}"  # e.g. tf-test-spendcap + suffix
  name            = "{{index $.ResourceIdVars "project_id"}}"
  org_id          = "{{index $.TestEnvVars "org_id"}}"         # org_id: ORG_ID
  billing_account = "{{index $.TestEnvVars "billing_acct"}}"
  deletion_policy = "DELETE"
}

resource "google_billing_budget" "{{$.PrimaryResourceId}}" {
  billing_account = data.google_billing_account.account.id
  display_name    = "{{index $.ResourceIdVars "display_name"}}"

  budget_filter {
    projects               = ["projects/${google_project.project.number}"]
    services               = ["services/C7E2-9256-1C43"]
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
    calendar_period        = "MONTH"
  }

  amount {
    specified_amount {
      units = "100"   # no currency_code: optional, defaults to the account currency; a mismatch is a bare 400
    }
  }
  # threshold_rules / all_updates_rule / spend_cap unchanged
}
```

In `Budget.yaml`, set `test_env_vars: { billing_acct: BILLING_ACCT, org_id: ORG_ID }` and add a `project_id`
resource-id var. Points to check when implementing:
- The billing link on a new project can take a moment to propagate. The budget already depends on the project implicitly
  through `.number`. If the budget create races the billing link, add a short `time_sleep`.
- Omitting `currency_code` relies on `amount.specified_amount.currency_code` being optional/computed. The handwritten
  `TestAccBillingBudget_billingBudgetCurrencycode` already omits it, so this is supported.
- An alternative with no new project is `BILLING_ACCT` plus `data "google_project"`. It depends on `GOOGLE_PROJECT`
  being billed by `BILLING_ACCT`, which nothing in the code guarantees. It also puts a cap on the shared CI project.

## 6. Recommended fixes in the resource (in addition to the sample)

1. **`spend_cap.input_state` permadiff (new, confirmed by the PLN run).** Add a `custom_flatten` for
   `spendCap.inputState` that:
   - uses the API value if one is ever returned;
   - otherwise keeps the configured value (`d.Get("spend_cap.0.input_state")`);
   - on import (nothing in state), derives the value from `outputState`: `AWAITING_NEXT_PERIOD` maps to
     `AWAITING_NEXT_PERIOD`, and anything else maps to `CONFIGURED`.

   This keeps import verification meaningful. The simpler `ignore_read: true` would also need
   `ignore_read_extra: [spend_cap.0.input_state]` with a comment saying that the API never returns `inputState`.
2. **Update mask (confirmed in probe-findings.md).** Whenever `spend_cap` is set, always include `spendCap.inputState`
   in the PATCH update mask, not only on `d.HasChange("spend_cap")`. Use a custom `pre_update` that appends it to
   `updateMask` and makes sure `spendCap.inputState` is in the body. Otherwise any in-place change to another field of
   a spend-cap budget (for example `amount`) fails with the bare 400.
3. Optional:
   - Do not send output-only `spendCap.outputState` on PATCH.
   - Consider a plan-time validation that `budget_filter.projects` has exactly one entry when `spend_cap` is set,
     because the API silently drops unresolvable projects and then still creates the cap with no project filter.
