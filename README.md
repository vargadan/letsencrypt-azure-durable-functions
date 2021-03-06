# LetsEncrypt certificate automation with Azure Durable Functions and Azure Key-Vault

LetsEncrypt certification request automation for Azure DNS and KeyVault with Azure Durable Functions
The orchestrated process is the following:
1. Get-Domians activity funtion: Query Azure DNS for domains that have a "letsencrypt" tag and also query their associated certificates from the key-vault; filter those whose certificate is about to expire or does not exist yet
2. Create-NewCertificate activity function: this function is executed in parallel for each domain returned by Get-Domains. What it does:
   1. Checks if a cert (pfx) file has been saved in the temporary blob storage; this is needed for idempotance as if you retry too often you may reach the rate limit of the LetsEncrypt service
   2. If there is no saved cert in the temp storage then it starts the ACME request process and saves the request in the temp storage
   3. If there is a saved cert in the temp storage then it reads that and saved to the local temp filesystem.
   4. Imports the cetificate into the Azure Key Vault
   5. Deletes certifiace files from local temp file system as well as from the temporary blob storage

## Triggers:
- HttpTrigger: this starts the orchestration function at route start/{stage:alpha?}; if the stage param is "prod" the the Create-NewCertificate will use the productive LetsEncrypt instance and create production ready certs; otherwise it will only use the staging instance and will create certs of its staging CA which is for testing.
- TimerTrigger: this actually calls the http trigger at the configured interval

## Configuration:
### Necessary Env Vars
- _VAULT_NAME_: the name of the vault where certificates are saved
- _CONTACT_EMAIL_: email of cert contact to where letsencrypt sends notifications (i.e. expiry)
- _TIMER_TRIGGER_START_URL_: The URL that the timer trigger should invoke
- _WEBSITE_CONTENTAZUREFILECONNECTIONSTRING_: this env var is automatically created and holds a connection string to the storage account associated with the durable function project; it is also read by the application because the temporary storage blob container (called "temp-storage") needs to be created in this storage account.
- FUNCTIONS_WORKER_PROCESS_COUNT and PSWorkerInProcConcurrencyUpperBound set to values greated than 1 (e.g. 4) to allow for parallel execution of activity functions
### Access Control
- Either a system or user assigned __managed identity__ needs to be assigned with the function application and it needs to have the below roles
   - __DNS Zone Contributor__ for the subscription or the resource groups holding the DNS zones, so that it can query domain names and place challenges into dns records
   - __Certificate List, Get and Import__ permission in the key vault (as set by the env var VAULT_NAME), so tha it can query certificates that are about to expire and import the new certificate into the key-vault

