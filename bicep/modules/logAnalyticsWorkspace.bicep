@description('Azure region')
param location string

@description('Environment name')
param environment string

@description('Common tags')
param tags object

var workspaceName = 'law-central-sec-${environment}'

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 365 // ISO27001 A.12.4 log retention evidence
    features: {
      immediatePurgeDataOn30Days: false
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Disabled' // query only via Sentinel/Private Link
  }
}

// Onboard Microsoft Sentinel onto the workspace
resource sentinelOnboarding 'Microsoft.SecurityInsights/onboardingStates@2024-03-01' = {
  scope: law
  name: 'default'
  properties: {}
}

output workspaceId string = law.id
output workspaceName string = law.name
