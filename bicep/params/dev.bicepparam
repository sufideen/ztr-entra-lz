using '../main.bicep'

param environment = 'dev'
param location = 'uksouth'
param connectivitySubscriptionId = readEnvironmentVariable('CONNECTIVITY_SUB_ID', '')
param identitySubscriptionId = readEnvironmentVariable('IDENTITY_SUB_ID', '')
param breakGlassGroupId = readEnvironmentVariable('BREAK_GLASS_GROUP_ID', '')

param commonTags = {
  project: 'zero-trust-landing-zone'
  environment: 'dev'
  controlFramework: 'ISO27001-CyberEssentials'
  managedBy: 'bicep-ci'
}
