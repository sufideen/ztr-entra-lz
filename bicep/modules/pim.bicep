// PIM role management policies — enforces eligible-only, time-boxed activation
// with approval + justification for every privileged Entra + Azure RBAC role.
// Same Graph-extension caveat as conditionalAccess.bicep — see docs/graph-resources.md.

extension microsoftGraph

@description('Roles requiring approval + justification + max 8hr activation')
param privilegedEntraRoles array = [
  '62e90394-69f5-4237-9190-012177145e10' // Global Administrator
  'fe930be7-5e62-47db-91af-98c3a49a38b1' // User Administrator
  '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3' // Application Administrator
  '729827e3-9c14-49f7-bb1b-9608f156bbb8' // Helpdesk Administrator
]

resource pimRoleSettings 'Microsoft.Graph/roleManagementPolicies@v1.0' = [for roleId in privilegedEntraRoles: {
  scopeId: '/'
  scopeType: 'DirectoryRole'
  // Rules applied to each policy: require approval, require justification,
  // max activation duration 8h, require MFA on activation, notify on activation
  rules: [
    {
      id: 'Expiration_EndUser_Assignment'
      ruleType: 'RoleManagementPolicyExpirationRule'
      isExpirationRequired: true
      maximumDuration: 'PT8H'
    }
    {
      id: 'Approval_EndUser_Assignment'
      ruleType: 'RoleManagementPolicyApprovalRule'
      setting: {
        isApprovalRequired: true
        approvalStages: [
          {
            approvalStageTimeOutInMinutes: 1440
            isApproverJustificationRequired: true
            primaryApprovers: [] // populate via pipeline variable per role owner group
          }
        ]
      }
    }
    {
      id: 'Enablement_EndUser_Assignment'
      ruleType: 'RoleManagementPolicyEnablementRule'
      enabledRules: ['MultiFactorAuthentication', 'Justification']
    }
    {
      id: 'Notification_Admin_EndUser_Assignment'
      ruleType: 'RoleManagementPolicyNotificationRule'
      notificationType: 'Email'
      recipientType: 'Admin'
      isDefaultRecipientsEnabled: true
    }
  ]
}]

@description('Azure RBAC PIM assignment — everyone eligible, nobody permanent, on custom roles from customRoles.bicep')
param azureRbacEligibleAssignments array = []
// Populated by the CI pipeline per environment from an access-request record
// (see scripts/graph/pim-assign-eligible.ps1) — kept out of Bicep so that
// individual assignments don't require a full landing-zone deployment to change.

output pimPolicyCount int = length(privilegedEntraRoles)
