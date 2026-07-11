// Deployed via the Microsoft Graph Bicep extension (preview).
// If your Bicep CLI / pipeline runner doesn't yet support `extension microsoftGraph`,
// use the fallback script: scripts/graph/deploy-conditional-access.ps1
// which applies the same policies idempotently via Microsoft.Graph PowerShell.
// See docs/graph-resources.md for the decision record on this.

extension microsoftGraph

@description('Object ID of the break-glass emergency access group — always excluded from CA')
param breakGlassGroupId string

// --- Baseline: require MFA for everyone, block legacy auth ---
resource caBaselineMfa 'Microsoft.Graph/conditionalAccessPolicies@v1.0' = {
  displayName: 'CA001 - Baseline - Require MFA for all users'
  state: 'enabled'
  conditions: {
    users: {
      includeUsers: ['All']
      excludeGroups: [breakGlassGroupId]
    }
    applications: {
      includeApplications: ['All']
    }
    clientAppTypes: ['all']
  }
  grantControls: {
    operator: 'OR'
    builtInControls: ['mfa']
  }
}

resource caBlockLegacyAuth 'Microsoft.Graph/conditionalAccessPolicies@v1.0' = {
  displayName: 'CA002 - Baseline - Block legacy authentication'
  state: 'enabled'
  conditions: {
    users: {
      includeUsers: ['All']
      excludeGroups: [breakGlassGroupId]
    }
    applications: {
      includeApplications: ['All']
    }
    clientAppTypes: ['exchangeActiveSync', 'other']
  }
  grantControls: {
    operator: 'OR'
    builtInControls: ['block']
  }
}

// --- Employees: compliant/hybrid-joined device required for privileged apps ---
resource caEmployeeDeviceCompliance 'Microsoft.Graph/conditionalAccessPolicies@v1.0' = {
  displayName: 'CA010 - Employees - Require compliant device for admin portals'
  state: 'enabled'
  conditions: {
    users: {
      includeUsers: ['All']
      excludeGroups: [breakGlassGroupId]
    }
    applications: {
      includeApplications: [
        '00000002-0000-0ff1-ce00-000000000000' // example: Azure management app ID (replace with tenant's)
      ]
    }
    clientAppTypes: ['all']
  }
  grantControls: {
    operator: 'AND'
    builtInControls: ['mfa', 'compliantDevice']
  }
}

// --- Contractors / vendors (guest users): MFA + Terms of Use + browser-only session ---
resource caGuestSessionControl 'Microsoft.Graph/conditionalAccessPolicies@v1.0' = {
  displayName: 'CA020 - Guests - MFA, ToU, browser-only, no persistent session'
  state: 'enabled'
  conditions: {
    users: {
      includeGuestsOrExternalUsers: {
        guestOrExternalUserTypes: 'b2bCollaborationGuest,b2bCollaborationMember'
        externalTenants: {
          membershipKind: 'all'
        }
      }
    }
    applications: {
      includeApplications: ['All']
    }
    clientAppTypes: ['browser']
  }
  grantControls: {
    operator: 'AND'
    builtInControls: ['mfa']
    termsOfUse: [
      'vendor-contractor-tou'
    ]
  }
  sessionControls: {
    persistentBrowser: {
      isEnabled: true
      mode: 'never'
    }
    signInFrequency: {
      isEnabled: true
      type: 'hours'
      value: 4
    }
  }
}

// --- Risk-based: sign-in risk medium/high -> block ---
resource caSignInRisk 'Microsoft.Graph/conditionalAccessPolicies@v1.0' = {
  displayName: 'CA030 - Risk-based - Block on medium/high sign-in risk'
  state: 'enabled'
  conditions: {
    users: {
      includeUsers: ['All']
      excludeGroups: [breakGlassGroupId]
    }
    applications: {
      includeApplications: ['All']
    }
    clientAppTypes: ['all']
    signInRiskLevels: ['high', 'medium']
  }
  grantControls: {
    operator: 'OR'
    builtInControls: ['block']
  }
}

// --- Workload identities: block interactive sign-in on service principals outside known IP ranges ---
resource caWorkloadIdentity 'Microsoft.Graph/conditionalAccessPolicies@v1.0' = {
  displayName: 'CA040 - Workload identity - restrict to CI/CD egress ranges'
  state: 'enabledForReportingButNotEnforced' // start in report-only, promote after bake period
  conditions: {
    clientApplications: {
      includeServicePrincipals: ['ServicePrincipalsInMyTenant']
    }
    applications: {
      includeApplications: ['All']
    }
    locations: {
      includeLocations: ['All']
      excludeLocations: ['AllTrusted']
    }
  }
  grantControls: {
    operator: 'OR'
    builtInControls: ['block']
  }
}
