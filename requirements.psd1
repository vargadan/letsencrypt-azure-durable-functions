# This file enables modules to be automatically managed by the Functions service.
# See https://aka.ms/functionsmanageddependency for additional information.
#
# NOTE: Managed dependencies only support exact versions ('5.5.2') or major
# wildcards ('5.*') - 'major.minor.*' is NOT supported and fails dependency install.
@{
    'Az.Accounts' = '5.5.2'
    'Az.KeyVault' = '6.6.0'
    'Az.Dns' = '2.2.0'
    'Az.Storage' = '9.7.2'
    'Posh-ACME' = '4.34.0'
    'AzureFunctions.PowerShell.Durable.SDK' = '2.3.0'
}
