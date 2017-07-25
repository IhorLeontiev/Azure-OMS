<#
Goal: Export Notification Alerts from OMS Log Analytics
Script: Export_Alerts.ps1
Author: Jose Fehse (@overcastinfo) 
Data: 06/02/2016
#>
param (
[string]$outfilename="alerts.xml"
)
$tenants=armclient login

$tenantinfo=@{}
$temp=@()
$NumberofTenants=([regex]::Matches($tenants, "User:" )).count
if ($NumberofTenants -gt 1)
{
    foreach ($line in $tenants)     {
        if ($line.Length -gt 4)         {
            if ($line.Substring(0,5) -eq "User:")        {
                $user=([regex]::Matches($line,[regex] '(?is)(?<=\bUser: \b).*?(?=\b, Tenant\b)')).value
                $tenantid=([regex]::Matches($line,[regex] '(?is)(?<=\bTenant: \b).*?(?=\b [(]\b)')).value
                $domain=([regex]::Matches($line,[regex] '(?is)(?<=[(]).*?(?=[)])')).value
                $temp+=(,@($user,$tenantid,$domain))
            }
        }
    }
}
$searchCategory = ""
$api = "2015-03-20"
if ($NumberofTenants -gt 1) {
    $uiPrompt = "Select a tenant.`n"
    $count=0
    for ($count=0;$count -lt $NumberofTenants;$count++)    {
        $uiPrompt+="$($count+1). " + $temp[$count][2] + " - Id: " + $temp[$count][1]+"`n"
    }
    $answer=(Read-Host -Prompt $uiPrompt) -1    
    Write-Host "Setting armclient token to $($temp[$answer][1])"
    armclient token "$($temp[$answer][1])" 
}
$allSubscriptions = armclient get /subscriptions?api-version=$api | out-string | ConvertFrom-Json
$uiPrompt = "Select a subscription.`n"
$count = 1
foreach ($subscription in $allSubscriptions.value) {
    $uiPrompt += "$count. " + $subscription.displayName + " (" + $subscription.subscriptionId + ")`n" 
    $count++
}

$answer = (Read-Host -Prompt $uiPrompt) - 1 
$subscription = $allSubscriptions.value[$answer].subscriptionId 

$allWorkspaces = armclient get /subscriptions/$subscription/providers/Microsoft.OperationalInsights/workspaces?api-version=$api | out-string | ConvertFrom-Json
"<OMSAlerts>" | Out-File $outfilename
foreach ($workspace in $allWorkspaces.value) {
    Write-Debug "$workspace.name / $workspace.location"
    $url = $workspace.id + "/savedsearches?api-version=$api"
    $savedSearches = armclient get $url | out-string | ConvertFrom-Json
    Write-host "Saved searches found:`r`n"
   
    foreach ($query in $savedSearches.value) {
        
        $schedules=armclient get  "$($query.id.Trim())/schedules?api-version=$api" | Out-String | ConvertFrom-Json
        if ($schedules -ne $null)
        {
            $actions= armclient get "$($schedules.id.trim())/actions?api-version=$api" | Out-String | ConvertFrom-Json
            if ($actions.value.properties.Type -eq "Alert")
            {
                $newline="<OMSAlert><Query><![CDATA["
                Write-host "Found schedule with Alert for $($query.properties.DisplayName) - $($query.properties.Category) category on Workspace: $($workspace.name)"
                
                $etag = $query.etag | ConvertTo-Json
                $properties = ($query.properties) | ConvertTo-Json -Compress
                $properties=$properties.Replace("""","'")
                Write-Host """{'etag': '$etag', 'properties': $properties }"""
                $newline+="{'properties': $properties }" 
                $newline+="]]></Query>"
                
                $newline+="<Schedule><![CDATA["
                $etag = $schedules.etag | ConvertTo-Json
                $properties= ($schedules.properties) | ConvertTo-Json -Compress
                $properties=$properties.Replace("""","'")
                Write-Host """{'etag': '$etag', 'properties': $properties }"""
                $newline+="{'properties': $properties }" 
                $newline+="]]></Schedule>"

                $newline+="<Action><![CDATA["
                $etag = $actions.value.etag | ConvertTo-Json
                $properties= ($actions.value.properties) | ConvertTo-Json -Compress
                $properties=$properties.Replace("""","'")
                Write-Host """{'etag': '$etag', 'properties': $properties }"""
                $newline+="{'properties': $properties }"
               
                $newline+="]]></Action></OMSAlert>"
                $newline | Out-File $outfilename -Append    
            }
        }
    }
}
"</OMSAlerts>" | Out-File $outfilename -Append
