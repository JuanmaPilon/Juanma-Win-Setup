[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepositoryRoot 'modules/SetupHelpers.psm1') -Force

Write-SetupStep 'Scanning configuration import scripts'
$configsRoot = Join-Path $RepositoryRoot 'configs'
$importScripts = @(Get-ChildItem -Path $configsRoot -Filter 'import.ps1' -Recurse -File -ErrorAction SilentlyContinue)

if ($importScripts.Count -eq 0 -or -not $importScripts) {
    Write-SetupStep 'No configuration import scripts were found.'
    return
}

$importTotal = $importScripts.Count
$importIndex = 0

foreach ($importScript in $importScripts) {
    $importIndex++
    $moduleName = $importScript.Directory.Name
    Write-SetupProgress -Activity 'Importing configuration modules' -Status "$moduleName ($importIndex/$importTotal)" -PercentComplete ([int](($importIndex - 1) * 100 / $importTotal))
    Write-SetupStep "Running import script: $($importScript.FullName)"
    try {
        & $importScript.FullName -RepositoryRoot $RepositoryRoot
    }
    catch {
        Write-SetupWarning "Import script failed: $($_.Exception.Message)"
        Write-SetupWarning "Continuing with the next import script."
    }
}

Clear-SetupProgress

Write-SetupStep 'Configuration import stage completed.'
