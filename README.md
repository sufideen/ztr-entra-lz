# Zero Trust Landing Zone

Identity-centric Zero Trust platform for Entra ID, built for mixed populations
(employees, contractors, vendors/B2B, and workload identities) landing on top
of an Azure Landing Zone. Deployed entirely via Bicep + GitHub Actions with a
DevSecOps gate at every stage.

## Why this exists

Most "Zero Trust" builds are a pile of manually-clicked Conditional Access
policies with no audit trail and no repeatability. This repo treats identity
control plane configuration (Conditional Access, PIM, RBAC, Sentinel
analytics) as code, with the same CI/CD discipline as application
infrastructure — What-If validation, policy-as-code scanning, and OIDC
federated deploy credentials (no stored secrets, anywhere).

## Scope / non-goals

- This repo owns: Conditional Access policies, PIM role settings, custom
  Azure RBAC role definitions, central Log Analytics workspace, Sentinel
  analytics rules/workbooks, Defender for Cloud plan configuration,
  diagnostic settings policy.
- This repo does **not** own: application infrastructure (see
  `ict-labs-platform`), Access Package definitions (owned by
  `scripts/graph`, since Entitlement Management isn't yet a stable Bicep
  resource type — see `docs/graph-resources.md`).

## Architecture

```
Tenant Root Management Group
├── mg-platform
│   ├── sub-identity        (this repo deploys here: PIM, CA, custom roles)
│   ├── sub-connectivity     (hub: central Log Analytics + Sentinel)
│   └── sub-management       (Defender for Cloud plans, Update Manager)
├── mg-landing-zones
│   ├── mg-corp              (employee-facing workloads)
│   └── mg-online             (B2B / vendor-facing workloads)
└── mg-decommissioned
```

Every subscription inherits diagnostic settings and Defender plans via
Azure Policy `DeployIfNotExists`, so nothing new can land in the tenant
unmonitored.

> **Current status**: the diagram above is the Phase 2 / production target.
> The POC currently deploys `bicep/main.bicep` at **subscription** scope
> (`targetScope = 'subscription'`) against a single sandbox subscription with
> no management group hierarchy set up — see the STATUS comment at the top of
> `main.bicep` for why, and `THROWAWAY.md` for the sandbox this targets by
> default.

## Personas → Access Model

| Persona | Identity source | Lifecycle | Session controls |
|---|---|---|---|
| Employee | Entra ID native, hybrid/Entra-joined device | Joiner/mover/leaver via HR-driven Entra provisioning | CA: compliant device + MFA |
| Contractor | Entra B2B guest via Access Package | Fixed expiry (default 90d), auto-review | CA: MFA + ToU + browser-only session |
| Vendor / B2B partner | Entra B2B guest, cross-tenant access policy scoped to specific apps | Sponsor-approved Access Package | CA: MFA + App Enforced Restrictions, no download |
| Workload / pipeline | Managed Identity / Workload Identity Federation | No credential — federated OIDC trust | Scoped custom RBAC role, no standing secret |

All privileged **roles** (Entra + Azure RBAC) are PIM-eligible only — see
`bicep/modules/pim.bicep`.

## Compliance mapping

See `docs/compliance-mapping.md` for the Cyber Essentials + ISO 27001
Annex A control mapping and where the evidence lives (Policy compliance
state, Sentinel workbook, PIM audit log).

## Pipeline status (as of 2026-07-12)

The full CI/CD pipeline — lint + PSRule + Checkov → What-If → deploy — runs
green end to end against the sandbox subscription. Getting there took a
chain of fixes (PRs #8–#14) across two categories:

- **Template bugs**: a Bicep scope mismatch left over from the
  subscription-scope retarget, a bogus custom log table reference, an
  invalid Key Vault RBAC action, a deprecated Defender auto-provisioning
  setting, missing required Sentinel alert-rule properties, invalid MITRE
  tactic/technique IDs, an invalid KQL `join`, and a missing required
  `scopePath` on the Defender continuous-export automation.
- **RBAC / deployment-model gaps**: the CI service principal needed
  subscription-scope Contributor (not just a resource-group grant) to run
  `az deployment sub` at all, plus a narrow custom role to cover the
  `Microsoft.Authorization/*/write` actions Contributor deliberately
  excludes — see "One-time bootstrap" below. The Defender pricing-plan
  deployment also needed `@batchSize(1)` to avoid an internal Azure lock
  conflict when writing multiple plans in parallel.

## Deploy

See `.github/workflows/deploy.yml`. Summary: PR triggers lint + PSRule +
Checkov + What-If; merge to `main` triggers deployment at subscription
scope using OIDC federated credentials (no stored secrets), gated behind
a GitHub Environment manual-approval step.

```bash
az deployment sub create \
  --location uksouth \
  --template-file bicep/main.bicep \
  --parameters bicep/params/sandbox.bicepparam
```

### One-time bootstrap: CI OIDC identity

Before the pipeline can authenticate to Azure, run
`scripts/azure/setup-federated-identity.ps1` once (under an Azure identity
with Owner/User Access Administrator on the target subscription) to create
the app registration, federated credential, and RBAC grants the pipeline
needs:

```powershell
.\scripts\azure\setup-federated-identity.ps1 -GitHubEnvironment sandbox -ResourceGroupName rg-security-sandbox
```

It's idempotent — safe to re-run any time the RBAC grants below change.
It assigns the CI service principal:

- **Contributor**, scoped to the subscription (subscription-scope
  deployments require `Microsoft.Resources/deployments/*` permissions at
  the subscription itself, not just at a child resource group).
- A narrow custom role, **"ztr-entra-lz CI Authorization Writer"**, scoped
  to the subscription — grants only
  `Microsoft.Authorization/{roleDefinitions,policyDefinitions,policyAssignments}/write`,
  which Contributor deliberately excludes. It does **not** include
  `Microsoft.Authorization/roleAssignments/*`, so the CI identity can
  define roles and policies but can never grant or revoke access to
  anyone, including itself — a deliberately narrower alternative to the
  built-in User Access Administrator role.

Then add the script's printed `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` /
`AZURE_SUBSCRIPTION_ID` output as secrets on the `sandbox` GitHub
Environment (or run `configure-repo-secrets.py`).

## Next steps

- **Re-enable PSRule as a hard gate** (currently `continue-on-error: true`
  in `deploy.yml`) once the 32-item backlog in `docs/compliance-mapping.md`
  is cleared.
- **Triage the Checkov code-scanning alert** raised on PR #13 (non-blocking
  today — see the repo's Security tab for details).
- **Graph resources (Conditional Access / PIM)**: still deployed out-of-band
  via `scripts/graph/*.ps1` — `bicep/modules/conditionalAccess.bicep` and
  `pim.bicep` stay disabled pending Graph Bicep extension support
  (`BCP407` on this CI runner's Bicep CLI); revisit per
  `docs/graph-resources.md`.
- **Fill in the POC evidence metrics** in `docs/poc-evidence/README.md`
  (Secure Score before/after, CA policies enforced, PR-merge-to-deploy
  time) now that a real deploy has succeeded.
- **Phase 2**: move from single-subscription scope back to the full
  management-group hierarchy in the Architecture diagram above, once that
  hierarchy actually exists — see the STATUS comment in `main.bicep`.
