# Upstream PR conventions: GoogleCloudPlatform/magic-modules

Sources: local repo (/home/user/magic-modules) and github.com web pages sampled 2026-10-28. Web results were summarised by a fetch tool and are not verbatim; verify anything load-bearing. Write-only change: this file.

## 1. Repo rules (local files)
- docs/content/code-review/create-pr.md: one self-contained change per PR (one new resource per PR; fields and bugfix in separate PRs). PR body must contain `Fixes <issue link>.` once per issue (issues live in hashicorp/terraform-provider-google). Must write release notes. Test locally before pushing; VCR can take up to 2h; community PR tests start only after reviewer approval. Ping reviewer after 2 US business days.
- docs/content/code-review/review-pr.md: reviewers check Fixes vs "Part of", GA/beta superset, breaking changes (`override-breaking-change` label), every new/changed field covered by a test, mutable fields in an update test, `tf-test`/`tf_test` prefix on resource ids, handwritten config steps followed by import steps, bugfix has a test reproducing it "or explain why it's not feasible ... including manual results". Presubmit VCR does NOT run in GA, so GA promotions need manual testing evidence. "Some acceptance tests may be skipped in VCR and manual testing is required."
- docs/content/contribution-process.md: fork, branch, generate providers, run relevant tests locally, open PR.
- .github/workflows/basic-pr-checks.yml (no submodules), changelog-checker.yml (runs tools/go-changelog changelog-pr-body-check on opened/edited/synchronize: fails if the body has no valid release-note block), gofmt.yml, unit-test-*.yml, build-downstream. Downstream generation + VCR run through .ci/gcb-pr-downstream-generation-and-test.yml (Cloud Build) and post a diff/test comment via modular-magician.
- Repo AGENTS.md: work in a worktree based on current upstream/main; push follow-up commits rather than amend/force-push after PR open; PR descriptions brief; never weaken tests (comment any `ignore_read` / `ImportStateVerifyIgnore`).
- No commit-message convention file exists locally. No CODEOWNERS-driven review (CODEOWNERS file exists at root but reviewers are assigned by magician; not inspected in depth).

## 2. PR template (.github/PULL_REQUEST_TEMPLATE.md)
HTML comment (self-review checklist link; "if WIP, create in draft mode"; description + `Fixes https://github.com/hashicorp/terraform-provider-google/issues/ID`), then:

    **Release Note Template for Downstream PRs (will be copied)**
    See [Write release notes](...) for guidance.
    ```release-note:REPLACEME

    ```

Replace REPLACEME. Leaving `REPLACEME` fails the changelog checker (per release-notes.md "Don't leave the type as REPLACEME").

## 3. Release-note syntax (docs/content/code-review/release-notes.md)
- Every PR needs >=1 block, one content line per block, multiple blocks for multiple changes. Append `(beta)`/`(ga)` only if one provider is affected.
- Bug fix: 
  ```release-note:bug
  container: fixed an error and subsequent permadiff when removing the `dns_config` block from `google_container_cluster`
  ```
- Enhancement (new field): 
  ```release-note:enhancement
  firestore: added `search_index_options` field to `google_firestore_index` resource
  ```
- Other types: new-resource, new-datasource, new-list-resource (content is just the backticked name), deprecation, breaking-change, note, `none` (empty body, for test/CI/docs-only).
- Style: past tense, user-focused, product prefix = MMv1 folder name (lowercase after colon), backticks on resource/field names, no "I/you".
- Observed practice: test-fix and docs PRs (#19775, #19777) left the template untouched with an empty/REPLACEME-style block or `none`; #19789 (docs) had no block shown. Treat as maintainers' leniency; contributors should use `release-note:none` explicitly for no-user-impact changes.

## 4. Sample of merged upstream PRs (page of 2026-10-27/28)
| PR | Title | Author | Notes |
|---|---|---|---|
| 19802 | Add PSC connection fields to `google_compute_region_network_endpoint_group` | marcjanek (community) | no "service:" prefix; Fixes issue; enhancement note "compute: added ..."; google-cla initially failed; 1 commit |
| 19794 | tpgiamresource: fix copyright headers in list resources | rileykarson | prefix style |
| 19791/19790 | "Built/Inlined ..." | melinath | past-tense, no prefix |
| 19789 | compute: note INTERNAL_SELF_MANAGED for service_lb_policy | c2thorn | docs, label type/docs, no release note |
| 19788 | compute: add per-router mutex to route policy and named set | SirGitsalot | release-note:bug, Fixes 2 issues, b/ ref |
| 19777 | tpuv2: move TestAccTpuV2Vm_update to ... | rileykarson | test-fix, `Fixes` issue, empty release note |
| 19775 | storagecontrol: fix org findings summary empty test check | rileykarson | test-fix |
| 19774 | container: fix dns_config block removal on cluster | rileykarson | 2 commits, release-note bug |
| 19767 | Add search_index_options field to google_firestore_index | slevenick | enhancement note; force-pushed once |
| 19757 | oracledatabase: add google_oracle_database_odb_dns_zone | NA2047 | 5 commits, all "oracledatabase:" prefix; no release note seen |
| 19755 | sql: promote blue_green_deployment on database_instance | c2thorn | "supersedes #19570"; 2nd commit is a merge of main; GA-only tests flagged for manual verification |
Also 19571 (biglakeiceberg: fix list, map and struct column types, community author Ferdinanddb).

Findings:
- Title: dominant format `product: lowercase description` (matches MMv1 folder / release-note prefix); some descriptive-sentence titles without prefix (19802, 19767, 19791). Labels `service/*`, `type/*`, `size/*` are added automatically by modular-magician; do not add manually.
- Release note block present in nearly all feature/bugfix PRs; test-only/docs PRs often have none or empty.
- Commits: all by individual humans under their own GitHub accounts, single or few commits; PR merged via merge queue (squash). Force-push occurs even in merged PRs (19802, 19767) despite repo AGENTS.md preference for added commits; no one objected.
- Human "Co-authored-by": search `"Co-authored-by"` merged returns 107 PRs but all page-1 results are old (#4400-#16361); zero merged after 2026-07-01. So human trailers exist historically but are rare/old; can't confirm how they interact with CLA.
- AI trailers/disclosure (web search counts, approximate):
  - `"Co-Authored-By: Claude"`: 1 PR, open (#19163, container, by eidam; body ends `Co-Authored-By: Claude Fable 5.1`; reviewer c2thorn requested changes on technical grounds only, nothing about AI).
  - `"Generated with Claude Code"`: 15 PRs: 6 open, 9 closed, of which merged = #19571, #18388, #16637 (3 merged); 6 closed unmerged (several drafts). Open: #19766, #19315, #19293, #19196, #19164, #19148. So AI-assisted PRs are accepted and merged (e.g. #19571 body ends "Generated with Claude Code", approved by melinath); disclosure is in the PR body, not as commit trailers, in the merged cases. No evidence of a policy forbidding it. The repo's own system reminder prescribes trailers; upstream has no documented rule (open question: confirm with maintainers).
- Stacked PRs: no evidence of common stacking. Only 1 open PR has non-main base (#19285). Practice seen: independent PRs; "supersedes #NNNN" in body (19755 -> 19570). Other approach: reference with "Depends on #N" in body (search matched many but could not confirm text).
- Drafts: widely used (135 open draft PRs; template says use draft for WIP). Reviewer assignment (request-reviewer.yml) skips drafts and fires on ready_for_review.

## 5. CLA, signing, co-authors
- Repo-side facts: .github/CONTRIBUTING.md requires individual or corporate Google CLA. No CLA code lives in .ci (the check is the external `google-cla` GitHub App; grep of .ci/magician found nothing CLA-specific). Observed on PRs: google-cla bot comment/check "CLA signature needed" on community PRs 19802, 19571, 19315; maintainers still merged 19802 with that failure shown first (authors later signed; page didn't show final state, 32 checks passed).
- From knowledge (not verifiable from repo, flag as such): google-cla checks the author and committer emails of every commit in the PR (and, per Google's docs, also `Co-authored-by` trailers are NOT used to block; the bot looks at commit author/committer). Email must be linked to the signer's GitHub account / CLA. Mixed authorship: any commit by an unsigned email fails the check. A Co-authored-by trailer with an unsigned email should not block, but unconfirmed. Using a noreply GitHub email is fine if associated with the signed account. A commit made by an AI under the user's git identity is authored by the user; trailers are inert for the check.
- Signed commits: not required by any file in repo or CI; not mentioned in docs. Nice-to-have only; CLA check does not look at signatures.

## 6. Building on an open PR (19315 by DrFaust92)
- Observed state of #19315 (billingbudgets: add spend_cap to google_billing_budget): open, from fork DrFaust92:billingbudget-spend-cap -> main, label service/billingbudgets, "generated with Claude Code" in body, 2 commits, CLA initially failed (author says now green). melinath requested changes (API 400 INVALID_ARGUMENT in recording test; sample may need a spend-cap-eligible billing account). Author offered `exclude_test: true` on the sample.
- Accepted ways (no doc defines this; inferred):
  1. Comment on the PR with findings/suggested diff (cheapest, preferred first step).
  2. PR against the author's fork branch (needs author to merge; CI does not run on forks' internal PRs; no magician support). Slow.
  3. Push to author's branch only if "Allow edits by maintainers" is on and you have write rights; for a non-maintainer contributor this is usually not available.
  4. New upstream PR from your branch that supersedes the old one: note "supersedes #19315" in body (precedent 19755 says "supersedes #19570"), keep original commit authorship (cherry-pick preserves author) so CLA covers both, and optionally Co-authored-by. Needs the original author's CLA coverage for their commits too.
- Base not main: .ci/magician handles it: generate_downstream.go defaults BASE_BRANCH to main; sync branches become `tpg-sync-<base>` etc. (getSyncBranch in wait_for_commit.go); vcr_merge.go puts cassettes under `/refs/branches/<base>/` when base != main (upload path). So non-main bases are supported mainly for feature branches (e.g. major release), not for stacking. Stacking on an unmerged PR branch in your fork is not supported by the downstream pipeline; wait until the parent merges or retarget to main. request-reviewer and CLA are unaffected. Open question: whether VCR replay uses main cassettes for non-main bases (path logic suggests separate branch cassette dir).

## 7. Review assignment and awaiting-approval
- request-reviewer.yml (pull_request_target on opened/ready_for_review/reopened/synchronize and author issue_comment, non-draft only) -> `magician request-reviewer`: if author is not a core contributor/trusted contributor, picks a random core reviewer from `reviewerRotation` in .ci/magician/github/membership_data.go (respects vacations), posts the comment from .ci/magician/github/REVIEWER_ASSIGNMENT_COMMENT.md (2 business day SLA), keeps the same reviewer on later pushes. Copybara PRs -> @melinath; modular-apprentice PRs -> ScottSuarez, slevenick.
- Service label mapping: `request-service-reviewers` (cmd/request_service_reviewers.go) uses `service/*` labels (not service/terraform) -> enrolled teams in tools/issue-labeler (`EnrolledTeamsYaml`) -> a random member of the GitHub team (excl. author); skipped if >3 service labels. `ensure-service-team-labels.yml` keeps labels in sync. This is for Googler/service team review ("Google-driven changes must have a service team engineer review first" - create-pr.md); community not required.
- awaiting-approval: label applied (outside this repo, by the Cloud Build trigger) to PRs from non-trusted authors so tests don't run; a maintainer approves/ comments to start; `.ci/gcb-pr-downstream-generation-and-test.yml` step `remove-label` and generate_comment.go (`gh.RemoveLabel(pr, "awaiting-approval")`) strip it when the run starts. Seen on #19315, 19163, 19571, 19802 (added then removed). Trusted contributors list: `trustedContributors` in membership data (e.g. PR 19754 adds names).
- Maintainer comments: `@modular-magician <command>` handled by magician-commands.yml (parse_comment.go) e.g. reassign reviewer, rerun tests.
- scheduled-pr-reminders.yml sends waiting-for-review/contributor/merge reminders and closes stale PRs.

## 8. Test evidence when VCR cannot run the test
- Docs: docs/content/test/test.md "Skip tests in VCR replaying mode" (~line 523): generated sample -> `skip_vcr: true` with a comment giving the reason or issue link; handwritten -> `acctest.SkipIfVcr(t)`. Skipped tests still run in the nightly suite. docs/content/reference/sample.md: `exclude_test: true` (no test generated at all), `skip_vcr: true`, `skip_test: <ticket link>` (skipped everywhere; value must be a ticket link), `tgc_skip_test`. test.md: for user-facing doc samples with unavoidable nondeterminism use `skip_vcr: true` with reason comment rather than test-only depends_on.
- Precedents: #19344 (observability: skip VCR; reason nondeterministic services:batchEnable order; bot showed 1 skipped; merged), #15855 (Excluded test generation for WasmPlugins examples; reason test can't supply a repository with plugin code, covered by handwritten update tests; merged), #19330 / sweepable PRs reference exclude_test as a mechanism, #19315 proposes `exclude_test: true` for the spend-cap sample.
- Expectation (review-pr.md + PRs): put manual evidence in the PR description - e.g. which TestAcc* you ran locally/in a real project with TF_ACC and result (`go test ... -run=` output summary), or API audit-log verification (#19163 did this), plus explanation why VCR is impossible, and a link/issue comment. For GA promotions, list the tests run manually (#19755 bot listed GA-only tests needing manual verification). Unrelated recording failures are explained in the body (#19755).
- Reviewer will still want a non-skipped test where feasible; do not weaken coverage (AGENTS.md rule).

## Open questions
- Exact google-cla semantics for Co-authored-by and mixed authorship (not in repo; confirm in the CLA bot's details link).
- Whether maintainers have an AI-authorship policy; none found in docs/.github.
- Which exact PRs carry human Co-authored-by trailers recently (none found since 2026-07).
- Actual base branch of #19285 and how magician treats it (not fetched).
