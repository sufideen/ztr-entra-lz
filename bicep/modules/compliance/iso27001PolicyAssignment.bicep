targetScope = 'subscription'

// Built-in ISO 27001:2013 regulatory-compliance initiative definition ID -
// same GUID in every tenant, published by Microsoft.
var iso27001InitiativeId = '/providers/Microsoft.Authorization/policySetDefinitions/89c6cddc-1c73-4ac1-b19c-54d1a15a42f2'

resource policyAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: 'assign-iso27001-2013'
  properties: {
    displayName: 'Assign: ISO 27001:2013 regulatory compliance'
    description: 'Evaluates the subscription against the built-in ISO 27001:2013 initiative for audit-readiness evidence - see docs/compliance-mapping.md.'
    policyDefinitionId: iso27001InitiativeId
  }
  identity: {
    type: 'SystemAssigned'
  }
  location: 'uksouth'
}

output policyAssignmentId string = policyAssignment.id
