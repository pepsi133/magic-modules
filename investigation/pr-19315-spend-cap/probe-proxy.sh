#!/usr/bin/env bash
# Probe the Billing Budgets spend cap API to test the hypotheses in report.md (H1-H6).
# Variant of probe.sh for an environment where an egress proxy injects the Authorization header:
# no Authorization header and no gcloud token are used here.
# Usage: set -a; . <parent>/.env; set +a; bash probe-proxy.sh
#   Required: GOOGLE_BILLING_ACCOUNT, GOOGLE_PROJECT, GOOGLE_PROJECT_NUMBER (see .env.example).
#   Optional: SPEND_CAP_CURRENCY (default PLN; must match the billing account's currency).
# WARNING: successful probes create real spend-cap budgets (5 units); every one is deleted right after its probe.
set -uo pipefail

: "${GOOGLE_BILLING_ACCOUNT:?GOOGLE_BILLING_ACCOUNT is not set (billing account ID, see .env.example)}"
: "${GOOGLE_PROJECT:?GOOGLE_PROJECT is not set (project ID billed by GOOGLE_BILLING_ACCOUNT, see .env.example)}"
: "${GOOGLE_PROJECT_NUMBER:?GOOGLE_PROJECT_NUMBER is not set (number of GOOGLE_PROJECT, see .env.example)}"

BILLING_ACCOUNT_ID="$GOOGLE_BILLING_ACCOUNT"
PROJECT_ID="$GOOGLE_PROJECT"
PROJECT_NUMBER="$GOOGLE_PROJECT_NUMBER"
CURRENCY="${SPEND_CAP_CURRENCY:-PLN}"
UNITS="5"
API="https://billingbudgets.googleapis.com/v1"
BUDGETS="$API/billingAccounts/$BILLING_ACCOUNT_ID/budgets"
SUFFIX="$(date +%s)"
CREATED_LOG=()
LEFTOVER=()

label() { printf '\n===== %s =====\n' "$1"; }

# req METHOD URL [BODY]: prints the request, HTTP status and full response body; response body saved in $RESP.
req() {
  local method="$1" url="$2" body="${3:-}" tmp code
  tmp="$(mktemp)"
  echo ">>> $method $url"
  if [ -n "$body" ]; then
    echo ">>> body:"; printf '%s\n' "$body" | jq . 2>/dev/null || printf '%s\n' "$body"
    code="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" "$url" \
      -H "X-Goog-User-Project: $PROJECT_ID" -H "Content-Type: application/json" -d "$body" || echo "curl-failed")"
  else
    code="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" "$url" \
      -H "X-Goog-User-Project: $PROJECT_ID" -H "Content-Type: application/json" || echo "curl-failed")"
  fi
  RESP="$(cat "$tmp")"; rm -f "$tmp"
  HTTP_CODE="$code"
  echo "<<< HTTP $code"
  printf '%s\n' "$RESP" | jq . 2>/dev/null || printf '%s\n' "$RESP"
}

# build_body DISPLAY_NAME SERVICE_ID WITH_SCHEMA_VERSION(true|false) CURRENCY
build_body() {
  local schema=""
  if [ "$3" = "true" ]; then schema='"schemaVersion": "1.0", '; fi
  cat <<JSON
{
  "displayName": "$1",
  "budgetFilter": {
    "projects": ["projects/$PROJECT_NUMBER"],
    "services": ["services/$2"],
    "creditTypesTreatment": "EXCLUDE_ALL_CREDITS",
    "calendarPeriod": "MONTH"
  },
  "amount": {"specifiedAmount": {"currencyCode": "$4", "units": "$UNITS"}},
  "thresholdRules": [
    {"thresholdPercent": 0.5, "spendBasis": "CURRENT_SPEND"},
    {"thresholdPercent": 0.8, "spendBasis": "CURRENT_SPEND"},
    {"thresholdPercent": 1.0, "spendBasis": "CURRENT_SPEND"}
  ],
  "notificationsRule": {${schema}"enableProjectLevelRecipients": true},
  "spendCap": {"inputState": "CONFIGURED"}
}
JSON
}

# Body the Terraform provider sends for the PR sample (report.md section 3), except currency/amount:
# PLN/5 instead of USD/100 because this account is billed in PLN (USD is tested separately in (h)).
build_provider_body() {
  cat <<JSON
{
  "displayName": "Example Spend Cap Budget$SUFFIX",
  "budgetFilter": {
    "projects": ["projects/$PROJECT_NUMBER"],
    "creditTypesTreatment": "EXCLUDE_ALL_CREDITS",
    "services": ["services/C7E2-9256-1C43"],
    "calendarPeriod": "MONTH"
  },
  "amount": {"specifiedAmount": {"currencyCode": "$CURRENCY", "units": "$UNITS"}},
  "thresholdRules": [
    {"thresholdPercent": 0.5, "spendBasis": "CURRENT_SPEND"},
    {"thresholdPercent": 0.8, "spendBasis": "CURRENT_SPEND"},
    {"thresholdPercent": 1.0, "spendBasis": "CURRENT_SPEND"}
  ],
  "notificationsRule": {"schemaVersion": "1.0", "enableProjectLevelRecipients": true},
  "spendCap": {"inputState": "CONFIGURED"}
}
JSON
}

# delete_budget NAME: delete, retry once on failure, confirm with GET.
delete_budget() {
  local n="$1"
  req DELETE "$API/$n"
  if [ "$HTTP_CODE" != "200" ]; then
    echo "delete of $n failed (HTTP $HTTP_CODE), retrying once in 5s"
    sleep 5
    req DELETE "$API/$n"
  fi
  if [ "$HTTP_CODE" != "200" ]; then
    echo "!!! LEFTOVER: delete of $n failed twice"
    LEFTOVER+=("$n")
  fi
  echo "--- confirm deletion of $n (expect 404)"
  req GET "$API/$n"
}

# create_probe LABEL BODY [after_create_hook]: create; on success GET once, run hook, delete.
create_probe() {
  local name
  req POST "$BUDGETS" "$2"
  name="$(printf '%s' "$RESP" | jq -r '.name // empty' 2>/dev/null)"
  if [ -n "$name" ]; then
    echo "### $1: CREATED $name"
    CREATED_LOG+=("$name")
    echo "--- GET once after create (record spendCap.outputState / reconciling)"
    req GET "$API/$name"
    echo "spendCap on GET: $(printf '%s' "$RESP" | jq -c '.spendCap' 2>/dev/null)"
    if [ -n "${3:-}" ]; then "$3" "$name"; fi
    delete_budget "$name"
  else
    echo "### $1: NOT CREATED (HTTP $HTTP_CODE)"
  fi
}

# Task 3: update behaviour, run only on the (c) budget.
update_probes() {
  local n="$1"
  label "(c-u1) PATCH updateMask=amount only, amount 6 $CURRENCY (does the API demand spendCap.inputState in the mask?)"
  req PATCH "$API/$n?updateMask=amount" \
    "{\"amount\": {\"specifiedAmount\": {\"currencyCode\": \"$CURRENCY\", \"units\": \"6\"}}}"
  label "(c-u2) PATCH updateMask=spendCap.inputState, inputState AWAITING_NEXT_PERIOD"
  req PATCH "$API/$n?updateMask=spendCap.inputState" \
    '{"spendCap": {"inputState": "AWAITING_NEXT_PERIOD"}}'
  echo "--- GET after updates"
  req GET "$API/$n"
  echo "amount/spendCap after updates: $(printf '%s' "$RESP" | jq -c '{amount, spendCap}' 2>/dev/null)"
  label "cleanup of (c)"
}

label "(a) billing info of project $PROJECT_ID (H2)"
req GET "https://cloudbilling.googleapis.com/v1/projects/$PROJECT_ID/billingInfo"

label "(a2) billing account $BILLING_ACCOUNT_ID (H3 masterBillingAccount, H4 currencyCode)"
req GET "https://cloudbilling.googleapis.com/v1/billingAccounts/$BILLING_ACCOUNT_ID"

label "(b) subaccounts of billingAccounts/$BILLING_ACCOUNT_ID (non-empty = reseller-style parent, H3)"
req GET "https://cloudbilling.googleapis.com/v1/billingAccounts/$BILLING_ACCOUNT_ID/subAccounts"

label "(b2) eligible service APIs on project $PROJECT_NUMBER (H5)"
for s in aiplatform.googleapis.com generativelanguage.googleapis.com; do
  echo "$s: $(curl -sS "https://serviceusage.googleapis.com/v1/projects/$PROJECT_NUMBER/services/$s" \
    -H "X-Goog-User-Project: $PROJECT_ID" | jq -r '.state // .error.message')"
done

label "(b3) existing budgets before probes (H6)"
req GET "$BUDGETS"

label "(c) create WITHOUT schemaVersion (documented body), service C7E2-9256-1C43, $CURRENCY"
create_probe "(c)" "$(build_body "probe-c-no-schemaversion-$SUFFIX" "C7E2-9256-1C43" false "$CURRENCY")" update_probes

label "(d) create WITH notificationsRule.schemaVersion 1.0, service C7E2-9256-1C43, $CURRENCY"
create_probe "(d)" "$(build_body "probe-d-with-schemaversion-$SUFFIX" "C7E2-9256-1C43" true "$CURRENCY")"

label "(e) create WITHOUT schemaVersion, service AEFD-7695-64FA (Gemini API), $CURRENCY"
create_probe "(e)" "$(build_body "probe-e-gemini-api-$SUFFIX" "AEFD-7695-64FA" false "$CURRENCY")"

label "(g) create with provider-shaped body for the PR sample (schemaVersion 1.0), $CURRENCY"
create_probe "(g)" "$(build_provider_body)"

label "(h) body (c) but currencyCode USD (H4)"
create_probe "(h)" "$(build_body "probe-h-usd-$SUFFIX" "C7E2-9256-1C43" false "USD")"

label "final: list budgets (expect no probe budget)"
req GET "$BUDGETS"
remaining="$(printf '%s' "$RESP" | jq -r '.budgets[]? | select((.displayName // "") | test("^probe-|^Example Spend Cap Budget")) | .name' 2>/dev/null)"
if [ -n "$remaining" ]; then echo "!!! probe budgets still present:"; echo "$remaining"; else echo "no probe budget remains"; fi

echo
echo "budgets created by this run:"
if [ "${#CREATED_LOG[@]}" -eq 0 ]; then echo "  (none)"; else printf '  %s\n' "${CREATED_LOG[@]}"; fi
echo "leftover budgets (delete failed twice):"
if [ "${#LEFTOVER[@]}" -eq 0 ]; then echo "  (none)"; else printf '  %s\n' "${LEFTOVER[@]}"; fi
