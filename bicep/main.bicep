targetScope = 'managementGroup'

@description('Environment name, used for naming and tagging')
param environment string = 'prod'

@description('Azure region for the central logging/security resources')
param location string = 'uksouth'

@description('Subscription ID hosting the central Log Analytics workspace and Sentinel')
param connectivitySubscriptionId string

@description('Subscription ID hosting the identity-plane resources (custom RBAC, diagnostic policy assignment)')
param identitySubscriptionId string

@description('Object ID of the break-glass emergency access group (excluded from CA)')
param breakGlassGroupId string

@description('Tags applied to all resources for ISO27001/CE evidence traceability')
param commonTags object = {
  project: 'zero-trust-landing-zone'
  environment: environment
  controlFramework: 'ISO27001-CyberEssentials'
  managedBy: 'bicep-ci'
}

// ---- Central logging + Sentinel (connectivity subscription) ----
module logAnalytics 'modules/logAnalytics.bicep' = {
  name: 'deploy-central-law'
  scope: subscription(connectivitySubscriptionId)
  params: {
    location: location
    environment: environment
    tags: commonTags
  }
}

module sentinelRules 'modules/sentinel/analyticsRules.bicep' = {
  name: 'deploy-sentinel-rules'
  scope: subscription(connectivitySubscriptionId)
  params: {
    workspaceName: logAnalytics.outputs.workspaceName
  }
  dependsOn: [
    logAnalytics
  ]
}

// ---- Defender for Cloud plans (management subscription tenant-wide) ----
module defender 'modules/defenderForCloud.bicep' = {
  name: 'deploy-defender-plans'
  scope: subscription(connectivitySubscriptionId)
  params: {
    workspaceResourceId: logAnalytics.outputs.workspaceId
  }
}

// ---- Diagnostic settings enforcement policy, assigned at management group ----
module diagPolicy 'modules/diagnosticSettings.bicep' = {
  name: 'deploy-diagnostic-policy'
  params: {
    workspaceResourceId: logAnalytics.outputs.workspaceId
  }
}

// ---- Custom RBAC role definitions, assigned at management group scope ----
module customRoles 'modules/rbac/customRoles.bicep' = {
  name: 'deploy-custom-rbac-roles'
}

// ---- Conditional Access + PIM: Microsoft Graph plane ----
// STATUS: disabled in this Bicep deployment as of 2026-07-11.
// The GitHub-hosted runner's Bicep CLI does not support the
// `extension microsoftGraph` syntax used in conditionalAccess.bicep and
// pim.bicep (confirmed via CI failure: BCP407 on conditionalAccess.bicep).
// This was a known, documented risk before this repo was built — see
// docs/graph-resources.md for the decision record and the fallback path.
//
// CA and PIM policies are deployed separately via the PowerShell scripts
// in scripts/graph/ (deploy-conditional-access.ps1, deploy-pim-policies.ps1),
// run as an explicit step outside this Bicep template until the Graph
// extension is confirmed stable in this environment.
//
// module conditionalAccess 'modules/conditionalAccess.bicep' = {
//   name: 'deploy-conditional-access'
//   params: {
//     breakGlassGroupId: breakGlassGroupId
//   }
// }
//
// module pim 'modules/pim.bicep' = {
//   name: 'deploy-pim-settings'
// }

output centralWorkspaceId string = logAnalytics.outputs.workspaceId
output customRoleIds array = customRoles.outputs.roleDefinitionIds
