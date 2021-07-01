function Get-CertName {
  Param (
    [Parameter(Mandatory = $true)][string] $DomainName,
    [Parameter(Mandatory = $true)][boolean] $IsProd
  )
  $CertName = "le-" + $DomainName.Replace('.','-')
  if (!$IsProd) {
    $CertName = "staging-" + $CertName
  }
  return $CertName
}
function Get-IfCertIsToExpire {
  Param (
    [Parameter(Mandatory = $true)][string] $DomainName,
    [Parameter(Mandatory = $true)][int] $Days,
    [Parameter(Mandatory = $true)][boolean] $IsProd
  )
  $CertName = Get-CertName -DomainName $DomainName -IsProd $IsProd
  $Cert = Get-AzKeyVaultCertificate -VaultName $VaultName -Name $CertName 
  Write-Host $Cert
  if (!$Cert -or !$Cert.Enabled) {
    $True
  } else {
    return $Cert.Expires -lt (Get-Date).AddDays($Days)
  }
}

function Get-DueDomains {
  Param (
    [Parameter(Mandatory = $true)][string] $VaultName,
    [Parameter(Mandatory = $true)][boolean] $IsProd
  ) 
  $Domains = Get-AzDnsZone `
    | Where-Object { $_.Tags.ContainsKey("letsencrypt") } `
    | Where-Object { (Get-IfCertIsToExpire -DomainName $_ -Days 20 -IsProd $IsProd) }
  $Domains
}

function Get-CertFromStorage {
  param (
    [Parameter(Mandatory = $true)][object] $StorageContext,
    [Parameter(Mandatory = $true)][string] $ContainerName,
    [Parameter(Mandatory = $true)][string] $CertName
  )
  $TemplFolder = $env:TEMP 
  Write-Host "Container: $ContainerName ; Blob: $CertName ; Context: $StorageContext"
  $CertBlob = Get-AzStorageBlob -Container $ContainerName -Blob $CertName -Context $StorageContext 
  $ReturnVal = $null
  if ($CertBlob) {
    $CertPath = "$TemplFolder/$CertName.pfx"
    $CertBlob | Get-AzStorageBlobContent -Destination $CertPath
    Write-Host "Blob downloaded to $CertPath"
    $ReturnVal = @{
      "CertPath" = $CertPath
      "Password" = $CertBlob.ICloudBlob.Metadata.Password
    }
  }
  $ReturnVal
}
  
function Save-CertToStorage  {
  param (
    [Parameter(Mandatory = $true)][object] $StorageContext,
    [Parameter(Mandatory = $true)][string] $ContainerName,
    [Parameter(Mandatory = $true)][string] $Password,
    [Parameter(Mandatory = $true)][string] $CertPath,
    [Parameter(Mandatory = $true)][string] $CertName
  )
  $Metadata = @{
    "Password" = $Password
  }
  Set-AzStorageBlobContent -File $CertPath `
    -Container $ContainerName `
    -Blob $CertName `
    -Metadata $Metadata `
    -Context $StorageContext `
    -Force
}

function Remove-CertFromStorage  {
  param (
    [Parameter(Mandatory = $true)][object] $StorageContext,
    [Parameter(Mandatory = $true)][string] $ContainerName,
    [Parameter(Mandatory = $true)][string] $CertName
  )
  Remove-AzStorageBlob -Container $ContainerName `
    -Blob $CertName `
    -Context $StorageContext `
    -Force
  Write-Host "Certificate removed from temp storage : $CertName"
}
