param($Context)

# Write-Host (Get-Member -InputObject $Context.Input.IsProd )
$IsProdString = $Context.Input.IsProd.ToString()
$InputDomainName = $Context.Input.Domain.ToString().Trim()
if ($InputDomainName) {
    Write-Host "Context.Input.Domain : $InputDomainName"
}
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
if ($InputDomainName) {
    $Domains = @(@{"Name" = $InputDomainName})
    Write-Host "Domains[0].Name : $($Domains[0].Name)"
} else {
    Write-Host "Querying Domains"
    $Domains = Invoke-DurableActivity -FunctionName 'Get-Domains' -Input @{ IsProd = $IsProdString; VaultName = $VaultName }
}
Write-Host "Domains :"
Write-Host $Domains

$ParallelTasks = foreach ($Domain in $Domains) {
    $DomainName = $Domain.Name
    $JobStatus = Invoke-DurableActivity -FunctionName 'Create-NewCertificate' -NoWait `
        -Input @{ DomainName = $DomainName; IsProd = $IsProdString; VaultName = $VaultName; Contact = $Contact; SaveInKeyVault = $SaveInKeyVault }
    Write-Host "Invoke-DurableActivity Create-NewCertificate for domain : $DomainName, status : $JobStatus"
    $DomainJobs.Add($DomainName, $JobStatus)
}

if ($ParallelTasks)
{
    # Unlike the legacy Wait-ActivityFunction, Wait-DurableTask propagates activity
    # failures; catch so one failed domain doesn't fail the whole orchestration.
    try {
        $ExecutionOutputs = Wait-DurableTask -Task $ParallelTasks
        Write-Host "Execution Outputs :"
        Write-Host $ExecutionOutputs
    } catch {
        Write-Error "One or more Create-NewCertificate activities failed: $_" -ErrorAction Continue
    }
}

Write-Host "DomainsJobs : "
Write-Host $DomainJobs

$DomainJobs