targetScope = 'resourceGroup'

@description('Resource ID of the central Log Analytics workspace Defender should export to')
param workspaceResourceId string

@description('Azure region')
param location string = 'uksouth'

// Microsoft.Security/automations is resourceGroup-scoped, unlike the
// subscription-scoped pricings/autoProvisioningSettings resources in
// defenderForCloud.bicep - hence this being a separate nested module,
// invoked at resourceGroup scope from there.
resource continuousExport 'Microsoft.Security/automations@2023-12-01-preview' = {
  name: 'export-to-central-law'
  location: location
  properties: {
    isEnabled: true
    scopes: [
      { description: 'subscription-scope', scopePath: subscription().id }
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
