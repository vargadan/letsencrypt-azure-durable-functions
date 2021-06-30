param($IsProd)

$VaultName = $env:VAULT_NAME

$IsProd = $IsProd -eq "True"

Write-Host "Get-Domains (VaultName : $VaultName, IsProd : $IsProd)"

$Domains = Get-DueDomains -VaultName $VaultName -IsProd $IsProd

Write-Host "Domains"
Write-Host $Domains

$Domains