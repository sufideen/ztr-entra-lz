targetScope = 'subscription'

// One-off deployment of the subscription-level Microsoft.Authorization
// resources that the CI service principal is deliberately NOT permitted to
// write: custom RBAC role definitions, and the diagnostic-settings policy
// definition/assignment. Contributor excludes Microsoft.Authorization/*/write
// by design (Azure's guardrail against Contributor self-escalating access),
// and this repo intentionally does not widen the unattended CI identity to
// User Access Administrator/Owner to reach it - see main.bicep and
// scripts/azure/deploy-privileged-resources.ps1 for the rationale.
//
// Run this manually via deploy-privileged-resources.ps1, under an identity
// that holds User Access Administrator (or Owner) at the subscription -
// never wire this into the automated CI/CD pipeline.

@description('Resource ID of the central Log Analytics workspace, from the main pipeline''s deploy-central-law output')
param workspaceResourceId string

// ---- Diagnostic settings enforcement policy ----
module diagPolicy 'modules/diagnosticSettings.bicep' = {
  name: 'deploy-diagnostic-policy'
  params: {
    workspaceResourceId: workspaceResourceId
  }
}

// ---- Custom RBAC role definitions ----
module customRoles 'modules/rbac/customRoles.bicep' = {
  name: 'deploy-custom-rbac-roles'
}

output customRoleIds array = customRoles.outputs.roleDefinitionIds
