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
  'Arm' // Defender for Resource Manager — catches suspicious ARM/Bicep deployment activity
  'CloudPosture' // CSPM, drives Secure Score
]

// Microsoft.Security/pricings enforces a subscription-level lock on pricing
// tier changes internally, even though each plan is a separate ARM resource -
// deploying this loop in parallel (Bicep/ARM's default) causes intermittent
// "Conflict: Another update operation is in progress" failures between the
// plans. @batchSize(1) forces sequential deployment to avoid that lock
// contention.
//
// checkov:skip=CKV_AZURE_87: false positive - Checkov can't resolve the
// looped `name: plan` against the literal 'KeyVaults' string this check
// needs to match, even though plansToEnable (below) includes 'KeyVaults'
// at pricingTier 'Standard'. Confirmed via local checkov 3.3.8 run that
// the generic CKV_AZURE_19 ("standard pricing tier is selected") passes
// on this same resource - only the plan-name-specific checks (CKV_AZURE_87
// for Key Vault, and presumably the equivalent for other named plans) fail
// due to this static-analysis limitation with Bicep for-loops.
@batchSize(1)
resource defenderPlans 'Microsoft.Security/pricings@2024-01-01' = [for plan in plansToEnable: {
  name: plan
  properties: {
    pricingTier: 'Standard'
  }
}]

// Continuous export of Secure Score + recommendations + alerts to the central workspace.
// Microsoft.Security/automations is resourceGroup-scoped (unlike the subscription-scoped
// pricings/autoProvisioningSettings resources here), so it's deployed as a nested module
// targeting the shared rg-security-<environment> resource group - see
// defenderContinuousExport.bicep.
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

// NOTE: no autoProvisioningSettings resource here - the 'On' Log Analytics
// agent auto-provisioning setting this used to configure is deprecated and
// rejected outright by the API as of 2024 (Microsoft retired the Log
// Analytics/MMA agent). Defender for Cloud now handles agent provisioning
// per-plan via extensions on the Microsoft.Security/pricings resources
// above rather than this subscription-wide legacy setting.
