<#
.SYNOPSIS
    Runs PSRule for Azure against the Bicep templates the same way CI does.

.DESCRIPTION
    `Assert-PSRule` needs the standalone Bicep CLI to expand .bicep files, but
    it does not know how to find the copy that `az bicep install` puts under
    the Azure CLI's own folder - that's what produces:

        [ERROR] Bicep CLI can not be found. Consider installing Bicep or
        setting the PSRULE_AZURE_BICEP_PATH environment variable to resolve
        this issue.

    This script locates (or installs) that Bicep CLI, points PSRule at it via
    PSRULE_AZURE_BICEP_PATH for the current session, and then runs
    Assert-PSRule with the same module/options the CI pipeline uses
    (see .github/workflows/deploy.yml and psrule/ps-rule.yaml).

.EXAMPLE
    .\scripts\local\Invoke-PSRule.ps1
#>
[CmdletBinding()]
param(
    [string]$InputPath = (Join-Path $PSScriptRoot '..\..\bicep'),
    [string]$Option = (Join-Path $PSScriptRoot '..\..\psrule\ps-rule.yaml')
)

# Deliberately not setting $ErrorActionPreference = 'Stop' globally: PSRule
# uses non-terminating warnings internally (e.g. "no matching rules found"
# for module files that aren't a deployable template on their own), and
# forcing -Stop here previously made Assert-PSRule abort its scan silently
# after the first one, reporting a false-clean "Rules processed: 0" instead
# of an error or real results.

# Resolve to a clean absolute path - PSRule's file globbing doesn't
# expand literal ".." segments the way Get-ChildItem does, so a raw
# Join-Path result silently matches zero files instead of erroring.
$InputPath = (Resolve-Path $InputPath).ProviderPath
$Option = (Resolve-Path $Option).ProviderPath

function Find-BicepCli {
    # az bicep install places the binary under ~/.azure/bin
    $azBicep = Join-Path $HOME '.azure/bin/bicep'
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        $azBicep += '.exe'
    }
    if (Test-Path $azBicep) {
        return $azBicep
    }

    $onPath = Get-Command bicep -ErrorAction SilentlyContinue
    if ($onPath) {
        return $onPath.Source
    }

    return $null
}

$bicepPath = Find-BicepCli
if (-not $bicepPath) {
    Write-Host 'Bicep CLI not found - installing via az bicep install...'
    az bicep install
    $bicepPath = Find-BicepCli
}

if (-not $bicepPath) {
    throw 'Could not locate or install the Bicep CLI. Install it manually (az bicep install) and re-run this script.'
}

Write-Host "Using Bicep CLI at $bicepPath"
$env:PSRULE_AZURE_BICEP_PATH = $bicepPath

if (-not (Get-Module -ListAvailable -Name PSRule.Rules.Azure)) {
    throw 'PSRule.Rules.Azure module is not installed. Run: Install-Module -Name PSRule.Rules.Azure -Scope CurrentUser -Repository PSGallery'
}


# Don't pass -Format here: it overrides psrule/ps-rule.yaml's `input.format:
# Bicep` and PSRule can't auto-detect .bicep/.bicepparam by extension,
# which silently produces "Rules processed: 0" instead of real results.
# Assert-PSRule already throws a terminating error on rule failures on its
# own, so no explicit -ErrorAction is passed here either.
Assert-PSRule -Module PSRule.Rules.Azure -InputPath (Get-ChildItem -Path $InputPath -Include "*.bicep","*.bicepparam" -Recurse | Select-Object -ExpandProperty FullName) -Option $Option



