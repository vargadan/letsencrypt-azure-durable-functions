using namespace System.Net

param($Request, $TriggerMetadata)

$ErrorActionPreference = "Stop"

$SaveInKeyVault = $True
if ($Request.Query.SaveInKeyVault -eq "False") {
  $SaveInKeyVault = $False
}

# force=true skips the temp-storage cache so a genuinely new cert is requested
$Force = $False
if ($Request.Query.Force -eq "True") {
  $Force = $True
}

$OrchestratorInput = @{
  IsProd = $Request.Params.Stage -eq "Prod"
  Domain= $Request.Params.Domain
  Contact = $env:CONTACT_EMAIL
  VaultName = $env:VAULT_NAME
  SaveInKeyVault = $SaveInKeyVault.ToString()
  Force = $Force.ToString()
}

$InstanceId = Start-DurableOrchestration -Input $OrchestratorInput -FunctionName 'CertProcressOrchestrator'
Write-Host "Started orchestration with ID = '$InstanceId'"

$Response = New-DurableOrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId

Write-Host $Response

Push-OutputBinding -Name Response -Value $Response