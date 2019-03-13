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

    Write-Information "CustomRp will trigger a request"

    # Write to the Azure Functions log stream.
    Write-Information ("Starting function aadAddGroupMembers...") 



$username = "b2ceb57c-0f34-4f80-8a29-a43d20947bec" 
$password = Convertto-SecureString "foo" -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username,$password)
$tenant = "d6ad82f3-42af-4a15-ac1e-49e6c08f624e"
$subscription = "0a938bc2-0bb8-4688-bd37-9964427fe0b0"
Connect-AzAccount -credential $credential -tenant $tenant -serviceprincipal -Subscription $subscription
    
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
    if ([string]::IsNullOrEmpty($request.body.properties) -or [string]::IsNullOrEmpty($request.body.properties.userPrincipalName) -or [string]::IsNullOrEmpty($request.body.properties.groupId))
    {
        Write-Host "Bad request..."
        Write-Information ("Error parsing request body")
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $badRequestStatusCode
            Body = $jsonErrorResponseBody
            ContentType = $ContentType
        })
    }
    else
    {
        Write-Information ("RP will attempt to add following user in AAD group: `n $($request.body.properties.userPrincipalName)")
        
            $UserPrincipalName = $request.body.properties.userPrincipalName
            Write-Information ("$UserPrincipalName")

            $AADGroup = $request.body.properties.groupId
            Write-Information ("$AADGroup")
        
            $UserExistenceCondition = Get-AzAdUser -UserPrincipalName $UserPrincipalName
            $GroupExistenceCondition = Get-AzADGroup -ObjectId $AADGroup
            if([string]::IsNullOrEmpty($UserExistenceCondition.UserPrincipalName) -or [string]::IsNullOrEmpty($GroupExistenceCondition.id))
            {
                Write-Host "Bad request..."
                Write-Information ("Error parsing request body")
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = $badRequestStatusCode
                    Body = $jsonErrorResponseBody
                    ContentType = $ContentType
                })
            }
            else
            {
                Write-Output "$($UserExistenceCondition.id) is present exists in AAD"
                Write-Output "$($GroupExistenceCondition.id) is present in AAD"
                $MemberExistenceCondition = Get-AzADGroupMember -GroupObjectId $GroupExistenceCondition.id | Where-Object {$_.id -eq $UserExistenceCondition.Id}

                if ([string]::IsNullOrEmpty($MemberExistenceCondition.DisplayName))
                {
                    Write-Output "User doesn't exists - will add him/her"
                    Add-AzADGroupMember -MemberUserPrincipalName $UserExistenceCondition.UserPrincipalName -TargetGroupObjectId $GroupExistenceCondition.Id
                    $AddMember = Get-AzAdGroupMember -GroupObjectId $GroupExistenceCondition.Id | where-object {$_.UserPrincipalName -eq $UserExistenceCondition.UserPrincipalName}
                    $jsonAddMember = $AddMember | ConvertTo-Json -depth 100
$jsonSuccessResponseBody = @"
{
    "id": $($id),
    "type": $($type),
    "name": $($name),
        "properties": $($jsonAddMember)
}
"@
                    Write-Information ("User $($UserExistenceCondition.Id) added to AAD Group!")
                    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = $okStatusCode
                        Body = $jsonSuccessResponseBody
                        ContentType = $ContentType
                    })
                }
                else
                {
                    Write-Output "User is already member of the group!"
                    $jsonMember = $MemberExistenceCondition | ConvertTo-Json -Depth 100
$jsonSuccessResponseBody = @"
{
    "id": $($id),
    "type": $($type),
    "name": $($name),
        "properties": $($jsonMember)
}
"@
                    Write-Information ("User $($UserExistenceCondition.Id) added to AAD Group!")
                    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = $okStatusCode
                        Body = $jsonSuccessResponseBody
                        ContentType = $ContentType
                    })                    
                }
            }                
    }