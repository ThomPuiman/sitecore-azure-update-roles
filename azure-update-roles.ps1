Param(
        [parameter(Mandatory=$true)]
        [string]$csNameCD,
        [parameter(Mandatory=$true)]
        [string]$csNameCE,
        [parameter(Mandatory=$true)]
        [string]$configDir,
        [parameter(Mandatory=$true)]
        [string]$applicationDir,
        [parameter(Mandatory=$true)]
        [string]$subscription,
        [parameter(Mandatory=$true)]
        [string]$storageAccount,
        [parameter(Mandatory=$true)]
        [string]$storageKey,
        $slot = "Production",
        $deploymentLabel = $null
)

$newCDDeployment = $false
$newCEDeployment = $false
$pkgSuffix = "-$((Get-Date).ToString('MMddyyyyhhmmss')).cspkg"
Write-Output "Cloud Service Name for CD: $csNameCD \r\n Cloud Service Name for CE: $csNameCE \r\n Cloud Service Package URL: $csPkgCD \r\n ServiceConfiguration for CD: $csCfgCD \r\n ServiceConfiguration for CE: $csCfgCE"

function LogRule($message, $role)
{
    Write-Output "[$(Get-Date -f "dd-MM-yyyy HH:mm:ss")] $role - $message"
}

function StartUpgrade($serviceName, $config, $csPkg, $role)
{
    LogRule -message "$serviceName - Trying to get the existing Azure Deployment" -role ""
    $deployment = Get-AzureDeployment -ServiceName $serviceName -Slot $slot -ErrorVariable a -ErrorAction silentlycontinue 
    
    If ($deployment.Name -ne $null)
    {
        LogRule -message "$serviceName - Deployment has been found, continuing to upgrade this" -role ""
        LogRule -message "$serviceName - Start upgrading deployment" -role ""
        Set-AzureDeployment -ServiceName $serviceName -Slot $slot -Configuration $config -Package $csPkg -Mode Simultaneous -Upgrade -Label "StagingDeployment"
        LogRule "$serviceName - Upgrade successfully triggered" ""
    }
    Else
    {
        LogRule -message "$serviceName - Deployment not found, creating new deployment" -role ""
        New-AzureDeployment -ServiceName $serviceName -Slot $slot -Configuration $config -Package $csPkg -Label "StagingDeployment"
        if($role -eq "CD"){
            $script:newCDDeployment = $true
        } else {
            $script:newCEDeployment = $true
        }
    }
    return $deployment
}

function AllInstancesRunning($roleInstanceList)
{
    foreach ($roleInstance in $roleInstanceList)
    {
		if ($roleInstance.InstanceStatus -ne "ReadyRole")
        {
            return $false
        }
    }

    return $true
}

function CreateCSPackage($dirToPack, $config)
{
    $cspack = 'C:\Program Files\Microsoft SDKs\Azure\.NET SDK\v2.5\bin\cspack.exe'
    $serviceDefinitionCD = "$config\CDServiceDefinition.csdef"
    $serviceDefinitionCE = "$config\CEServiceDefinition.csdef"
    $cmdCD = """$($serviceDefinitionCD)"" /out:./SitecoreCD$($pkgSuffix) /sites:""SitecoreWebRole"";""SitecoreWebSite"";""$($dirToPack)"" /role:""SitecoreWebRole"";""$($dirToPack)"""
    & $cspack $cmdCD.Split(" ")

    
    $cmdCE = """$($serviceDefinitionCE)"" /out:./SitecoreCE$($pkgSuffix) /sites:""SitecoreWebRole"";""SitecoreWebSite"";""$($dirToPack)"" /role:""SitecoreWebRole"";""$($dirToPack)"""
    & $cspack $cmdCE.Split(" ")

    $container = "sitecore"
    Write-Output "Start uploading packages to storage $($storageAccount)"
    try {
         $context = New-AzureStorageContext -StorageAccountName $storageAccount -StorageAccountKey $storageKey
 
         $prop =  @{"ContentType"="application/octetstream"} 
	     
         #uploading CD package
         Set-AzureStorageBlobContent -Blob "SitecoreCD$($pkgSuffix)" -Container $container -File "SitecoreCD$($pkgSuffix)" -Context $context -Properties $prop -Force
         #uploading CE package
         Set-AzureStorageBlobContent -Blob "SitecoreCE$($pkgSuffix)" -Container $container -File "SitecoreCE$($pkgSuffix)" -Context $context -Properties $prop -Force
    } 
    catch [System.Exception] {
        Write-Output $_.Exception.ToString()
        exit 1
    }
}

CreateCSPackage -dirToPack $applicationDir -config $configDir

LogRule -message "Trying to find subscription" -role ""
#Select Azure subscription
Import-AzurePublishSettingsFile "$($configDir)\Azure.publishsettings"
Select-AzureSubscription $subscription
Set-AzureSubscription –SubscriptionName $subscription -CurrentStorageAccount $storageAccount 

LogRule -message "Subscription found" -role ""

$deploymentCD = StartUpgrade -serviceName $csNameCD -config "$($configDir)\CDServiceConfiguration.cscfg" -csPkg "https://$($storageAccount).blob.core.windows.net/sitecore/SitecoreCD$($pkgSuffix)" -role "CD"
$deploymentCE = StartUpgrade -serviceName $csNameCE -config "$($configDir)\CEServiceConfiguration.cscfg" -csPkg "https://$($storageAccount).blob.core.windows.net/sitecore/SitecoreCE$($pkgSuffix)" -role "CE"

$oldStatusStrCD = @("")
$oldStatusStrCE = @("")

sleep -Seconds 10

$deploymentCD = Get-AzureDeployment -ServiceName $csNameCD -Slot $slot
$deploymentCE = Get-AzureDeployment -ServiceName $csNameCE -Slot $slot

while ($deploymentCD.OperationStatus -ne "Succeeded" -And $deploymentCE.OperationStatus -ne "Succeeded")
{
    $i = 1
    foreach ($roleInstance in $deploymentCD.RoleInstanceList)
    {
        $instanceName = $roleInstance.InstanceName
        $instanceStatus = $roleInstance.InstanceStatus

		# Did the status change?
        if ($oldStatusStrCD -ne $roleInstance.InstanceStatus)
        {
            $oldStatusStrCD = $roleInstance.InstanceStatus
            LogRule -message "Starting Instance '$instanceName': $instanceStatus" -role "CD"
        }

        $i = $i + 1
    }

    foreach ($roleInstance in $deploymentCE.RoleInstanceList)
    {
        $instanceName = $roleInstance.InstanceName
        $instanceStatus = $roleInstance.InstanceStatus

		# Did the status change?
        if ($oldStatusStrCE -ne $roleInstance.InstanceStatus)
        {
            $oldStatusStrCE = $roleInstance.InstanceStatus
            LogRule -message "Starting Instance '$instanceName': $instanceStatus" -role "CE"
        }

        $i = $i + 1
    }

    sleep -Seconds 1

    $deploymentCD = Get-AzureDeployment -ServiceName $csNameCD -Slot $slot
    $deploymentCE = Get-AzureDeployment -ServiceName $csNameCE -Slot $slot
}

if($newCEDeployment -eq $true){
    $ip = $deploymentCE.VirtualIPs[0].Address        
    LogRule -message "IP address: $ip" -role "CD"
}

if($newCDDeployment -eq $true){
    $ip = $deploymentCD.VirtualIPs[0].Address
    LogRule -message "IP address: $ip" -role "CE"
}

LogRule "Provisioning finished." ""