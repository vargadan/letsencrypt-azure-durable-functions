param($Parameters)

Write-Host $Parameters

$IsProd = $Parameters.IsProd -eq "True"

Write-Debug "Get-Domains (VaultName : $VaultName, IsProd : $IsProd)"

$Domains = Get-DueDomains -VaultName $VaultName -IsProd $IsProd

$Domains | ForEach-Object { Write-Host $_.Name }

$Domains