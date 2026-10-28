#!/usr/bin/env bash
# Probe the Billing Budgets spend cap API to test the hypotheses in report.md.
# Usage: set -a; . <parent>/.env; set +a; ./probe.sh
#   Required: GOOGLE_BILLING_ACCOUNT, GOOGLE_PROJECT (see .env.example).
#   Optional: GOOGLE_PROJECT_NUMBER (looked up with gcloud when unset).
# Note: the bodies use currency USD; on a billing account in another currency every create returns a bare 400.
# WARNING: successful probes create real budgets; step (f) deletes them.
set -euo pipefail

: "${GOOGLE_BILLING_ACCOUNT:?GOOGLE_BILLING_ACCOUNT is not set (billing account ID, see .env.example)}"
: "${GOOGLE_PROJECT:?GOOGLE_PROJECT is not set (project ID billed by GOOGLE_BILLING_ACCOUNT, see .env.example)}"
BILLING_ACCOUNT_ID="$GOOGLE_BILLING_ACCOUNT"
PROJECT_ID="$GOOGLE_PROJECT"

TOKEN="$(gcloud auth print-access-token)"
API="https://billingbudgets.googleapis.com/v1"
PROJECT_NUMBER="${GOOGLE_PROJECT_NUMBER:-$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')}"
CREATED=()

label() { printf '\n===== %s =====\n' "$1"; }

# build_body DISPLAY_NAME SERVICE_ID WITH_SCHEMA_VERSION(true|false)
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
  "amount": {"specifiedAmount": {"currencyCode": "USD", "units": "100"}},
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

# create_budget DISPLAY_NAME SERVICE_ID WITH_SCHEMA_VERSION
create_budget() {
  local out name
  out="$(curl -sS -X POST "$API/billingAccounts/$BILLING_ACCOUNT_ID/budgets" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-Goog-User-Project: $PROJECT_ID" \
    -H "Content-Type: application/json" \
    -d "$(build_body "$1" "$2" "$3")" || true)"
  echo "$out"
  name="$(printf '%s' "$out" | sed -n 's/^ *"name": *"\(billingAccounts\/[^"]*\)".*/\1/p' | head -n1)"
  if [ -n "$name" ]; then CREATED+=("$name"); fi
}

label "(a) billing account of project $PROJECT_ID"
gcloud billing projects describe "$PROJECT_ID" --format='value(billingAccountName)' || echo "probe (a) failed"

label "(b) subaccounts of billingAccounts/$BILLING_ACCOUNT_ID (any output = reseller-style parent)"
gcloud billing accounts list --filter="masterBillingAccount=billingAccounts/$BILLING_ACCOUNT_ID" || echo "probe (b) failed"

label "(c) create WITHOUT schemaVersion (documented body), service C7E2-9256-1C43"
create_budget "probe-no-schemaversion" "C7E2-9256-1C43" false || echo "probe (c) failed"

# Delete anything created so far so the dedupe policy does not mask the next probe.
cleanup() {
  local n
  if [ "${#CREATED[@]}" -eq 0 ]; then echo "nothing to delete"; return 0; fi
  for n in "${CREATED[@]}"; do
    echo "deleting $n"
    curl -sS -X DELETE "$API/$n" \
      -H "Authorization: Bearer $TOKEN" \
      -H "X-Goog-User-Project: $PROJECT_ID" \
      -H "Content-Type: application/json" || echo "delete of $n failed"
    echo
  done
  CREATED=()
}

label "cleanup after (c), so (d) is not rejected as a duplicate"
DELETED_LOG=()
if [ "${#CREATED[@]}" -gt 0 ]; then DELETED_LOG+=("${CREATED[@]}"); fi
cleanup || true

label "(d) create WITH schemaVersion 1.0 (provider-shaped body), service C7E2-9256-1C43"
create_budget "probe-with-schemaversion" "C7E2-9256-1C43" true || echo "probe (d) failed"
if [ "${#CREATED[@]}" -gt 0 ]; then DELETED_LOG+=("${CREATED[@]}"); fi
cleanup || true

label "(e) create WITHOUT schemaVersion, service AEFD-7695-64FA (Gemini API)"
create_budget "probe-no-schemaversion" "AEFD-7695-64FA" false || echo "probe (e) failed"

label "(f) delete budgets created by (c)/(d)/(e)"
if [ "${#CREATED[@]}" -gt 0 ]; then DELETED_LOG+=("${CREATED[@]}"); fi
cleanup || true
echo "budgets created and deleted by this run:"
if [ "${#DELETED_LOG[@]}" -eq 0 ]; then echo "  (none)"; else printf '  %s\n' "${DELETED_LOG[@]}"; fi
