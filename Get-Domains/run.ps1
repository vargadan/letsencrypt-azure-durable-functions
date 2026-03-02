param($Parameters)

$ErrorActionPreference = "Stop"

Write-Host $Parameters

$IsProd = $Parameters.IsProd -eq "True"
$VaultName = $Parameters.VaultName

Write-Host "Get-Domains (VaultName : $VaultName, IsProd : $IsProd)"

$DaysToExpiry = $env:DAYS_TO_EXPIRY ?? 30

$Domains = Get-DueDomains -VaultName $VaultName -IsProd $IsProd -DaysToExpiry $DaysToExpiry

$Domains | ForEach-Object { Write-Host "returning : " + $_.Name }

$Domains
