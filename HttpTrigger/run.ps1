using namespace System.Net

param($Request, $TriggerMetadata)

$ErrorActionPreference = "Stop"

$SaveInKeyVault = $True
if ($Request.Query.SaveInKeyVault -eq "False") {
  $SaveInKeyVault = $False
}

$OrchestratorInput = @{
  IsProd = $Request.Params.Stage -eq "Prod"
  Domain= $Request.Params.Domain
  Contact = $env:CONTACT_EMAIL
  VaultName = $env:VAULT_NAME
  SaveInKeyVault = $SaveInKeyVault.ToString()
}

$InstanceId = Start-NewOrchestration -Input $OrchestratorInput -FunctionName 'CertProcressOrchestrator' 
Write-Host "Started orchestration with ID = '$InstanceId'"

$Response = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId

Write-Host $Response

Push-OutputBinding -Name Response -Value $Response