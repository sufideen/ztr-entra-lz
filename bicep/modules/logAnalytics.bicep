targetScope = 'subscription'

@description('Azure region')
param location string

@description('Environment name')
param environment string

@description('Common tags')
param tags object

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-security-${environment}'
  location: location
  tags: tags
}

module workspace 'logAnalyticsWorkspace.bicep' = {
  name: 'law-inner'
  scope: rg
  params: {
    location: location
    environment: environment
    tags: tags
  }
}

output workspaceId string = workspace.outputs.workspaceId
output workspaceName string = workspace.outputs.workspaceName
