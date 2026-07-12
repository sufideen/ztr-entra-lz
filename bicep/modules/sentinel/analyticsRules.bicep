targetScope = 'resourceGroup'

@description('Name of the Log Analytics workspace Sentinel is onboarded to')
param workspaceName string

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource ruleImpossibleTravel 'Microsoft.SecurityInsights/alertRules@2024-03-01' = {
  scope: law
  name: guid('impossible-travel-rule')
  kind: 'Scheduled'
  properties: {
    displayName: 'Impossible travel sign-in (Zero Trust)'
    description: 'Detects sign-ins from the same identity from geographically distant locations within an implausible time window.'
    severity: 'High'
    enabled: true
    query: '''
SigninLogs
| where ResultType == 0
| project TimeGenerated, UserPrincipalName, Location = tostring(LocationDetails.city), IPAddress
| sort by UserPrincipalName, TimeGenerated asc
| serialize
| extend PrevLocation = prev(Location, 1), PrevUser = prev(UserPrincipalName, 1), PrevTime = prev(TimeGenerated, 1)
| where UserPrincipalName == PrevUser and Location != PrevLocation
| where TimeGenerated - PrevTime < 2h
'''
    queryFrequency: 'PT1H'
    queryPeriod: 'PT2H'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionEnabled: false
    suppressionDuration: 'PT5H'
    tactics: ['InitialAccess']
    techniques: ['T1078']
  }
}

resource rulePimActivationAnomaly 'Microsoft.SecurityInsights/alertRules@2024-03-01' = {
  scope: law
  name: guid('pim-activation-outside-hours')
  kind: 'Scheduled'
  properties: {
    displayName: 'PIM role activation outside business hours'
    description: 'Flags privileged role activations outside 07:00-19:00 UK time, or without an approval record — a Cyber Essentials / ISO27001 A.9 access-control control point.'
    severity: 'Medium'
    enabled: true
    query: '''
AuditLogs
| where OperationName == "Add member to role completed (PIM activation)"
| extend hour = datetime_part("hour", TimeGenerated)
| where hour < 7 or hour > 19
'''
    queryFrequency: 'PT1H'
    queryPeriod: 'PT1H'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionEnabled: false
    suppressionDuration: 'PT5H'
    tactics: ['PrivilegeEscalation']
    techniques: ['T1078']
  }
}

resource ruleCaPolicyChange 'Microsoft.SecurityInsights/alertRules@2024-03-01' = {
  scope: law
  name: guid('ca-policy-modified')
  kind: 'Scheduled'
  properties: {
    displayName: 'Conditional Access policy modified outside pipeline'
    description: 'Any CA policy change not attributable to the pipeline service principal — CA policies should only ever change via Bicep + PR review.'
    severity: 'High'
    enabled: true
    query: '''
AuditLogs
| where Category == "Policy" and OperationName has "Conditional Access"
| where InitiatedBy.app.appId != "REPLACE_WITH_PIPELINE_SP_APP_ID"
'''
    queryFrequency: 'PT15M'
    queryPeriod: 'PT15M'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionEnabled: false
    suppressionDuration: 'PT5H'
    tactics: ['DefenseEvasion', 'Persistence', 'PrivilegeEscalation']
    techniques: ['T1556']
  }
}

resource ruleGuestOutsideAccessPackage 'Microsoft.SecurityInsights/alertRules@2024-03-01' = {
  scope: law
  name: guid('guest-created-outside-access-package')
  kind: 'Scheduled'
  properties: {
    displayName: 'Guest account created outside Access Package workflow'
    description: 'Detects any B2B guest invite not correlated with an Entitlement Management Access Package request — enforces "no standing guest accounts" policy.'
    severity: 'Medium'
    enabled: true
    query: '''
AuditLogs
| where OperationName == "Invite external user"
| join kind=leftanti (
    AuditLogs
    | where OperationName == "Request approved (Entitlement Management)"
) on $left.TargetResources[0].id == $right.TargetResources[0].id
'''
    queryFrequency: 'PT1H'
    queryPeriod: 'PT1H'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionEnabled: false
    suppressionDuration: 'PT5H'
    tactics: ['InitialAccess', 'Persistence']
    techniques: ['T1136']
  }
}
