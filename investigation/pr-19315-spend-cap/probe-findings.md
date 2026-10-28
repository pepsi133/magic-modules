# Spend-cap API probe findings (2026-10-28)

The raw output is in `probe-results-2026-10-28.txt`. It was produced by `probe-proxy.sh` plus one supplemental control
run, which is recorded at the end of that file.

## Setup

- Target: the test billing account ("My Billing Account").
  - `masterBillingAccount: ""` and no subaccounts, so this is a first-party, non-reseller account.
  - Parent is `organizations/${GOOGLE_ORG}`.
  - `currencyCode: PLN`.
- Budget scope: project `${GOOGLE_PROJECT}` (number `${GOOGLE_PROJECT_NUMBER}`). This project is billed by that same account.
  - `aiplatform.googleapis.com` and `generativelanguage.googleapis.com` are both **DISABLED** on the project.
- The account had no budgets before the run and none after it. Five spend-cap budgets were created; each was deleted
  right after its probe, and a GET confirmed it was gone (404).
- Every 400 from the API was the generic body below, **with no `details` array** (no `ErrorInfo`, no `BadRequest.fieldViolations`):

```json
{
  "error": {
    "code": 400,
    "message": "Request contains an invalid argument.",
    "status": "INVALID_ARGUMENT"
  }
}
```

## Probe results

| Probe | Body | Result |
|---|---|---|
| (c) | Body from the guide, no `schemaVersion`, C7E2-9256-1C43, PLN 5 | **200** created, `spendCap: {"outputState":"CONFIGURED"}` (no `reconciling` field returned) |
| (c-u1) | PATCH `updateMask=amount`, amount PLN 6 | **400** (generic body above), amount unchanged |
| (c-u2) | PATCH `updateMask=spendCap.inputState`, `AWAITING_NEXT_PERIOD` while `outputState=CONFIGURED` | **400** (generic body above) |
| (c2) control | PATCH `updateMask=amount,spendCap.inputState` (inputState CONFIGURED), amount PLN 6 | **200**, amount became 6 |
| (c2) control | PATCH `updateMask=amount.specifiedAmount,spendCap.inputState`, amount PLN 7 | **200**, amount became 7 |
| (d) | (c) + `notificationsRule.schemaVersion: "1.0"` | **200** created. The response leaves out `schemaVersion` (`notificationsRule: {"enableProjectLevelRecipients": true}`) |
| (e) | (c) with service AEFD-7695-64FA (Gemini API) | **200** created, outputState CONFIGURED |
| (g) | Body the provider sends for the PR sample (report.md section 3: displayName `Example Spend Cap Budget<suffix>`, `schemaVersion "1.0"`, spendBasis, `enableProjectLevelRecipients`, inputState CONFIGURED) with **PLN 5 instead of USD 100** | **200** created, outputState CONFIGURED |
| (h) | (c) with `currencyCode: "USD"` | **400** (generic body above) |

## Hypotheses

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| H1 | `notificationsRule.schemaVersion: "1.0"` is rejected for spend caps | **Refuted** | (d) and (g) both return 200 with `schemaVersion: "1.0"`. The API accepts the field and silently drops it from the stored budget. |
| H2 | The project is not billed by the budget's billing account | **Untested (negative case)** | Here the project *is* billed by the account, and create succeeds. A budget scoped to a project billed by a different account was not tried, because only one project and one account were available. |
| H3 | The billing account is not eligible (reseller/parent or not first-party) | **Untested (negative case)** | This account is first-party with no subaccounts and is eligible: (c), (d), (e), (g) succeed. No reseller or parent account was available to try. |
| H4 | Currency mismatch | **Confirmed** | (h), which is identical to the successful (c) except for `currencyCode: "USD"` on a PLN account, fails with `400 "Request contains an invalid argument." INVALID_ARGUMENT`. This is the same generic error the upstream test reports. |
| H5 | Wrong service ID / service API not enabled | **Refuted** | Both C7E2-9256-1C43 (c, d, g) and AEFD-7695-64FA (e) are accepted. Creation also succeeds while the corresponding APIs are DISABLED on the project. |
| H6 | A duplicate budget with the same scope exists | **Untested** | The account had no budgets before the run, and every probe deleted its budget before the next one ran. A deliberate duplicate was not tried. |

Update-path findings, which are part of the resource design and not the create 400:
- **Confirmed:** once a budget is a spend cap, an update mask without `spendCap.inputState` is rejected.
  - (c-u1) `updateMask=amount` → generic 400.
  - The same change with `updateMask=amount,spendCap.inputState` → 200.
- **Confirmed:** you cannot set `AWAITING_NEXT_PERIOD` on a cap that is not enforced. (c-u2) → generic 400, which matches
  the Discovery text ("valid only when updating ... to explicitly lift an enforced cap").
- On GET, the API returns `spendCap.outputState` but not `inputState` or `reconciling` (when false).

## Conclusion: what the upstream test most likely hits

The provider-shaped body (g) is accepted, so the PR's request shape is valid. That rules out `schemaVersion` (H1), the
service ID (H5), and output-only fields. The upstream 400 is therefore environmental. In order of likelihood:

1. **H4 (currency).** If `GOOGLE_MASTER_BILLING_ACCOUNT` is not billed in USD, the hard-coded `currency_code = "USD"`
   produces exactly this generic 400. Other budget samples on MASTER use USD and pass, but those are not spend caps; the
   docs apply the currency-match rule specifically to spend caps. Probe (h) shows that rule is enforced with the same
   generic error. A maintainer should run `gcloud billing accounts describe $GOOGLE_MASTER_BILLING_ACCOUNT --format='value(currencyCode)'`.
2. **H2/H3 (account/project eligibility).** These could not be tested here. MASTER is the CI account with subaccounts
   (reseller-style), and `GOOGLE_PROJECT` is probably billed by `GOOGLE_BILLING_ACCOUNT` rather than MASTER. Either
   condition could also produce the same detail-less 400; the API returns no field violations that would tell them apart.

## Code changes the PR needs (not made here; nothing under `mmv1/` was changed)

1. **Sample/test:**
   - Remove the hard-coded currency, or make it match the CI account. Option: omit `currency_code`; the docs say it is
     optional and must match if given.
   - Point the sample at a billing account that is first-party and actually bills the scoped project. For example, use
     `BILLING_ACCT` with `GOOGLE_PROJECT` instead of `MASTER_BILLING_ACCT`, or create a project in the test that is linked
     to the account used.
2. **Update mask (required):** always append `spendCap.inputState` to the update mask whenever `spend_cap` is set. Use a
   custom `pre_update` / update encoder. The current generated code adds it only on `d.HasChange("spend_cap")`, so any
   in-place change to another field (for example `amount`) on a spend-cap budget will fail with 400.
3. **`schemaVersion`:** no change is needed for create; the API accepts it and leaves it out of the stored budget.
   The existing `default_if_empty` flatten keeps state at `"1.0"`, so no diff is expected.
4. **Optional:**
   - Stop sending output-only `spendCap.outputState` on PATCH.
   - Document that `AWAITING_NEXT_PERIOD` is accepted only while the cap is `ENFORCED`. Setting it in config on a
     non-enforced cap fails with 400.
