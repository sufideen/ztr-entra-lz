targetScope = 'subscription'

// Custom, least-privilege roles for the three non-employee personas.
// All are assigned via PIM as ELIGIBLE only (see modules/pim.bicep) -
// none of these should ever be a permanent (active) assignment.

resource contractorReader 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, 'contractor-scoped-reader')
  properties: {
    roleName: 'Contractor Scoped Reader'
    description: 'Read-only access to assigned resource group for time-boxed contractor engagements. No secrets/keys list permission.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          '*/read'
        ]
        notActions: [
          'Microsoft.KeyVault/vaults/secrets/read'
          'Microsoft.KeyVault/vaults/keys/read'
        ]
        dataActions: []
        notDataActions: [
          'Microsoft.KeyVault/vaults/secrets/getSecret/action'
        ]
      }
    ]
    assignableScopes: [
      subscription().id
    ]
  }
}

resource vendorAppDeployer 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, 'vendor-scoped-app-deployer')
  properties: {
    roleName: 'Vendor Scoped App Deployer'
    description: 'Deploy/update permissions scoped to a single vendor-facing App Service / Container App. No network, IAM, or policy write.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.Web/sites/*'
          'Microsoft.App/containerApps/*'
          'Microsoft.Insights/components/*'
        ]
        notActions: [
          'Microsoft.Web/sites/publish/Action'
        ]
        dataActions: []
        notDataActions: []
      }
    ]
    assignableScopes: [
      subscription().id
    ]
  }
}

resource pipelineDeployRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, 'pipeline-scoped-contributor')
  properties: {
    roleName: 'Pipeline Scoped Contributor'
    description: 'CI/CD workload identity role - Contributor minus RBAC/policy/subscription-level writes. Used by GitHub Actions OIDC federated credential only, never by a human.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          '*'
        ]
        notActions: [
          'Microsoft.Authorization/*/write'
          'Microsoft.Authorization/*/delete'
          'Microsoft.Blueprint/blueprintAssignments/write'
          'Microsoft.Blueprint/blueprintAssignments/delete'
        ]
        dataActions: []
        notDataActions: []
      }
    ]
    assignableScopes: [
      subscription().id
    ]
  }
}

output roleDefinitionIds array = [
  contractorReader.id
  vendorAppDeployer.id
  pipelineDeployRole.id
]
