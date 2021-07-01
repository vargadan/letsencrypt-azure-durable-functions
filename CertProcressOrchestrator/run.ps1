param($Context)

# Write-Host (Get-Member -InputObject $Context.Input.IsProd )
$IsProdValue = $Context.Input.IsProd.ToString()
Write-Host "Context.Input.IsProd : $IsProdValue"
$IsProd = $IsProdValue -eq "True"
Write-Host "IsProd : $IsProd"

$DomainJobs = @{}
$DomainJobs.Add("IsProd", $IsProd)
$Domains = Invoke-DurableActivity -FunctionName 'Get-Domains' -Input @{ IsProd = $IsProdValue }

$ParallelTasks = foreach ($Domain in $Domains) {
    $RequestProperties = @{ DomainName = $Domain.Name; IsProd = $IsProd }
    # $RequestPropertiesJson = (ConvertTo-Json $RequestProperties)
    Write-Host $RequestPropertiesJson 
    $JobStatus = Invoke-DurableActivity -FunctionName 'Create-NewCertificate' -Input $RequestProperties -NoWait
    $DomainJobs.Add($Domain.Name, $JobStatus)
}

$ExecutionOutputs = Wait-ActivityFunction -Task $ParallelTasks

Write-Host "Execution Outputs : "
Write-Host $ExecutionOutputs
Write-Host "DomainsJobs : "
Write-Host $DomainsJobs

$DomainsJobs