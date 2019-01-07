<#
.SYNOPSIS
    This sample RP based on PS requires the following Az PowerShell Core modules present in your function:
    - Az.Resources
    - Az.Accounts
    - Az.Compute

.PARAMETER Request
    The request body in json format that is sent into the function.
.PARAMETER TriggerMetadata
    Required. Information about what triggered the function.
#>
using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$ErrorActionPreference = 'stop'

# Authenticating to ARM using MSI and preparing RPC valid reponse
Write-Information 'CustomRp will trigger a request'

# Write to the Azure Functions log stream.
Write-Information 'Starting function vmAction...'

if ($null -ne $Env:MSI_ENDPOINT)
{
    Write-Information 'Using MSI for ARM authentication'
    $TokenAuthURI = $env:MSI_ENDPOINT + '?resource=https://management.azure.com/&api-version=2017-09-01'
    $TokenResponse = Invoke-RestMethod -Uri $tokenAuthURI -Method Get -Headers @{
        Secret = $env:MSI_SECRET
    }

    # Get connection context from Function variables
    $Website_owner_name = $env:WEBSITE_OWNER_NAME
    $SubscriptionId = $Website_owner_name.Substring(0,$Website_owner_name.IndexOf('+'))
    $AppName = $env:APPSETTING_WEBSITE_SITE_NAME
    Connect-AzAccount -SubscriptionId $SubscriptionId -AccessToken $TokenResponse.access_token -AccountId $AppName
}

# Preparing RPC valid response for Azure Resource Manager
$ContentType = 'application/json'
$okStatusCode = 'Ok'
$badRequestStatusCode = 'BadRequest'
$resourceProperties = $request.body.properties | ConvertTo-Json -Depth 100
$uri = $request.Url

class RPC {
    [string] static GetSubScription ([uri]$uri) {
        return $uri.Segments[3].TrimEnd('/')
    }

    [string] static GetCleanedUri ([uri]$uri) {
        return $uri.Segments.Where{$_ -ne 'api/'} -join ''
    }

    [string] static GetProviderPath ([uri]$uri) {
        $startIndex = $uri.Segments.IndexOf('Microsoft.CustomProviders/')
        $endIndex = $startIndex + 3
        return ($uri.Segments[$startIndex..$endIndex] -join '').TrimEnd('/')
    }

    [string] static GetResourceName ([uri]$uri) {
        return $uri.Segments[-1].TrimEnd('/')
    }
}

$id = [RPC]::GetCleanedUri($uri) | ConvertTo-Json
$name = [RPC]::GetResourceName($uri) | ConvertTo-Json
$type = [RPC]::GetProviderPath($uri) | ConvertTo-Json

$jsonSuccessResponseBody = @"
{
    "id": $($id),
    "type": $($type),
    "name": $($name),
        "properties": $($resourceProperties)
}
"@

$jsonErrorResponseBody = @"
{
    "id": $($id),
    "type": $($type),
    "name": $($name),
        "properties": $($badRequestStatusCode)
}
"@

# RP Logic
if ([string]::IsNullOrEmpty($request.body.properties) -or [string]::IsNullOrEmpty($request.body.properties.vmResourceId))
{
    Write-Host 'Bad request...'
    Write-Information 'Error parsing request body'
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $badRequestStatusCode
        Body = $jsonErrorResponseBody
        ContentType = $ContentType
    })
}
else
{
    Write-Information "Preparing to stop/start the following VM: `n $($request.body.properties.vmResourceId)"

        $VMToStop = Get-AzResource -ResourceId $Request.body.properties.vmResourceId
        $VmRg = $VMToStop.ResourceGroupName
        $VmName = $VmToStop.Name

        Stop-AzVm -Name $VMName -ResourceGroupName $VmRg -Force
        Write-Information "VM $VmName has now stopped"
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $okStatusCode
            Body = $jsonSuccessResponseBody
            ContentType = $ContentType
        })
}
