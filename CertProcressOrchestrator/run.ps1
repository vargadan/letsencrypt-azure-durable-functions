param($Context)

$ErrorActionPreference = "Stop"
# Write-Host (Get-Member -InputObject $Context.Input.IsProd )
$IsProdValue = $Context.Input.IsProd.ToString()
Write-Host "Context.Input.IsProd : $IsProdValue"
$IsProd = $IsProdValue -eq "True"
Write-Host "IsProd : $IsProd"

$Domains = Invoke-DurableActivity -FunctionName 'Get-Domains' -Input ("" + $IsProd)
$DomainsDone = @()


$ParallelTasks = foreach ($Domain in $Domains) {
    $RequestProperties = @{
        DomainName = $Domain.Name
        IsProd = $IsProd
    }
    $RequestPropertiesJson = (ConvertTo-Json $RequestProperties)
    Write-Host "RequestPropertiesJson : $RequestPropertiesJson"
    $DomainsDone += $Domain.Name
    Invoke-DurableActivity -FunctionName 'Create-NewCertificate' -Input ("JSON:" + $RequestPropertiesJson) -NoWait
}

$Outputs = Wait-ActivityFunction -Task $ParallelTasks

Write-Host "Outputs : "
Write-Host $Outputs

$DomainsDone