<#
Goal: Import Notification Alerts to OMS Log Analytics workspace
Script: Import_Alerts.ps1
Author: Jose Fehse (@overcastinfo) 
Data: 06/02/2016
#>

#Functions
#Function: Get-Filename
#Source: http://blogs.technet.com/b/heyscriptingguy/archive/2009/09/01/hey-scripting-guy-september-1.aspx
#
Function Get-FileName($initialDirectory)
{   
 [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
 Out-Null

 $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
 $OpenFileDialog.initialDirectory = $initialDirectory
 $OpenFileDialog.filter = "All files (*.*)| *.*"
 $OpenFileDialog.ShowDialog() | Out-Null
 $OpenFileDialog.filename
} #end function Get-FileName
#EndFunctions

#Main script
$api = "2015-03-20"
#logs in and get tenant info.
#$tenants=armclient login

$temp=@()
$NumberofTenants=([regex]::Matches($tenants, "User:" )).count
#if you have more than one tenant, you'll need to pick one:
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

#getSubscription

$allSubscriptions = armclient get /subscriptions?api-version=$api | out-string | ConvertFrom-Json

$uiPrompt = "Select a subscription.`n"
$count = 1
foreach ($subscription in $allSubscriptions.value) {
    $uiPrompt += "$count. " + $subscription.displayName + "(" + $subscription.subscriptionId + ")`n" 
    $count++
}

$answer = (Read-Host -Prompt $uiPrompt) - 1 
$subscription = $allSubscriptions.value[$answer].subscriptionId 

#getWorkspace

$allWorkspaces = armclient get /subscriptions/$subscription/providers/Microsoft.OperationalInsights/workspaces?api-version=$api | out-string | ConvertFrom-Json
$uiPrompt = "Select a workspace.`n"
$count = 1

foreach ($workspace in $allWorkspaces.value) {
    $uiPrompt += "$count. " + $workspace.name + "(" + $workspace.id + ")`n" 
    $count++
}

$answer = (Read-Host -Prompt $uiPrompt) - 1 
$workspace = $allWorkspaces.value[$answer].name  

#determines resource group name
$WSId=$allWorkspaces.value[$answer].id
$tempvar=$WSId.Substring($WSId.IndexOf("resourcegroups")+15,$WSId.Length-$WSId.IndexOf("resourcegroups")-15)
$resourcegroup=$tempvar.Substring(0,$tempvar.IndexOf("/"))

$searchidprefix="igsearch"
$scheduleprefix="igschedule"
$actionprefix="igalert"

$xmfilename=Get-FileName -initialDirectory "."

#list of search queries
if ($xmfilename -ne "")
{
    try {
        [xml]$searchlist=get-content $xmfilename
       
    }
    catch {
        Write-host "Error reading file $xmfilename"
        break
    }
    $myId = 0
    foreach ($OMSAlert in $searchList.OMSAlerts.OMSAlert) {
        $searchId=$searchidprefix+$myId
        $scheduleId=$scheduleprefix+$myId
        $actionid=$actionprefix+$myId
        $baseurl="/subscriptions/$subscription/resourceGroups/$resourcegroup/providers/Microsoft.OperationalInsights/workspaces/$workspace"
        
         #create search query
	    $queryurl = "/subscriptions/$subscription/resourceGroups/$resourcegroup/providers/Microsoft.OperationalInsights/workspaces/$workspace/savedsearches/$searchId" + "?api-version=$api"
        armclient put $queryurl $OMSAlert.Query.InnerText

	    #assign schedule
	    $scheduleJson = $OMSAlert.Schedule.InnerText
        armclient put "/subscriptions/$subscription/resourceGroups/$resourcegroup/providers/Microsoft.OperationalInsights/workspaces/$workspace/savedSearches/$searchId/schedules/$($scheduleId)?api-version=$api" $scheduleJson

	    #assign action
      
        $actionjson = $OMSAlert.Action.InnerText
        armclient put "/subscriptions/$subscription/resourceGroups/$resourcegroup/providers/Microsoft.OperationalInsights/workspaces/$workspace/savedSearches/$searchId/schedules/$scheduleId/actions/$($actionid)?api-version=$api" $actionjson
        
        $myId++
    }
}
else
{
    write-host "File not selected."
}

[xml]$searchList=Get-Content .\Alerts.xml

