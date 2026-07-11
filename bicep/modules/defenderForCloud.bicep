targetScope = 'subscription'

@description('Resource ID of the central Log Analytics workspace Defender should export to')
param workspaceResourceId string

@description('Environment name, used to locate the shared rg-security-<environment> resource group')
param environment string

var plansToEnable = [
  'VirtualMachines'
  'AppServices'
  'SqlServers'
  'KeyVaults'
  'StorageAccounts'
  'Containers'
  'Arm' // Defender for Resource Manager - catches suspicious ARM/Bicep deployment activity
  'CloudPosture' // CSPM, drives Secure Score
]

resource defenderPlans 'Microsoft.Security/pricings@2024-01-01' = [for plan in plansToEnable: {
  name: plan
  properties: {
    pricingTier: 'Standard'
  }
}]

// Continuous export of Secure Score/alerts/compliance to the central workspace.
// Microsoft.Security/automations is resourceGroup-scoped (unlike pricings and
// autoProvisioningSettings below, which are subscription-scoped) - see
// defenderContinuousExport.bicep and docs/graph-resources.md-style rationale
// for why this is a separate nested module rather than inline here.
module continuousExport 'defenderContinuousExport.bicep' = {
  name: 'deploy-defender-continuous-export'
  scope: resourceGroup('rg-security-${environment}')
  params: {
    workspaceResourceId: workspaceResourceId
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
