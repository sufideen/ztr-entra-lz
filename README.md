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

## Deploy

See `.github/workflows/deploy.yml`. Summary: PR triggers lint + PSRule +
What-If; merge to `main` triggers scoped deployment
(mg → subscription → resource group) using OIDC, no stored secrets.

```bash
az deployment mg create \
  --management-group-id mg-platform \
  --location uksouth \
  --template-file bicep/main.bicep \
  --parameters bicep/params/prod.bicepparam
```
