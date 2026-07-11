# Decision record: Deploying Microsoft Graph resources (CA, PIM, Access Packages)

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
