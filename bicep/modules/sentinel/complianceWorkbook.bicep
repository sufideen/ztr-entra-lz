targetScope = 'resourceGroup'

@description('Azure region')
param location string

@description('Resource ID of the central Log Analytics workspace')
param workspaceResourceId string

var workbookDisplayName = 'Zero Trust Landing Zone - Compliance Evidence'

var serializedWorkbook = string({
  version: 'Notebook/1.0'
  items: [
    {
      type: 1
      content: {
        json: '## Zero Trust Landing Zone - Compliance Evidence\n\nISO 27001 / Cyber Essentials evidence surface: the four Sentinel analytics rules deployed by `analyticsRules.bicep`, plus PIM activation and guest-lifecycle summaries. See `docs/compliance-mapping.md` for the full control mapping.'
      }
      name: 'text - intro'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'SecurityAlert\n| where AlertName == "Impossible travel sign-in (Zero Trust)"\n| summarize Count = count() by bin(TimeGenerated, 1d)\n| sort by TimeGenerated desc'
        size: 0
        title: 'Impossible travel sign-in - alerts over time'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
      }
      name: 'query - impossible travel'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'AuditLogs\n| where OperationName == "Add member to role completed (PIM activation)"\n| extend hour = datetime_part("hour", TimeGenerated)\n| summarize Activations = count() by OutsideBusinessHours = (hour < 7 or hour > 19)'
        size: 0
        title: 'PIM role activation - business hours summary'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
      }
      name: 'query - pim activation anomaly'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'SecurityAlert\n| where AlertName == "Conditional Access policy modified outside pipeline"\n| project TimeGenerated, AlertName, Severity, Description\n| sort by TimeGenerated desc'
        size: 0
        title: 'Conditional Access policy changes outside pipeline'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
      }
      name: 'query - ca policy change'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'AuditLogs\n| where OperationName == "Invite external user"\n| summarize GuestInvitesRaised = count() by bin(TimeGenerated, 7d)\n| sort by TimeGenerated desc'
        size: 0
        title: 'Guest lifecycle - external invites raised'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
      }
      name: 'query - guest lifecycle'
    }
  ]
  fallbackResourceIds: [
    workspaceResourceId
  ]
})

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid('ztlz-compliance-evidence-workbook')
  location: location
  kind: 'shared'
  properties: {
    displayName: workbookDisplayName
    serializedData: serializedWorkbook
    category: 'sentinel'
    sourceId: workspaceResourceId
  }
}

output workbookId string = workbook.id
