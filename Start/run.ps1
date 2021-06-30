using namespace System.Net

param($Request, $TriggerMetadata)

$ErrorActionPreference = "Stop"
$OrchestratorInput = @{
  IsProd = $Request.Params.Stage -eq "Prod"
}

$InstanceId = Start-NewOrchestration -Input $OrchestratorInput -FunctionName 'CertProcressOrchestrator' 
Write-Host "Started orchestration with ID = '$InstanceId'"

$Response = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId

Write-Host $Response

Push-OutputBinding -Name Response -Value $Response