// Entra ID groups this repo's other Graph modules currently expect as
// already-existing Object IDs, supplied as parameters (breakGlassGroupId in
// conditionalAccess.bicep, primaryApprovers in pim.bicep's role management
// policies, SponsorGroupId in scripts/graph/create-access-package.ps1).
// Authoring them here means those consumers can eventually reference this
// module's outputs instead of a manually-created, manually-documented
// Object ID.
//
// STATUS: NOT wired into main.bicep, same disabled-but-present pattern as
// conditionalAccess.bicep and pim.bicep - see docs/graph-resources.md for
// why Microsoft.Graph/* resources don't compile on this pipeline's Bicep
// CLI today (BCP407). Until that's resolved, these groups are created via
// the Microsoft Graph portal/PowerShell directly and their Object IDs
// passed as parameters, same as every other Graph-plane resource here.

extension microsoftGraph

@description('Display name suffix distinguishing this environment''s test groups from production, e.g. "sandbox"')
param environment string = 'sandbox'

resource breakGlassGroup 'Microsoft.Graph/groups@v1.0' = {
  displayName: 'ZTLZ Break-Glass Emergency Access - ${environment}'
  description: 'Excluded from every Conditional Access policy - see docs/break-glass-procedure.md. Membership: the 2 dedicated break-glass accounts only.'
  mailEnabled: false
  mailNickname: 'ztlz-breakglass-${environment}'
  securityEnabled: true
  groupTypes: []
}

resource contractorTestGroup 'Microsoft.Graph/groups@v1.0' = {
  displayName: 'ZTLZ Test - Contractor Persona - ${environment}'
  description: 'Sponsor/approver group for contractor-persona Access Packages created by scripts/graph/create-test-personas.ps1. Test-only - not a production sponsor group.'
  mailEnabled: false
  mailNickname: 'ztlz-test-contractor-${environment}'
  securityEnabled: true
  groupTypes: []
}

resource vendorTestGroup 'Microsoft.Graph/groups@v1.0' = {
  displayName: 'ZTLZ Test - Vendor Persona - ${environment}'
  description: 'Sponsor/approver group for vendor-persona Access Packages created by scripts/graph/create-test-personas.ps1. Test-only - not a production sponsor group.'
  mailEnabled: false
  mailNickname: 'ztlz-test-vendor-${environment}'
  securityEnabled: true
  groupTypes: []
}

output breakGlassGroupId string = breakGlassGroup.id
output contractorTestGroupId string = contractorTestGroup.id
output vendorTestGroupId string = vendorTestGroup.id
