# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every "cold start" of your Function App.
# "cold start" occurs when:
#
# * A Function App starts up for the very first time
# * A Function App starts up after being de-allocated due to inactivity
#
# You can define helper functions, run commands, or specify environment variables
# NOTE: any variables defined that are not environment variables will get reset after the first execution

# Authenticate with Azure PowerShell using MSI.
# Remove this if you are not planning on using MSI or Azure PowerShell.
if ($env:MSI_SECRET) {
    Disable-AzContextAutosave -Scope Process | Out-Null
    Connect-AzAccount -Identity
    Write-Host "AZ login successful"
}

# Uncomment the next line to enable legacy AzureRm alias in Azure PowerShell.
# Enable-AzureRmAlias

# You can also define functions or aliases that can be referenced in any of your PowerShell functions.

try {
    Import-Module Az.Accounts
    Import-Module Az.KeyVault
    Import-Module Az.Dns
    Import-Module Az.Storage
    Import-Module Posh-ACME
} catch {
    Write-Error $_
}

try {
    Import-Module $PSScriptRoot/Module/CertAutomation.psm1 -Force
} catch {
    Write-Error $_
}