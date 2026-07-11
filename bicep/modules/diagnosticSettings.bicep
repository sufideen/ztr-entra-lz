targetScope = 'managementGroup'

@description('Resource ID of the central Log Analytics workspace')
param workspaceResourceId string

var policyDefinitionName = 'deploy-diag-settings-to-central-law'

resource policyDef 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: policyDefinitionName
  properties: {
    displayName: 'Deploy diagnostic settings to central Log Analytics workspace'
    policyType: 'Custom'
    mode: 'Indexed'
    metadata: {
      category: 'Monitoring'
      controlMapping: 'ISO27001-A.12.4 / CyberEssentials-Logging'
    }
    parameters: {
      logAnalytics: {
        type: 'String'
        metadata: {
          displayName: 'Log Analytics workspace'
        }
      }
    }
    policyRule: {
      if: {
        field: 'type'
        in: [
          'Microsoft.KeyVault/vaults'
          'Microsoft.Sql/servers/databases'
          'Microsoft.Storage/storageAccounts'
          'Microsoft.Compute/virtualMachines'
          'Microsoft.Web/sites'
          'Microsoft.Network/networkSecurityGroups'
        ]
      }
      then: {
        effect: 'DeployIfNotExists'
        details: {
          type: 'Microsoft.Insights/diagnosticSettings'
          existenceCondition: {
            field: 'Microsoft.Insights/diagnosticSettings/workspaceId'
            equals: '[parameters(\'logAnalytics\')]'
          }
          roleDefinitionIds: [
            '/providers/microsoft.authorization/roleDefinitions/92aaf0da-9dab-42b6-94a3-d43ce8d16293' // Log Analytics Contributor
          ]
          deployment: {
            properties: {
              mode: 'incremental'
              template: {
                '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
                contentVersion: '1.0.0.0'
                parameters: {
                  resourceName: { type: 'string' }
                  logAnalytics: { type: 'string' }
                }
                resources: [
                  {
                    type: 'Microsoft.Insights/diagnosticSettings'
                    apiVersion: '2021-05-01-preview'
                    name: 'central-law-export'
                    properties: {
                      workspaceId: '[parameters(\'logAnalytics\')]'
                      logs: [
                        { categoryGroup: 'allLogs', enabled: true }
                      ]
                      metrics: [
                        { category: 'AllMetrics', enabled: true }
                      ]
                    }
                  }
                ]
              }
              parameters: {
                logAnalytics: {
                  value: '[parameters(\'logAnalytics\')]'
                }
              }
            }
          }
        }
      }
    }
  }
}

resource policyAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: 'assign-diag-settings'
  properties: {
    displayName: 'Assign: Deploy diagnostic settings to central LAW'
    policyDefinitionId: policyDef.id
    parameters: {
      logAnalytics: {
        value: workspaceResourceId
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
  location: 'uksouth'
}
