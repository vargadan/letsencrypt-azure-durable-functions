param($Context)

# Write-Host (Get-Member -InputObject $Context.Input.IsProd )
$IsProdString = $Context.Input.IsProd.ToString()
$DomainName = $Context.Input.Domain
Write-Host "Context.Input.IsProd : $IsProdString"
$IsProd = $IsProdString -eq "True"
Write-Host "IsProd : $IsProd"
$SaveInKeyVault = $Context.Input.SaveInKeyVault.ToString()

$Contact = $Context.Input.Contact.ToString()
$VaultName = $Context.Input.VaultName.ToString()

Write-Host "Contact: $Contact"
Write-Host "VaultName: $VaultName"

$DomainJobs = @{}
$DomainJobs.Add("IsProd", $IsProd)

$Domains = @()
if (!$DomainName) {
    $Domains = Invoke-DurableActivity -FunctionName 'Get-Domains' -Input @{ IsProd = $IsProdString; VaultName = $VaultName }
} else {
    $Domains = @(@{"Name" = $DomainName})
}
Write-Host "Domains : $Domains"

$ParallelTasks = foreach ($Domain in $Domains) {
    $JobStatus = Invoke-DurableActivity -FunctionName 'Create-NewCertificate' -NoWait `
        -Input @{ DomainName = $Domain.Name; IsProd = $IsProdString; VaultName = $VaultName; Contact = $Contact; SaveInKeyVault = $SaveInKeyVault }
    Write-Host "Invoke-DurableActivity Create-NewCertificate for domain : $DomainName, status : $JobStatus"
    $DomainJobs.Add($DomainName, $JobStatus)
}

if ($ParallelTasks)
{
    $ExecutionOutputs = Wait-ActivityFunction -Task $ParallelTasks
    Write-Host "Execution Outputs : "
    Write-Host $ExecutionOutputs

}

Write-Host "DomainsJobs : "
Write-Host $DomainsJobs

$DomainsJobs