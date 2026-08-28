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
    [Parameter(Mandatory = $true)][string] $VaultName,
    [Parameter(Mandatory = $true)][string] $DomainName,
    [Parameter(Mandatory = $true)][int] $Days,
    [Parameter(Mandatory = $true)][boolean] $IsProd
  )
  $CertName = Get-CertName -DomainName $DomainName -IsProd $IsProd
  $Cert = Get-AzKeyVaultCertificate -VaultName $VaultName -Name $CertName 
  if (!$Cert -or !$Cert.Enabled) {
    Write-Host "$DomainName : no enabled cert found."
    $True
  } else {
    $Expires = $Cert.Expires
    Write-Host "$DomainName : cert found; will expire at $Expires"
    return $Expires -lt (Get-Date).AddDays($Days)
  }
}

function Get-DueDomains {
  Param (
    [Parameter(Mandatory = $true)][string] $VaultName,
    [Parameter(Mandatory = $true)][boolean] $IsProd,
    [Parameter(Mandatory = $true)][int] $DaysToExpiry
  ) 
  $Domains = Get-AzDnsZone `
    | Where-Object { $_.Tags.ContainsKey("letsencrypt") } `
    | Where-Object { (Get-IfCertIsToExpire -DomainName $_.Name -Days $DaysToExpiry -IsProd $IsProd -VaultName $VaultName) }
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
    $CertPath = "$TemplFolder/$CertName"
    $CertBlob | Get-AzStorageBlobContent -Destination $CertPath | Out-Null
    Write-Host "Blob downloaded to $CertPath"
    $ReturnVal = @{
      "CertPath" = $CertPath
      "Password" = $CertBlob.ICloudBlob.Metadata.Password
    }
  }
  $ReturnVal
}
  
# function Save-CertToStorage  {
#   param (
#     [Parameter(Mandatory = $true)][object] $StorageContext,
#     [Parameter(Mandatory = $true)][string] $ContainerName,
#     [Parameter(Mandatory = $true)][string] $Password,
#     [Parameter(Mandatory = $true)][string] $CertPath,
#     [Parameter(Mandatory = $true)][string] $CertName
#   )
#   $Metadata = @{
#     "Password" = $Password
#   }
#   Set-AzStorageBlobContent -File $CertPath `
#     -Container $ContainerName `
#     -Blob $CertName `
#     -Metadata $Metadata `
#     -Context $StorageContext `
#     -Force
# }

# function Remove-CertFromStorage  {
#   param (
#     [Parameter(Mandatory = $true)][object] $StorageContext,
#     [Parameter(Mandatory = $true)][string] $ContainerName,
#     [Parameter(Mandatory = $true)][string] $CertName
#   )
#   Remove-AzStorageBlob -Container $ContainerName `
#     -Blob $CertName `
#     -Context $StorageContext `
#     -Force
#   Write-Host "Certificate removed from temp storage : $CertName"
# }

# --- Leaf-first PFX repacking ---
# Posh-ACME's bundled BouncyCastle writes PKCS#12 cert bags in hashtable order
# (rmbolger/Posh-ACME#683), so fullchain.pfx may come out with the chain certs
# scrambled. Key Vault and Application Gateway serve the chain verbatim, so the
# PFX must be rebuilt in leaf -> issuer -> ... order before it leaves the activity.

# ships with PowerShell 7 but is not loaded into the session by default
if (-not ('System.Security.Cryptography.Pkcs.Pkcs12Builder' -as [type])) {
  Add-Type -AssemblyName 'System.Security.Cryptography.Pkcs'
}

function Get-SubjectKeyIdHex {
  Param (
    [Parameter(Mandatory = $true)][object] $Cert
  )
  $Ext = $Cert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.14' } | Select-Object -First 1
  if ($Ext -is [System.Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension]) {
    return $Ext.SubjectKeyIdentifier
  }
  return $null
}

function Get-AuthorityKeyIdHex {
  Param (
    [Parameter(Mandatory = $true)][object] $Cert
  )
  $Ext = $Cert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.35' } | Select-Object -First 1
  if (-not $Ext) { return $null }
  try {
    $Aki = [System.Security.Cryptography.X509Certificates.X509AuthorityKeyIdentifierExtension]::new($Ext.RawData, $false)
    $KeyId = $Aki.KeyIdentifier
    if ($null -ne $KeyId) {
      return [System.Convert]::ToHexString($KeyId.ToArray())
    }
  } catch {
    # runtime without the typed AKI extension or unparseable AKI: the caller
    # falls back to subject-name matching
  }
  return $null
}

# In-memory private key (RSA or ECDsa) from the first key bag of a PFX.
# Parses the PKCS#12 structure in managed code: keys attached to X509
# certificates by PFX import are keychain/CSP-backed on macOS/Windows and may
# refuse re-export, while the raw key bag always decrypts.
function Get-PfxPrivateKey {
  Param (
    [Parameter(Mandatory = $true)][byte[]] $PfxBytes,
    [Parameter(Mandatory = $true)][string] $Password
  )
  $Consumed = 0
  $Info = [System.Security.Cryptography.Pkcs.Pkcs12Info]::Decode(
    [System.ReadOnlyMemory[byte]]::new($PfxBytes), [ref] $Consumed, $true)
  foreach ($Safe in $Info.AuthenticatedSafe) {
    if ($Safe.ConfidentialityMode -eq [System.Security.Cryptography.Pkcs.Pkcs12ConfidentialityMode]::Password) {
      $Safe.Decrypt($Password)
    }
    foreach ($Bag in $Safe.GetBags()) {
      $KeyInfo = $null
      $Read = 0
      if ($Bag -is [System.Security.Cryptography.Pkcs.Pkcs12ShroudedKeyBag]) {
        $KeyInfo = [System.Security.Cryptography.Pkcs.Pkcs8PrivateKeyInfo]::DecryptAndDecode(
          $Password, $Bag.EncryptedPkcs8PrivateKey, [ref] $Read)
      } elseif ($Bag -is [System.Security.Cryptography.Pkcs.Pkcs12KeyBag]) {
        $KeyInfo = [System.Security.Cryptography.Pkcs.Pkcs8PrivateKeyInfo]::Decode(
          $Bag.Pkcs8PrivateKey, [ref] $Read, $true)
      }
      if (-not $KeyInfo) { continue }
      $AlgOid = $KeyInfo.AlgorithmId.Value
      $PlainPkcs8 = $KeyInfo.Encode()
      $Read = 0
      switch ($AlgOid) {
        '1.2.840.113549.1.1.1' {
          $Key = [System.Security.Cryptography.RSA]::Create()
          $Key.ImportPkcs8PrivateKey($PlainPkcs8, [ref] $Read)
          return $Key
        }
        '1.2.840.10045.2.1' {
          $Key = [System.Security.Cryptography.ECDsa]::Create()
          $Key.ImportPkcs8PrivateKey($PlainPkcs8, [ref] $Read)
          return $Key
        }
        default { throw "Unsupported private key algorithm OID $AlgOid in PFX" }
      }
    }
  }
  return $null
}

# Cert bags of a PFX in file order, as what a strict TLS consumer sees.
# X509Certificate2Collection.Import is NOT usable for this: on Windows it
# enumerates a cert store whose order is unrelated to the bag order.
function Get-PfxCertBagInfo {
  Param (
    [Parameter(Mandatory = $true)][byte[]] $PfxBytes,
    [Parameter(Mandatory = $true)][string] $Password
  )
  $Consumed = 0
  $Info = [System.Security.Cryptography.Pkcs.Pkcs12Info]::Decode(
    [System.ReadOnlyMemory[byte]]::new($PfxBytes), [ref] $Consumed, $true)
  if ($Info.IntegrityMode -eq [System.Security.Cryptography.Pkcs.Pkcs12IntegrityMode]::Password) {
    if (-not $Info.VerifyMac($Password)) {
      throw "PFX MAC verification failed (wrong password?)"
    }
  }
  $Result = [System.Collections.Generic.List[object]]::new()
  foreach ($Safe in $Info.AuthenticatedSafe) {
    if ($Safe.ConfidentialityMode -eq [System.Security.Cryptography.Pkcs.Pkcs12ConfidentialityMode]::Password) {
      $Safe.Decrypt($Password)
    }
    foreach ($Bag in $Safe.GetBags()) {
      if ($Bag -is [System.Security.Cryptography.Pkcs.Pkcs12CertBag]) {
        $Cert = $Bag.GetCertificate()
        $null = $Result.Add(@{
          Subject    = $Cert.Subject
          Issuer     = $Cert.Issuer
          Thumbprint = $Cert.Thumbprint
        })
        $Cert.Dispose()
      }
    }
  }
  return $Result
}

function Test-PfxLeafFirst {
  Param (
    [Parameter(Mandatory = $true)][string] $PfxPath,
    [Parameter(Mandatory = $true)][string] $Password
  )
  $Bags = @(Get-PfxCertBagInfo -PfxBytes ([System.IO.File]::ReadAllBytes($PfxPath)) -Password $Password)
  if ($Bags.Count -eq 0) { return $false }
  for ($i = 0; $i -lt $Bags.Count - 1; $i++) {
    if ($Bags[$i].Issuer -ne $Bags[$i + 1].Subject) { return $false }
  }
  return $true
}

function Build-LeafFirstPfx {
  Param (
    [Parameter(Mandatory = $true)][string] $PfxPath,
    [Parameter(Mandatory = $true)][string] $Password,
    [Parameter(Mandatory = $true)][System.Security.Cryptography.X509Certificates.X509KeyStorageFlags] $Flags
  )
  $Collection = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
  $Collection.Import($PfxPath, $Password, $Flags)
  $PrivateKey = $null
  try {
    $All = @($Collection)
    $Leaves = @($All | Where-Object { $_.HasPrivateKey })
    if ($Leaves.Count -eq 0) { throw "No private-key entry found in PFX $PfxPath" }
    if ($Leaves.Count -gt 1) {
      Write-Warning "Multiple private-key entries in PFX $PfxPath; using the first one"
    }
    $Leaf = $Leaves[0]

    $Remaining = [System.Collections.Generic.List[object]]::new()
    foreach ($Cert in $All) {
      if (-not [object]::ReferenceEquals($Cert, $Leaf)) { $null = $Remaining.Add($Cert) }
    }

    # walk issuer links from the leaf: AKI/SKI match first, subject-name fallback
    $Ordered = [System.Collections.Generic.List[object]]::new()
    $Current = $Leaf
    while ($Remaining.Count -gt 0) {
      $Next = $null
      $Aki = Get-AuthorityKeyIdHex -Cert $Current
      if ($Aki) {
        $Hits = @($Remaining | Where-Object { (Get-SubjectKeyIdHex -Cert $_) -eq $Aki })
        if ($Hits.Count -eq 1) { $Next = $Hits[0] }
      }
      if (-not $Next) {
        $Hits = @($Remaining | Where-Object { $_.Subject -eq $Current.Issuer })
        if ($Hits.Count -ge 1) { $Next = $Hits[0] }
      }
      if (-not $Next) { break }
      $null = $Ordered.Add($Next)
      $null = $Remaining.Remove($Next)
      $Current = $Next
    }
    # never drop certs: anything unchainable is appended behind the chain
    foreach ($LeftOver in $Remaining) {
      Write-Warning "PFX cert not part of the issuer chain, appending as-is: $($LeftOver.Subject)"
      $null = $Ordered.Add($LeftOver)
    }

    $PrivateKey = Get-PfxPrivateKey -PfxBytes ([System.IO.File]::ReadAllBytes($PfxPath)) -Password $Password
    if (-not $PrivateKey) { throw "No private key bag found in PFX $PfxPath" }

    # TripleDES/SHA1 PBE: Key Vault import and Application Gateway reject AES-based PBE
    $Pbe = [System.Security.Cryptography.PbeParameters]::new(
      [System.Security.Cryptography.PbeEncryptionAlgorithm]::TripleDes3KeyPkcs12,
      [System.Security.Cryptography.HashAlgorithmName]::SHA1, 2000)
    $LocalKeyId = [System.Security.Cryptography.Pkcs.Pkcs9LocalKeyId]::new($Leaf.GetCertHash())

    $CertContents = [System.Security.Cryptography.Pkcs.Pkcs12SafeContents]::new()
    $LeafBag = $CertContents.AddCertificate($Leaf)
    $null = $LeafBag.Attributes.Add($LocalKeyId)
    foreach ($Cert in $Ordered) {
      $null = $CertContents.AddCertificate($Cert)
    }

    $KeyContents = [System.Security.Cryptography.Pkcs.Pkcs12SafeContents]::new()
    $KeyBag = $KeyContents.AddShroudedKey($PrivateKey, $Password, $Pbe)
    $null = $KeyBag.Attributes.Add($LocalKeyId)

    $Builder = [System.Security.Cryptography.Pkcs.Pkcs12Builder]::new()
    $Builder.AddSafeContentsEncrypted($CertContents, $Password, $Pbe)
    $Builder.AddSafeContentsUnencrypted($KeyContents)
    $Builder.SealWithMac($Password, [System.Security.Cryptography.HashAlgorithmName]::SHA1, 2000)

    return @{
      Bytes          = $Builder.Encode()
      Subjects       = @($Leaf.Subject) + @($Ordered | ForEach-Object { $_.Subject })
      LeafThumbprint = $Leaf.Thumbprint
      CertCount      = 1 + $Ordered.Count
    }
  } finally {
    if ($PrivateKey) { $PrivateKey.Dispose() }
    foreach ($Cert in $Collection) { $Cert.Dispose() }
  }
}

# Rebuilds the PFX at $PfxPath in place with cert bags in leaf-first issuer order.
# The original file is only replaced after the rebuilt PFX passes verification;
# on any failure it throws and leaves the original untouched, so callers can
# treat the repack as best-effort (a misordered chain beats a missed renewal).
function ConvertTo-LeafFirstPfx {
  Param (
    [Parameter(Mandatory = $true)][string] $PfxPath,
    [Parameter(Mandatory = $true)][string] $Password
  )
  $StorageFlags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]
  # EphemeralKeySet avoids temp key containers, but is unsupported on macOS and
  # can block key export on some Windows CSPs: fall back to Exportable alone
  # (keys are cleaned up by the Dispose calls in Build-LeafFirstPfx)
  $FlagSets = @(
    ($StorageFlags::Exportable -bor $StorageFlags::EphemeralKeySet),
    $StorageFlags::Exportable
  )
  $Build = $null
  $LastError = $null
  foreach ($Flags in $FlagSets) {
    try {
      $Build = Build-LeafFirstPfx -PfxPath $PfxPath -Password $Password -Flags $Flags
      break
    } catch {
      $LastError = $_
    }
  }
  if (-not $Build) { throw $LastError }

  # verify the rebuilt PFX before replacing the original file
  $Bags = @(Get-PfxCertBagInfo -PfxBytes $Build.Bytes -Password $Password)
  if ($Bags.Count -ne $Build.CertCount) {
    throw "Repacked PFX has $($Bags.Count) cert bags, expected $($Build.CertCount)"
  }
  if ($Bags[0].Thumbprint -ne $Build.LeafThumbprint) {
    throw "Repacked PFX does not start with the leaf certificate"
  }
  for ($i = 0; $i -lt $Bags.Count - 1; $i++) {
    if ($Bags[$i].Issuer -ne $Bags[$i + 1].Subject) {
      # possible with appended unchainable extras; not fatal, but worth seeing
      Write-Warning "Repacked PFX: cert $($i + 1) ($($Bags[$i + 1].Subject)) does not certify its predecessor ($($Bags[$i].Subject))"
    }
  }
  # confirm the private key survived and still belongs to the leaf
  $CheckCollection = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
  try {
    foreach ($Flags in @($StorageFlags::EphemeralKeySet, $StorageFlags::DefaultKeySet)) {
      try {
        $CheckCollection.Import($Build.Bytes, $Password, $Flags)
        break
      } catch { }
    }
    $KeyCerts = @($CheckCollection | Where-Object { $_.HasPrivateKey })
    if ($KeyCerts.Count -ne 1 -or $KeyCerts[0].Thumbprint -ne $Build.LeafThumbprint) {
      throw "Private key did not survive the PFX repack"
    }
  } finally {
    foreach ($Cert in $CheckCollection) { $Cert.Dispose() }
  }

  $TempPath = "$PfxPath.leaffirst"
  [System.IO.File]::WriteAllBytes($TempPath, $Build.Bytes)
  Move-Item -Path $TempPath -Destination $PfxPath -Force
  Write-Host ("PFX repacked leaf-first: " + ($Build.Subjects -join ' -> '))
}
