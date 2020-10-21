$clusterName = 'DemoClPFSFCI'

$ipAddr = '10.0.0.115'
$probePort = '59990'
### To be updated with your SA name!!! ###
$witnessSaName = 'sqlfcisawitness'
### To be updated with your SA key!!! ###
$witnessSaKey = '6QabCmN+38hBe48cl2STlQLnA3M5D2qixN7FKrkb5mr/KEVuFQyyW5vgANCwxP0y9iY/T+Bdo05l0olo3tK1sQ=='
$sqlNodes = 'SqlPfsClNode01','SqlPfsClNode02'

Import-Module FailoverClusters

# Disable firewall on Domain profile - only for demo purposes!
Set-NetFirewallProfile -Profile Domain -Enabled False
$cimSession = New-CimSession -ComputerName $sqlNodes[1]
Set-NetFirewallProfile -Profile Domain -Enabled False -CimSession $cimSession



# Create WSFC 
Test-Cluster -Node $sqlNodes –Include "Inventory", "Network", "System Configuration"
New-Cluster -Name $clusterName -Node $sqlNodes -NoStorage

# Change cluster quorum configuration to storage account
Set-ClusterQuorum -CloudWitness -AccountName $witnessSaName -AccessKey $witnessSaKey

# Create a service account on AD for the SQL services
$sqlSvc = Get-AdUser -Filter * | ? Name -eq "SqlSvc"
if(!$sqlSvc) {
    $sqlSvc = New-AdUser -Name "SqlSvc" -AccountPassword ("Passw0rd.1" | ConvertTo-SecureString -AsPlainText -Force) -Enabled:$true
}

# Install the PowerShell module for Azure Storage and log into your subscription, in o
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if(-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
    Register-PSRepository -Default
}

Install-Module "Az.Storage"
Add-AzAccount
# Use Select-AzSubscription, if you have access to multiple subs and need to specify the correct one

# Specify resource group name and location for the Premium File Share
$rgName = 'SqlIaasPlayground-RG'
$location = 'westeurope'

$fsSa = New-AzStorageAccount -ResourceGroupName $rgName `
            -Name ("demostor$(Get-Random -Maximum 999999999)") `
            -SkuName "Premium_LRS" `
            -Location $location `
            -Kind "FileStorage"

$pfs = New-AzStorageShare `
            -Name "sqldemo" `
            -Context $fsSa.Context 

$pfs | Set-AzStorageShareQuota -Quota 100

#Test connectivity to the file share
Test-NetConnection -ComputerName $pfs.Uri.Host -Port 445

# Register file share credentials on both cluster nodes.
# The operation must be done in the context of the SQL Server service account and for the user who's executing the setup
$target = $pfs.Uri.Host
$usrName = "Azure\$($fsSa.StorageAccountName)"
$usrPwd = $(($fsSa | Get-AzStorageAccountKey)[0].Value)

$cmdKeyArgs = @()
$cmdKeyArgs += "/add:$($target)"
$cmdKeyArgs += "/user:$($usrName)"
$cmdKeyArgs += "/pass:$($usrPwd)"


## local execution - execute a process in the context of the service account - the process launch CMDKEY
$sqlSvcCred = New-Object PSCredential "CONTOSO\SqlSvc", ("Passw0rd.1" | ConvertTo-SecureString -AsPlainText -Force)

Start-Process "cmdKey.exe" `
    -ArgumentList $cmdKeyArgs `
    -Credential $sqlSvcCred `
    -NoNewWindow

# Repeat for current user
Start-Process "cmdKey.exe" `
    -ArgumentList $cmdKeyArgs `
    -NoNewWindow
    
## remote execution - CMDKEY can't be executed in a PSSession.
## The workaround is to create two scheduled tasks on the remote system, that run with the service account and the current user credential to execute CMDKEY
## To cut some corners, I'm adding the service account to remote admin group, and then remove it once execution is completed.
## This is necessary because you need "Logon as a batch job" privilege to run an unattended task if you're not an admin.
## I didn't find a quick and dirty way to do it; it's possible to do it by editing Local Security Policy with SECEDIT or by using
## this script: https://gallery.technet.microsoft.com/scriptcenter/Grant-Log-on-as-a-service-11a50893
## Anyway, both solutions are overkilling for this demo setup, so I proceed with local admin rights

Invoke-Command -ComputerName $sqlNodes[1] -ScriptBlock { Add-LocalGroupMember -Group "Administrators" -Member "CONTOSO\SqlSvc" }


$sta = New-ScheduledTaskAction "cmdkey" -Argument ($cmdKeyArgs -join " ") -CimSession $cimSession
Register-ScheduledTask -TaskName "cmdKeySvcAccnt" -Action $sta -User "CONTOSO\SqlSvc" -Password "Passw0rd.1" -RunLevel Highest -CimSession $cimSession
Register-ScheduledTask -TaskName "cmdKeyAdmin" -Action $sta -User "CONTOSO\contosoadmin" -Password "Passw0rd.1" -RunLevel Highest -CimSession $cimSession

Get-ScheduledTask -TaskName "cmdKeySvcAccnt" -CimSession $cimSession | Start-ScheduledTask
Get-ScheduledTask -TaskName "cmdKeySvcAccnt" -CimSession $cimSession | Unregister-ScheduledTask -Confirm:$false

Get-ScheduledTask -TaskName "cmdKeyAdmin" -CimSession $cimSession | Start-ScheduledTask
Get-ScheduledTask -TaskName "cmdKeyAdmin" -CimSession $cimSession | Unregister-ScheduledTask -Confirm:$false

Invoke-Command -ComputerName $sqlNodes[1] -ScriptBlock { Remove-LocalGroupMember -Group "Administrators" -Member "CONTOSO\SqlSvc" }


# Setup instance on first node
$pfsUncPath = "\\$target\$($pfs.Name)"

(Get-Content -Path ".\PFSFCI-SqlConfigFile-node01-template.ini" ).Replace('{0}', $pfsUncPath) | Out-File ".\PFSFCI-SqlConfigFile-node01-final.ini" -Force
Install-DbaInstance -Version 2019 -ConfigurationFile ".\PFSFCI-SqlConfigFile-node01-final.ini" -Path C:\SQLServerFull

# Update cluster IP with probe details
$clusterNetwork = Get-ClusterNetwork

$sqlClusterGroup = Get-ClusterGroup | Where-Object Name -Like "*SQL SERVER*"
$sqlClusterIpAddr = $sqlClusterGroup| get-clusterresource | where-object { $_.resourcetype.name -eq "ip address"}  
$sqlClusterIpAddr | Set-ClusterParameter -Multiple @{
    "Address"=$ipAddr;
    "ProbePort"= $probePort;
    "SubnetMask"="255.255.255.255";
    "Network"="$($clusterNetwork.Name)";
    "EnableDhcp"=0
}

$sqlClusterGroup | Stop-ClusterGroup
$sqlClusterGroup | Start-ClusterGroup

# Setup instance on second node - This doesn't work with DBATools up to version 1.0.105, due to a bug. 
# You can also find issues related to updates on secondary node.
# You can alternatively connect to secondary node and execute the setup wizard with the configuration file
(Get-Content -Path ".\PFSFCI-SqlConfigFile-node02-template.ini" ).Replace('{0}', $pfsUncPath) | Out-File ".\PFSFCI-SqlConfigFile-node02-final.ini" -Force
Install-DbaInstance -Version 2019 -ConfigurationFile ".\PFSFCI-SqlConfigFile-node02-final.ini" -Path C:\SQLServerFull -SqlInstance $sqlNodes[1] -Verbose

