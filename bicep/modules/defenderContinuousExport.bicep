targetScope = 'resourceGroup'

@description('Resource ID of the central Log Analytics workspace Defender should export to')
param workspaceResourceId string

@description('Azure region')
param location string = 'uksouth'

// Continuous export of Secure Score + recommendations + alerts to the central workspace.
// This resource type (Microsoft.Security/automations) is resourceGroup-scoped, unlike
// Microsoft.Security/pricings and autoProvisioningSettings which are subscription-scoped -
// hence this being a separate module from defenderForCloud.bicep, invoked at resourceGroup
// scope from there.
resource continuousExport 'Microsoft.Security/automations@2023-12-01-preview' = {
  name: 'export-to-central-law'
  location: location
  properties: {
    isEnabled: true
    scopes: [
      { description: 'subscription-scope' }
    ]
    sources: [
      { eventSource: 'Alerts', ruleSets: [] }
      { eventSource: 'SecureScores', ruleSets: [] }
      { eventSource: 'RegulatoryComplianceAssessment', ruleSets: [] }
    ]
    actions: [
      {
        actionType: 'Workspace'
        workspaceResourceId: workspaceResourceId
      }
    ]
  }
}
