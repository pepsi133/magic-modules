# Investigation: upstream PR 19315 (billing budget `spend_cap`)

**Start with [HANDOVER.md](HANDOVER.md).** It has the current status, decisions and next steps. This README is the
original overview; its top hypothesis (H1, `schemaVersion`) was later refuted (see `probe-findings.md`).

This branch is the head of upstream PR
[GoogleCloudPlatform/magic-modules#19315](https://github.com/GoogleCloudPlatform/magic-modules/pull/19315)
(commit `b1edf518`) plus one commit adding these investigation notes. It is a public draft on a fork and is
not meant to be merged. Related issue: [hashicorp/terraform-provider-google#28575](https://github.com/hashicorp/terraform-provider-google/issues/28575).

Files:
- `report.md`: full report on why the recording-mode create call returns 400.
- `probe.sh`: script to test the hypotheses against a real billing account (creates and deletes budgets).

## Top hypothesis (H1)

The generated create request always sends `notificationsRule.schemaVersion: "1.0"`, because
`all_updates_rule.schema_version` has `default_value: "1.0"` in `Budget.yaml`. The Google spend-cap guide says
the only allowed `NotificationsRule` field is `enableProjectLevelRecipients=true` and that all other
`NotificationsRule` parameters are unsupported. The documented create body has no `schemaVersion`.

## Other hypotheses

- H2: the CI project is not billed by `GOOGLE_MASTER_BILLING_ACCOUNT`.
- H3: the billing account is not eligible (reseller/parent account with subaccounts, or not first-party).
- H4: currency mismatch (`USD` versus the account's currency); unlikely.
- H5: the service ID is wrong or the service API is not enabled on the project; unlikely.
- H6: a duplicate budget with the same scope already exists; unlikely.
