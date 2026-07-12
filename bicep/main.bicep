targetScope = 'subscription'

// STATUS: retargeted from managementGroup to subscription scope on
// 2026-07-11. The original design assumed a full Azure Landing Zone
// management group hierarchy (mg-platform, mg-connectivity, etc), but
// this POC runs in a single sandbox subscription with no management
// group structure set up. Deploying at managementGroup scope against a
// value that is actually a resource group name produced AuthorizationFailed
// / invalid scope errors on the first real pipeline run - see git history
// on this file for that failure.
//
// `az deployment sub what-if|create` (subscription scope) in turn requires
// Microsoft.Resources/deployments/* permissions at the subscription itself,
// not just at a resource group, so the OIDC app registration's RBAC grant
// (see scripts/azure/setup-federated-identity.ps1) was widened from a
// single resource group to the whole subscription to match.
//
// Phase 2 TODO: once a real ALZ management group hierarchy exists,
// revisit this and connectivitySubscriptionId/identitySubscriptionId
// below to properly support a multi-subscription hub-spoke layout.

@description('Environment name, used for naming and tagging')
param environment string = 'sandbox'

@description('Azure region for the central logging/security resources')
param location string = 'uksouth'

@description('Object ID of the break-glass emergency access group (excluded from CA)')
param breakGlassGroupId string = ''

@description('App ID of the CI/CD pipeline service principal, excluded from the CA-policy-change-outside-pipeline Sentinel detection')
param pipelineServicePrincipalAppId string = ''

@description('Tags applied to all resources for ISO27001/CE evidence traceability')
param commonTags object = {
  project: 'zero-trust-landing-zone'
  environment: environment
  controlFramework: 'ISO27001-CyberEssentials'
  managedBy: 'bicep-ci'
}

// ---- Central logging + Sentinel ----
module logAnalytics 'modules/logAnalytics.bicep' = {
  name: 'deploy-central-law'
  params: {
    location: location
    environment: environment
    tags: commonTags
  }
}

module sentinelRules 'modules/sentinel/analyticsRules.bicep' = {
  name: 'deploy-sentinel-rules'
  scope: resourceGroup('rg-security-${environment}')
  params: {
    workspaceName: logAnalytics.outputs.workspaceName
    pipelineServicePrincipalAppId: pipelineServicePrincipalAppId
  }
  dependsOn: [
    logAnalytics
  ]
}

module complianceWorkbook 'modules/sentinel/complianceWorkbook.bicep' = {
  name: 'deploy-compliance-workbook'
  scope: resourceGroup('rg-security-${environment}')
  params: {
    location: location
    workspaceResourceId: logAnalytics.outputs.workspaceId
  }
  dependsOn: [
    logAnalytics
  ]
}

// ---- Defender for Cloud plans ----
module defender 'modules/defenderForCloud.bicep' = {
  name: 'deploy-defender-plans'
  params: {
    workspaceResourceId: logAnalytics.outputs.workspaceId
    environment: environment
  }
}

// ---- Diagnostic settings enforcement policy ----
module diagPolicy 'modules/diagnosticSettings.bicep' = {
  name: 'deploy-diagnostic-policy'
  params: {
    workspaceResourceId: logAnalytics.outputs.workspaceId
  }
}

// ---- Custom RBAC role definitions ----
module customRoles 'modules/rbac/customRoles.bicep' = {
  name: 'deploy-custom-rbac-roles'
}

// ---- ISO 27001 regulatory-compliance policy assignment ----
module iso27001Policy 'modules/compliance/iso27001PolicyAssignment.bicep' = {
  name: 'deploy-iso27001-policy'
}

// ---- Conditional Access + PIM: Microsoft Graph plane ----
// STATUS: disabled in this Bicep deployment - see docs/graph-resources.md
// for the decision record. Deployed separately via scripts/graph/.
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
output complianceWorkbookId string = complianceWorkbook.outputs.workbookId
output iso27001PolicyAssignmentId string = iso27001Policy.outputs.policyAssignmentId
