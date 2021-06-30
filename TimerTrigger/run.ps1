# Input bindings are passed in via param block.
param($Timer)

$ErrorActionPreference = "Stop"

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

$START_URL = $env:TIMER_TRIGGER_START_URL

Write-Host "Calling Http Endpoint To Start Durable Function..."
$Response = Invoke-WebRequest -Method GET -Body "" -Uri $START_URL 

$Uris = $Response.Content | ConvertFrom-Json

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

$Uris