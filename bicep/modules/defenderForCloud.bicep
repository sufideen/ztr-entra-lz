targetScope = 'subscription'

@description('Resource ID of the central Log Analytics workspace Defender should export to')
param workspaceResourceId string

var plansToEnable = [
  'VirtualMachines'
  'AppServices'
  'SqlServers'
  'KeyVaults'
  'StorageAccounts'
  'Containers'
  'Arm' // Defender for Resource Manager — catches suspicious ARM/Bicep deployment activity
  'CloudPosture' // CSPM, drives Secure Score
]

resource defenderPlans 'Microsoft.Security/pricings@2024-01-01' = [for plan in plansToEnable: {
  name: plan
  properties: {
    pricingTier: 'Standard'
  }
}]

// Continuous export of Secure Score + recommendations + alerts to the central workspace
resource continuousExport 'Microsoft.Security/automations@2023-12-01-preview' = {
  name: 'export-to-central-law'
  location: 'uksouth'
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
  dependsOn: [
    defenderPlans
  ]
}

// Auto-provisioning of Log Analytics agent / Azure Monitor Agent for Defender-covered resources
resource autoProvision 'Microsoft.Security/autoProvisioningSettings@2017-08-01-preview' = {
  name: 'default'
  properties: {
    autoProvision: 'On'
  }
}
