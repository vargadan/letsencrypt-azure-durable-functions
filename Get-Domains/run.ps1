param($Parameters)

$ErrorActionPreference = "Stop"

Write-Host $Parameters

$IsProd = $Parameters.IsProd -eq "True"
$VaultName = $Parameters.VaultName

Write-Host "Get-Domains (VaultName : $VaultName, IsProd : $IsProd)"

$DaysToExpiry = 30
if (!$IsProd) {
  $DaysToExpiry = 100
}

$Domains = Get-DueDomains -VaultName $VaultName -IsProd $IsProd -DaysToExpiry $DaysToExpiry

$Domains | ForEach-Object { Write-Host "returning : " + $_.Name }

$Domains
