param($Parameters)

$ErrorActionPreference = "Stop"

Write-Host "Parameters : $Parameters"

$DomainName = $Parameters.DomainName
Write-Host "Parameters : $DomainName"
$IsProd = $Parameters.IsProd -eq "True"
$SaveInKeyVault = $Parameters.SaveInKeyVault -eq "True"
$Contact = $Parameters.Contact
$CertName = Get-CertName -DomainName $DomainName -IsProd $IsProd
$VaultName = $Parameters.VaultName

$DomainNames=$DomainName, "*.$DomainName"

$StorageContext = New-AzStorageContext -ConnectionString $env:WEBSITE_CONTENTAZUREFILECONNECTIONSTRING
$BlobContainerName =  "temp-storage"

$SavedCertData = $null
try {
    $SavedCertData = Get-CertFromStorage -StorageContext $StorageContext -ContainerName $BlobContainerName -CertName "$CertName-fullchain.pfx" -ErrorAction "Ignore"
} catch {
    Write-Host "Error Downloading Certificate :  $_"
}

$CertData = $null

if ($SavedCertData) {
    Write-Host "Using certificate restored from temp storage"
    $CertData = @{
        CertPath = $SavedCertData.CertPath
        Password = $SavedCertData.Password
    }
} else {
    Write-Host "Requesting new crertificate from LetsEncript CA"
    Write-Host "DomainName  : $DomainName"
    Write-Host "IsProd      : $IsProd"
    Write-Host "CertName    : $CertName"
    Write-Host "Contact     : $Contact"
    Write-Host "VaultName   : $VaultName"
    Write-Host "DomainNames : $DomainNames"
    $Password = ( -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count 30  | ForEach-Object {[char]$_}) )
    $PasswordLength = $Password.Length
    Write-Host "Pfx Cert Password Length   : $PasswordLength"
    $AzSubscriptionId = $(Get-AzContext).Subscription.Id
    Write-Host "SubscriptionId   : $AzSubscriptionId"
    $AzToken = $(Get-AzAccessToken).Token
    $azParams = @{
        AZSubscriptionId=$AzSubscriptionId
        AZAccessToken=$AzToken
    }
    
    $DirectoryUrl = 'LE_PROD'
    if (!$IsProd) {
        $DirectoryUrl = 'LE_STAGE'
    }
    Write-Host "DirectoryUrl     : $DirectoryUrl"
    $LEResult = New-PACertificate $DomainNames -AlwaysNewKey -Contact $Contact -DnsPlugin Azure -PluginArgs $azParams -AcceptTOS -DirectoryUrl $DirectoryUrl -Force -PfxPass $Password -verbose
    Write-Host "Certificate generated : $LEResult"
    Get-Member -InputObject $LEResult
    $CertData = @{
        CertPath = $LEResult.PfxFullChain
        Password = $Password
    }
    $CertPath = $CertData.CertPath 
    Write-Host "Saving Cert and Key files for $CertName in temp storage from $CertPath"
    Set-AzStorageBlobContent -File $LEResult.PfxFullChain -Container $BlobContainerName -Blob "$CertName-fullchain.pfx" -Metadata @{ "Password" = $Password; "DomainName" =  $DomainName } -Context $StorageContext -Force
    Set-AzStorageBlobContent -File $LEResult.PfxFile -Container $BlobContainerName -Blob "$CertName.pfx" -Metadata @{ "Password" = $Password; "DomainName" =  $DomainName } -Context $StorageContext -Force
    Set-AzStorageBlobContent -File $LEResult.FullChainFile -Container $BlobContainerName -Blob "$CertName-fullchain.cer" -Metadata @{ "DomainName" =  $DomainName } -Context $StorageContext -Force
    Set-AzStorageBlobContent -File $LEResult.ChainFile -Container $BlobContainerName -Blob "$CertName-chain.cer" -Metadata @{ "DomainName" =  $DomainName } -Context $StorageContext -Force
    Set-AzStorageBlobContent -File $LEResult.CertFile -Container $BlobContainerName -Blob "$CertName.cer" -Metadata @{ "DomainName" =  $DomainName } -Context $StorageContext -Force
    Set-AzStorageBlobContent -File $LEResult.KeyFile -Container $BlobContainerName -Blob "$CertName.key" -Metadata @{ "DomainName" =  $DomainName } -Context $StorageContext -Force
}

if (!$CertData) {
    Write-Host "$CertName : Neither saved nor new certificate found!"
    $null
} elseif ($SaveInKeyVault) {
    Write-Host "Saving Certificate in Key-Vault : $VaultName"
    $CertPath = $CertData.CertPath
    $Password = $CertData.Password
    $CertTags = @{
        Password=$Password
        DomainName=$DomainName
        WildCard='TRUE'
    }
    $Certpw = $Password | ConvertTo-SecureString -AsPlainText -Force
    Write-Host "Uploading certificate $CertName to key-vault $VaultName from $CertPath"
    Import-AzKeyVaultCertificate -VaultName $VaultName -Name $CertName -FilePath $CertPath -Password $Certpw -Tag $CertTags
    Write-Host "Certificate uploaded : $CertName"
    Remove-Item -Force $CertPath
    Write-Host "Certificate file deleted : $CertPath"
    # Remove-CertFromStorage -StorageContext $StorageContext -ContainerName $BlobContainerName -CertName $CertName -ErrorAction "Ignore"
    $CertName 
} else {
    Write-Host "$CertName : Not saved in keyvault, certificate file left in temporary storage!"
    $CertName 
}
