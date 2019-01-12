# Custom RP based on Azure Function with PowerShell Core

The **mainTemplate.json** will deploy the following:

- Resource Group
- Storage account for diagnostics/metrics
- Application Insights instance
- App Function - using PowerShell Core
- App Function Web plan
- MSI assigned at resource group - or subscription scope

## Deployment

Since this is a subscription level deployment, you must deploy using either CLI or PowerShell:

PowerShell:

```powershell
New-AzureRmDeployment -Name myRp -Location <location> -TemplateUri "https://raw.githubusercontent.com/krnese/customRps/master/CustomRp-Prototypes/AzureFunctionApp/mainTemplate.json"
```

CLI
```cli
az deployment create -n myRp -l <location> --template-uri "https://raw.githubusercontent.com/krnese/customRps/master/CustomRp-Prototypes/AzureFunctionApp/mainTemplate.json"
```
