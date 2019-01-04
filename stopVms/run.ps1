using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$ErrorActionPreference = 'stop'

try {

# Authenticating to ARM using MSI and preparing RPC valid reponse

    Write-Information "CustomRp will trigger a request"

    # Write to the Azure Functions log stream.
    Write-Information ("Starting function CustomRps...") 

    if ($null -ne $Env:MSI_ENDPOINT)
    {
        Write-Information ("Using MSI for ARM authentication")
        $TokenAuthURI = $env:MSI_ENDPOINT + "?resource=https://management.azure.com/&api-version=2017-09-01"
        $TokenResponse = Invoke-RestMethod -Method Get -Headers @{"Secret"="$env:MSI_SECRET"} -Uri $tokenAuthURI

        # Get connection context from Function variables
        $Website_owner_name = $env:WEBSITE_OWNER_NAME
        $SubscriptionId = $Website_owner_name.Substring(0,$Website_owner_name.IndexOf('+'))
        $AppName = $env:APPSETTING_WEBSITE_SITE_NAME
        Login-AzAccount -SubscriptionId $SubscriptionId -AccessToken $TokenResponse.access_token `
                            -AccountId $AppName      
    }
    # Preparing RPC valid response for Azure Resource Manager
    
    $ContentType = 'application/json'
    $okStatusCode = "Ok"
    $badRequestStatusCode = "BadRequest"
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
    
$jsonResponseBody = @"
{
    "id": $($id),
    "type": $($type),
    "name": $($name),
        "properties": $($resourceProperties)
}
"@
Write-Information $jsonResponsebody

    # RP Logic
    if ([string]::IsNullOrEmpty($request.body.properties) -or [string]::IsNullOrEmpty($request.body.properties.vmResourceId))
    {
        Write-Host "Bad request..."
        Write-Information ("Error parsing request body")
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $badRequestStatusCode
            Body = $jsonResponseBody
            ContentType = $ContentType
        })
    }
    else
    {
        Write-Information ("Preparing to stop/start the following VM: `n $($request.body.properties.vmResourceId)")

        Try {
            $VMToStop = Get-AzResource -ResourceId $Request.body.properties.vmResourceId
            $VmRg = $VMToStop.ResourceGroupName
            $VmName = $VmToStop.Name

            Stop-AzVm -Name $VMName -ResourceGroupName $VmRg -Force
            Write-Information ("VM $($VmName) has now stopped")
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = $okStatusCode
                Body = $jsonResponseBody
                ContentType = $ContentType
            })
        }
        Catch {
            Write-Host "Bad request..."
            Write-Information ("Unable to stop VM")
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = $badRequestStatusCode
                Body = $jsonResponseBody
                ContentType = $ContentType
            })
        }
    }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $okStatusCode
    Body = $jsonResponseBody
    ContentType = $ContentType
})
}
Catch
{
    Write-Information ("Failed beyond recognition")
    {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = "500"
        Body = $_.Exception.Message
    })
}
}