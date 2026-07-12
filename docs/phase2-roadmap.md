# Phase 2 Roadmap: Path to Enterprise Scale

This consolidates the Phase 2 TODOs already scattered across `main.bicep`,
`docs/graph-resources.md`, `docs/compliance-mapping.md`'s "Gaps to close",
and findings from the full-project review on 2026-07-12. It's ordered by
what unblocks what, not by importance — some items are prerequisites for
others.

## 1. Automated testing

**Status: not started.** Every control today is verified manually against
the live sandbox, walked through step-by-step in
`docs/poc-evidence/README.md`. There's no scripted assertion that RBAC,
Conditional Access, PIM, or persona access controls actually behave as
designed — "it works" is currently provable only by a human clicking
through the Entra portal.

- `tests/ConditionalAccess.RegressionGuard.Tests.ps1` (added alongside
  this roadmap) is the first piece: a static Pester test over the Bicep
  *source*, not live Azure, that catches exactly the report-only regression
  found and fixed in the CA policy review (5 of 6 policies were
  accidentally hardcoded to `enabled`). Runs in CI with no Azure
  credentials needed.
- Next: a live-resource Pester suite (`tests/PostDeploy.Tests.ps1`,
  scaffolded but not yet CI-wired — see that file's header) asserting
  against the actual deployed subscription: Defender plans at Standard
  tier, Sentinel rules enabled, custom RBAC role definitions match their
  Bicep source, no unexpected standing role assignments.
- Once Conditional Access is actually deployed (see #3), extend this with
  the Microsoft Graph `conditionalAccess/evaluate` "What If" API to assert
  specific request shapes get blocked/allowed — this is the only way to
  test CA policy *logic*, not just that the policy object exists.

## 2. Entra ID group provisioning

**Status: not started.** Confirmed via review: nothing in this repo
creates Entra ID groups. `breakGlassGroupId`, Conditional Access
`excludeGroups`, PIM `primaryApprovers`, and Access Package
`SponsorGroupId` are all parameters expecting a **pre-existing** group's
Object ID — every group referenced here is assumed to already exist,
created manually in the portal.

- Add a `bicep/modules/groups.bicep` (Graph Bicep extension,
  `Microsoft.Graph/groups`) defining the break-glass group, per-role
  approver/sponsor groups, and any persona-scoped groups referenced
  elsewhere in this repo.
- Blocked on the same Graph extension availability issue as #3.

## 3. Close the Graph resources gap for real

**Status: partially blocked, partially just unwired.** Two separate
problems, not one:

- The Graph Bicep extension itself isn't supported on this CI runner
  (`BCP407`, confirmed via an actual pipeline failure) — wait for GA, or
  commit fully to the PowerShell fallback path in `scripts/graph/`.
- Even the fallback path doesn't run today: `GRAPH_BICEP_EXTENSION_AVAILABLE`
  is checked in `deploy.yml` but never set by `configure-repo-secrets.py`
  or anywhere else. And even if it were set, the fallback would fail —
  `setup-federated-identity.ps1` only grants the CI identity **Azure**
  RBAC roles, never Graph API permissions
  (`Policy.ReadWrite.ConditionalAccess`, `RoleManagementPolicy.ReadWrite.Directory`).
  Granting those requires tenant-level admin consent — a deliberate
  decision point, not something to automate silently.

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

- Build the Sentinel "Compliance Evidence" workbook.
- Formalize Access Review cadence (quarterly minimum for CE Plus).
- Document and dry-run the break-glass account procedure.
- Confirm the Defender for Cloud regulatory-compliance dashboard maps to
  the ISO 27001 built-in initiative.

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
