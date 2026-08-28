param($Context)

# The standalone Durable SDK preserves $null input values (e.g. Domain when the
# route has no domain segment), so use null-safe [string] casts instead of .ToString()
$IsProdString = [string]$Context.Input.IsProd
$InputDomainName = ([string]$Context.Input.Domain).Trim()
if ($InputDomainName) {
    Write-Host "Context.Input.Domain : $InputDomainName"
}
Write-Host "Context.Input.IsProd : $IsProdString"
$IsProd = $IsProdString -eq "True"
Write-Host "IsProd : $IsProd"
$SaveInKeyVault = [string]$Context.Input.SaveInKeyVault
$ForceString = [string]$Context.Input.Force

$Contact = [string]$Context.Input.Contact
$VaultName = [string]$Context.Input.VaultName

Write-Host "Contact: $Contact"
Write-Host "VaultName: $VaultName"
Write-Host "Force: $ForceString"

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

# The tasks must be collected AND awaited: the standalone SDK only dispatches
# awaited tasks (the legacy SDK ran scheduled-but-unawaited activities anyway).
$ParallelTasks = @()
$TaskDomainNames = @()
foreach ($Domain in $Domains) {
    $DomainName = $Domain.Name
    $Task = Invoke-DurableActivity -FunctionName 'Create-NewCertificate' -NoWait `
        -Input @{ DomainName = $DomainName; IsProd = $IsProdString; VaultName = $VaultName; Contact = $Contact; SaveInKeyVault = $SaveInKeyVault; Force = $ForceString }
    Write-Host "Invoke-DurableActivity Create-NewCertificate for domain : $DomainName"
    $ParallelTasks += $Task
    $TaskDomainNames += $DomainName
    $DomainJobs.Add($DomainName, "scheduled")
}

if ($ParallelTasks)
{
    # Unlike the legacy Wait-ActivityFunction, Wait-DurableTask propagates activity
    # failures; catch so one failed domain doesn't fail the whole orchestration.
    try {
        $ExecutionOutputs = @(Wait-DurableTask -Task $ParallelTasks)
        Write-Host "Execution Outputs :"
        Write-Host $ExecutionOutputs
        # results keep task order ($null entries preserved for empty outputs)
        for ($i = 0; $i -lt $TaskDomainNames.Count; $i++) {
            $DomainJobs[$TaskDomainNames[$i]] = [string]$ExecutionOutputs[$i]
        }
    } catch {
        Write-Error "One or more Create-NewCertificate activities failed: $_" -ErrorAction Continue
    }
}

Write-Host "DomainsJobs : "
Write-Host $DomainJobs

$DomainJobs