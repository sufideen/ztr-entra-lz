using '../main.bicep'

param environment = 'prod'
param location = 'uksouth'
param breakGlassGroupId = readEnvironmentVariable('BREAK_GLASS_GROUP_ID', '')

param commonTags = {
  project: 'zero-trust-landing-zone'
  environment: 'prod'
  controlFramework: 'ISO27001-CyberEssentials'
  managedBy: 'bicep-ci'
  costCentre: 'platform-security'
}
