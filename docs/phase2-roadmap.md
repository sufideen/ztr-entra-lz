# Phase 2 Roadmap: Path to Enterprise Scale

This consolidates the Phase 2 TODOs already scattered across `main.bicep`,
`docs/graph-resources.md`, `docs/compliance-mapping.md`'s "Gaps to close",
and findings from the full-project review on 2026-07-12. It's ordered by
what unblocks what, not by importance — some items are prerequisites for
others.

## 1. Automated testing

**Status: both Pester suites now exist and are CI-wired.**
`tests/ConditionalAccess.RegressionGuard.Tests.ps1` is a static Pester
test over the Bicep *source*, not live Azure, that catches exactly the
report-only regression found and fixed in the CA policy review (5 of 6
policies were accidentally hardcoded to `enabled`) — runs in `lint-and-scan`
on every PR, no Azure credentials needed. `tests/PostDeploy.Tests.ps1` is
a live-resource Pester suite wired into the `deploy` job (right after
"Deploy landing zone (Bicep)"), asserting against the actual deployed
subscription: Log Analytics retention, Defender plans at Standard tier,
Sentinel rules enabled, custom RBAC role definitions exist, and the CI
identity itself holds only its two documented standing role assignments.

- Remaining: once Conditional Access is actually deployed (see #3), extend
  this with the Microsoft Graph `conditionalAccess/evaluate` "What If" API
  to assert specific request shapes get blocked/allowed — this is the
  only way to test CA policy *logic*, not just that the policy object
  exists.

## 2. Entra ID group provisioning

**Status: authored, not deployed.** `bicep/modules/groups.bicep` (Graph
Bicep extension, `Microsoft.Graph/groups`) now defines the break-glass
group and the contractor/vendor test sponsor groups referenced by
`scripts/graph/create-test-personas.ps1`. It is **not** wired into
`main.bicep` — same disabled-but-present pattern as
`conditionalAccess.bicep`/`pim.bicep`, blocked on the same Graph extension
availability issue as #3. Until that's resolved, these groups still need
to be created via the Graph portal/PowerShell directly, with their Object
IDs passed as parameters, same as every other Graph-plane resource here.

- `scripts/graph/create-test-personas.ps1` / `teardown-test-personas.ps1`
  (new) create/remove Contractor and Vendor B2B guest test identities via
  the real Access Package flow, plus an optional Employee-persona member
  account — every object tagged `ztlz-test-<persona>-<RunId>` for
  unambiguous teardown. **Authored, not executed** against the real
  tenant — creating B2B guest invitations is a tenant-visible action that
  needs its own explicit go-ahead at execution time.

## 3. Close the Graph resources gap for real

**Status: groundwork prepared, decision + execution pending.** Two
separate problems, not one — full writeup and recommendation now in
`docs/graph-resources.md`'s "Decision needed" section:

- The Graph Bicep extension itself isn't supported on this CI runner
  (`BCP407`, confirmed via an actual pipeline failure) — wait for GA, or
  commit fully to the PowerShell fallback path in `scripts/graph/`.
- Even the fallback path doesn't run today: `GRAPH_BICEP_EXTENSION_AVAILABLE`
  is checked in `deploy.yml` but never set, and the CI identity has never
  been granted any Graph API permission. `scripts/azure/grant-graph-api-permissions.ps1`
  (new) is written and ready — requests exactly the two Application
  permissions `deploy-conditional-access.ps1`/`deploy-pim-policies.ps1`
  need, deliberately excluding the broader user/entitlement permissions
  `create-test-personas.ps1` needs (that script is designed for a human
  operator's own session, not the CI identity). It does not self-consent —
  that's a separate, deliberate Global Administrator action the script
  prints instructions for.
- Recommendation: commit to the fallback path (option 2 in
  `docs/graph-resources.md`) rather than wait indefinitely for extension
  GA — this is the shared blocker keeping `groups.bicep` unwired and CA/PIM
  enforcement untestable through the real pipeline.

## 4. Real management-group hierarchy

**Status: not started, explicitly deferred.** The README's Architecture
diagram (`mg-platform` → `sub-identity`/`sub-connectivity`/`sub-management`,
`mg-landing-zones` → `mg-corp`/`mg-online`) is the target state. Today
everything deploys into one flat sandbox subscription — see the STATUS
comment at the top of `main.bicep` for why (the first real pipeline run
failed with `AuthorizationFailed` against a management-group scope that
didn't exist yet).

- Prerequisite: stand up the actual management-group tree in the tenant.
- Then: revisit `main.bicep`'s `targetScope`, and the
  `connectivitySubscriptionId`/`identitySubscriptionId` split referenced
  in its Phase 2 TODO comment, to support real multi-subscription
  hub-spoke.

## 5. Real segregation of duties

**Status: intentionally simplified for solo operation, needs revisiting
once collaborators exist.**

- `.github/CODEOWNERS` references `@your-org/identity-admins`,
  `@your-org/security-ops`, `@your-org/platform-admins` — placeholder
  teams that don't exist on this personal repo, so the review requirement
  it's meant to enforce is currently a no-op.
- `scripts/github/configure-repo-protections.py` sets
  `required_approving_review_count: 0` — documented in the script's own
  docstring as a deliberate solo-operator workaround (GitHub won't let a
  PR author self-approve toward a review count). Raise to 1+ once a
  second person is added.

## 6. Audit-readiness backlog

Already itemized in `docs/compliance-mapping.md` → "Gaps to close before
a formal audit" — repeated here for visibility since it's genuinely part
of the enterprise-readiness path, not a separate concern:

- [x] Build the Sentinel "Compliance Evidence" workbook —
      `bicep/modules/sentinel/complianceWorkbook.bicep`.
- [x] Formalize Access Review cadence (quarterly minimum for CE Plus) —
      `docs/access-review-policy.md` (policy defined; automation still
      blocked on the Graph extension gap, see #3).
- [x] Document and dry-run the break-glass account procedure —
      `docs/break-glass-procedure.md` documents it; the dry-run itself is
      still a manual action to perform and log.
- [x] Confirm the Defender for Cloud regulatory-compliance dashboard maps
      to the ISO 27001 built-in initiative —
      `bicep/modules/compliance/iso27001PolicyAssignment.bicep`.

## 7. ict-labs-platform integration

**Status: undetermined — needs that repo's own contents to assess
concretely.** This session doesn't have access to `ict-labs-platform`, so
the integration surface below is inferred from this repo's design alone,
not verified against the other side:

- `diagnosticSettings.bicep`'s `DeployIfNotExists` policy is subscription-wide,
  so any ict-labs-platform resource in the same subscription gets swept
  into central logging automatically, no coordination needed.
- Defender for Cloud / Sentinel are similarly subscription-wide —
  ict-labs-platform inherits them for free once both land in the same
  subscription.
- The custom RBAC roles (`pipelineDeployRole`, `vendorAppDeployer` in
  `customRoles.bicep`) look purpose-built for a *different* pipeline
  identity to assume — but nothing here actually establishes that
  cross-repo federated-credential trust. If ict-labs-platform's CI needs
  to deploy into resources this repo manages, that trust relationship
  needs to be built explicitly (its own federated credential + role
  assignment), not assumed.
