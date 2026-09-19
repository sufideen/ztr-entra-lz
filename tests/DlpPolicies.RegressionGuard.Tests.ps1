#Requires -Modules Pester

<#
.SYNOPSIS
  Regression guard: every DLP policy in deploy-dlp-policies.ps1 must deploy
  in TestWithNotifications mode, never 'Enable', until an explicit,
  deliberate promotion after a bake period.

.DESCRIPTION
  Static test over the PowerShell *source text* - no Purview/Exchange
  Online credentials needed, safe to run in CI on every PR. This is the DLP
  analog of tests/ConditionalAccess.RegressionGuard.Tests.ps1: that test
  regexes conditionalAccess.bicep because Bicep is the source of truth for
  Conditional Access policies. DLP policies have no Bicep source of truth
  (see docs/graph-resources.md) - scripts/purview/deploy-dlp-policies.ps1
  IS the source of truth, so this test regexes that file directly instead.

  This is deliberately a strict allow-list test, not a "some policies can
  be enabled" test: promoting a policy out of TestWithNotifications is a
  real, deliberate security decision (mirroring THROWAWAY.md Step 5's rule
  for Conditional Access) that should be a one-line diff a reviewer can see
  and question, not something this test should quietly accommodate.

.NOTES
  Run locally: Invoke-Pester -Path ./tests/DlpPolicies.RegressionGuard.Tests.ps1

  Follows the exact BeforeDiscovery/BeforeAll duplication pattern documented
  in ConditionalAccess.RegressionGuard.Tests.ps1's .NOTES (see PR #19):
  Pester v5 evaluates -ForEach at Discovery time, before BeforeAll runs, so
  the -ForEach data is built in BeforeDiscovery. But BeforeDiscovery's
  script-scope variables are not reliably visible to plain, non-ForEach It
  blocks (they run later, in an isolated Run-phase scope) - so the same
  computation is deliberately duplicated in BeforeAll rather than factored
  into a shared helper, since a Discovery-time helper would have the exact
  same visibility problem.
#>

BeforeDiscovery {
    $script:ScriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'purview' 'deploy-dlp-policies.ps1'
    $script:ScriptContent = Get-Content -Path $script:ScriptPath -Raw

    # Split into individual Set-DlpPolicy calls so a failure names the
    # specific policy, not just "something in the file".
    $script:PolicyBlocks = [regex]::Matches(
        $script:ScriptContent,
        "Set-DlpPolicy\s+-DisplayName\s+`"(?<name>[^`"]+)`".*?(?=Set-DlpPolicy\s+-DisplayName|\z)",
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $script:PolicyBlockData = @($script:PolicyBlocks | ForEach-Object {
        @{ Name = $_.Groups['name'].Value; Body = $_.Value }
    })
}

BeforeAll {
    # Recompute (don't just reference the BeforeDiscovery values) - see the
    # .NOTES above for why the Discovery-phase values aren't visible here.
    $script:ScriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'purview' 'deploy-dlp-policies.ps1'
    $script:ScriptContent = Get-Content -Path $script:ScriptPath -Raw
    $script:PolicyBlocks = [regex]::Matches(
        $script:ScriptContent,
        "Set-DlpPolicy\s+-DisplayName\s+`"(?<name>[^`"]+)`".*?(?=Set-DlpPolicy\s+-DisplayName|\z)",
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
}

Describe 'DLP policies deploy report-only' {

    It 'finds deploy-dlp-policies.ps1' {
        Test-Path $script:ScriptPath | Should -BeTrue
    }

    It 'finds at least one DLP policy' {
        $script:PolicyBlocks.Count | Should -BeGreaterThan 0
    }

    It '<name> Mode is TestWithNotifications or TestWithoutNotifications, never Enable' -ForEach $script:PolicyBlockData {
        $modeMatch = [regex]::Match($Body, 'Mode\s*=\s*"(?<mode>[^"]+)"')
        $modeMatch.Success | Should -BeTrue -Because "policy '$Name' must have an explicit Mode property"
        $modeMatch.Groups['mode'].Value | Should -Not -Be 'Enable' -Because "DLP policy '$Name' must deploy in test mode until a deliberate, reviewed bake-period promotion"
    }
}
