$clusterName = 'DemoClS2DFCI'

$ipAddr = '10.0.0.110'
$probePort = '59990'
### To be updated with your SA name!!! ###
$witnessSaName = 'sqlfcisawitness'
### To be updated with your SA key!!! ###
$witnessSaKey = '6QabCmN+38hBe48cl2STlQLnA3M5D2qixN7FKrkb5mr/KEVuFQyyW5vgANCwxP0y9iY/T+Bdo05l0olo3tK1sQ=='
$sqlNodes = 'SqlClNode01','SqlClNode02'

Import-Module FailoverClusters

# Disable firewall on Domain profile - only for demo purposes!
Set-NetFirewallProfile -Profile Domain -Enabled False
$cimSession = New-CimSession -ComputerName $sqlNodes[1]
Set-NetFirewallProfile -Profile Domain -Enabled False -CimSession $cimSession


# Create WSFC 
Test-Cluster -Node $sqlNodes -Include "Inventory", "Network", "System Configuration"
New-Cluster -Name $clusterName -Node $sqlNodes -NoStorage

# Change cluster quorum configuration to storage account
Set-ClusterQuorum -CloudWitness -AccountName $witnessSaName -AccessKey $witnessSaKey
# Enable storage spaces direct and create a new CSV
Enable-ClusterS2D

New-Volume -StoragePoolFriendlyName S2D* `
    -FriendlyName "SQLVolume" `
    -FileSystem "CSVFS_NTFS" `
    -Size 0.9TB `
    -AllocationUnitSize 64KB `
    -ResiliencySettingName Mirror

# Create a service account on AD for the SQL services
$sqlSvc = Get-AdUser -Filter * | ? Name -eq "SqlSvc"
if(!$sqlSvc) {
    $sqlSvc = New-AdUser -Name "SqlSvc" -AccountPassword ("Passw0rd.1" | ConvertTo-SecureString -AsPlainText -Force) -Enabled:$true
}

# Setup instance on first node
Install-DbaInstance -Version 2019 -ConfigurationFile ".\S2DFCI-SqlConfigFile-node01.ini" -Path C:\SQLServerFull

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
# You can alternatively connect to secondary node and execute the setup wizard with the configuration file
Install-DbaInstance -Version 2019 -ConfigurationFile ".\S2DFCI-SqlConfigFile-node02.ini" -Path C:\SQLServerFull -SqlInstance $sqlNodes[1]
