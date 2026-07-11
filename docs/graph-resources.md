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
