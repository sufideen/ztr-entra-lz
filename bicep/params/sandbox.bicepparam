using '../main.bicep'

// Targets the throwaway M365 Developer Program tenant + Azure free
// subscription described in THROWAWAY.md. Safe to deploy CA policies
// in enforced mode here once tested in report-only mode first - it's
// not a real business tenant.

param environment = 'sandbox'
param location = 'uksouth'
param breakGlassGroupId = readEnvironmentVariable('BREAK_GLASS_GROUP_ID', '')

param commonTags = {
  project: 'zero-trust-landing-zone'
  environment: 'sandbox'
  controlFramework: 'ISO27001-CyberEssentials'
  managedBy: 'bicep-ci'
  purpose: 'portfolio-poc-throwaway'
}
