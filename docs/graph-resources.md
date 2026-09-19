# Decision record: Deploying Microsoft Graph resources (CA, PIM, Access Packages, DLP)

## Problem

Conditional Access policies, PIM role management policies, and Entitlement
Management Access Packages are Microsoft Graph resources, not ARM resources.
They aren't natively deployable through standard `az deployment` the way
Key Vaults or VMs are.

## Options considered

1. **Microsoft Graph Bicep extension** (preview, `extension microsoftGraph`)
   — lets us author these as Bicep resources with the same PR/What-If
   workflow as everything else. Preview maturity varies by resource type;
   confirm support in your Bicep CLI version before relying on it in prod.
2. **Microsoft.Graph PowerShell SDK**, scripted and run from the same
   pipeline, authenticated via the same OIDC federated identity.
3. **Terraform AzureAD provider** — mature and stable, but introduces a
   second IaC tool/state store into a Bicep-first repo. Rejected to keep
   one deployment technology and one review process.

## Decision

Use the Graph Bicep extension where the pipeline's Bicep CLI version
supports it (tracked via the `GRAPH_BICEP_EXTENSION_AVAILABLE` repo
variable). Fall back to the PowerShell scripts in `scripts/graph/` when it
doesn't. Both paths are idempotent and run from the same CI/CD stage so the
review and approval process is identical either way.

**Action item**: revisit this quarterly — extend `bicep/modules/*.bicep` to
be the sole source of truth once Graph extension coverage is confirmed
stable for all resource types used here (conditionalAccessPolicies,
roleManagementPolicies, accessPackages, accessPackageAssignmentPolicies).

## Update - 2026-07-11: confirmed via CI

The predicted limitation above was hit on the first real pipeline run
against this repo's GitHub-hosted runners: `az bicep build` failed with
`BCP407` on `bicep/modules/conditionalAccess.bicep`, confirming the
Microsoft Graph Bicep extension is not usable in this environment today.

**Resolution applied**: the `conditionalAccess` and `pim` module
references in `bicep/main.bicep` are commented out (not deleted - the
module files remain in the repo as the intended future state). CA and
PIM policies are deployed via the PowerShell fallback scripts in
`scripts/graph/` as a manual step, run separately from the Bicep
pipeline, until the Graph extension is confirmed stable.

This is tracked as a Phase 2 item: re-enable the Bicep modules once a
newer Bicep CLI version with stable Graph extension support is available
on GitHub-hosted runners (or pin a self-hosted runner with a specific
CLI version, if that becomes necessary sooner).

## Update - 2026-07-12: the fallback path itself isn't actually live either

A closer look found the PowerShell fallback isn't just a manual step - it
doesn't run automatically at all, and couldn't even if triggered:

- `deploy.yml`'s fallback step is gated on
  `vars.GRAPH_BICEP_EXTENSION_AVAILABLE == 'false'`, but that repo
  variable has never been set (not by `configure-repo-secrets.py`, not
  manually) - GitHub Actions treats an unset variable as an empty string,
  which never equals `'false'`, so the step is silently skipped on every
  run.
- Even if the variable were set, the CI app registration
  (`setup-federated-identity.ps1`) only grants **Azure** RBAC roles -
  it's never been granted any **Microsoft Graph** API permission. The
  `deploy-conditional-access.ps1` / `deploy-pim-policies.ps1` scripts'
  `Connect-MgGraph -Scopes ...` calls would fail outright.

### Decision needed: commit to the fallback path, or wait for GA

Two real options, not one:

1. **Wait for the Graph Bicep extension to reach GA** on GitHub-hosted
   runners. Zero new privilege granted in the meantime; `conditionalAccess.bicep`
   and `pim.bicep` stay disabled until then. No effort required now, but
   no CA/PIM enforcement testing through the real pipeline either.
2. **Commit to the PowerShell fallback path properly** - this closes the
   gap above and is what actually unblocks Workstream C's Bicep path
   (`groups.bicep`) and real CA/PIM enforcement testing. Requires:
   - Run `scripts/azure/grant-graph-api-permissions.ps1` (new - requests
     `Policy.ReadWrite.ConditionalAccess` and
     `RoleManagementPolicy.ReadWrite.Directory` as Application permissions
     on the CI app registration; scoped to only what
     `deploy-conditional-access.ps1`/`deploy-pim-policies.ps1` need, not
     the broader `User.ReadWrite.All`/`EntitlementManagement.ReadWrite.All`
     that `create-test-personas.ps1` needs - those scripts are designed
     for a human operator's own delegated session, not the unattended CI
     identity, so they're deliberately excluded).
   - A Global Administrator runs the `az ad app permission admin-consent`
     command the script prints - **not automated**, this is a real,
     tenant-wide privilege escalation for the CI identity and needs
     deliberate sign-off.
   - Set the `GRAPH_BICEP_EXTENSION_AVAILABLE` repo variable to `false`
     so the already-written `deploy.yml` step actually executes.

Recommendation: option 2. The Graph Bicep extension has been in preview
with no committed GA date, and this repo's whole premise (CA/PIM
enforcement testing, group provisioning) is blocked without a working
Graph deployment path of *some* kind. The permission grant is narrow and
auditable (two named permissions, admin-consent is a separate deliberate
step, not silent), which is the same least-privilege bar the rest of this
repo's RBAC decisions have held to (see README's "One-time bootstrap: CI
OIDC identity" for the equivalent reasoning on the Azure RBAC side).

## Update - 2026-08-29: DLP/Purview is a separate control plane, not Microsoft Graph

Investigating what it would take to add Microsoft Purview DLP (Data Loss
Prevention) policies (see `scripts/purview/deploy-dlp-policies.ps1`) found
this doesn't fit the CA/PIM/Access-Package pattern above at all: Purview DLP
compliance policies (`New-DlpCompliancePolicy`, `New-DlpComplianceRule`) are
Security & Compliance Center resources, managed through Security &
Compliance PowerShell (`ExchangeOnlineManagement` module,
`Connect-IPPSSession`) - **not** Microsoft Graph, and with no confirmed
Bicep-deployable resource type at all (unlike CA/PIM, whose Graph resource
types are real and just currently blocked by this CI's Bicep CLI version).

**This needs verification, not treated as settled**: whether Microsoft
Graph (stable or beta) exposes any DLP policy surface today, and if so
whether a Bicep extension resource type exists for it, should be re-checked
against current Graph API docs before ruling out a Bicep-first approach
permanently.

Given that, this repo's decision for DLP is:

- **No `.bicep` module for DLP** for now - unlike `conditionalAccess.bicep`/
  `pim.bicep` (kept as "intended future state" because their resource types
  are confirmed real), authoring speculative Bicep for an unconfirmed
  resource type risks breaking `az bicep build` in `lint-and-scan` for no
  benefit. Revisit once the point above is verified.
- **`scripts/purview/deploy-dlp-policies.ps1` is the real and only source of
  truth**, not a fallback - it lives in its own `scripts/purview/`
  directory (rather than `scripts/graph/`) precisely because it talks to a
  different control plane with a different PowerShell module and a
  different auth story.
- **Open question, not yet resolved**: whether `Connect-IPPSSession`/
  `Connect-ExchangeOnline` can authenticate unattended using this repo's
  existing OIDC federated credential (avoiding a new stored secret, keeping
  the "no stored secrets, anywhere" posture from README.md), or whether it
  requires certificate-based app-only auth instead - check current
  `ExchangeOnlineManagement` module release notes/docs before deciding.
  Until this is resolved, `deploy-dlp-policies.ps1` runs only via an
  interactive `Connect-IPPSSession` (a human operator's own delegated
  session), same as the human-operator-only class of scripts in
  `scripts/graph/` (`create-test-personas.ps1` etc.) - it is not wired into
  `deploy.yml`.
- **Additional permission surface beyond a Graph app-role grant**: even
  once an auth mechanism is chosen, `scripts/azure/grant-exchange-api-permissions.ps1`
  granting `Exchange.ManageAsApp` + admin consent is not sufficient on its
  own - the app registration must also be added to an Exchange Online RBAC
  role group scoped to DLP management (that script prints, but does not
  run, the `New-RoleGroup`/`Add-RoleGroupMember` commands for this).

Tracked as a Phase 2 item alongside the existing Graph resources gap: see
`docs/phase2-roadmap.md`.
