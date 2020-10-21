$clusterName = 'DemoClSHDFCI'

### To be updated with your SA name!!! ###
$witnessSaName = 'sqlfcisawitness'
### To be updated with your SA key!!! ###
$witnessSaKey = '8555TwOeVqyPxfNZp/k2KTXsKBaYWVcqF+ZQhwwjY1SXFWmokkQLxYTUEx/TAe/xferGn9aDfpAtLkVI5BXo7w=='
$sqlNodes = 'SqlShdClNode01','SqlShdClNode02'

Import-Module FailoverClusters

# Disable firewall on Domain profile - only for demo purposes!
Set-NetFirewallProfile -Profile Domain -Enabled False
$cimSession = New-CimSession -ComputerName $sqlNodes[1]
Set-NetFirewallProfile -Profile Domain -Enabled False -CimSession $cimSession
$cimSession.Close()

# Initialize shared disks
$disk = Get-Disk | ? PartitionStyle -eq "RAW" 
$disk | Initialize-Disk -PartitionStyle GPT 
$disk | Set-Disk -IsOffline:$false
$disk | 
    New-Partition -AssignDriveLetter -UseMaximumSize |
    Format-Volume -FileSystem NTFS -AllocationUnitSize 64KB -Force -Confirm:$false

# Create WSFC  
Test-Cluster -Node $sqlNodes –Include "Inventory", "Network", "System Configuration"
New-Cluster -Name $clusterName -Node $sqlNodes -NoStorage

# Change cluster quorum configuration to storage account
Set-ClusterQuorum -CloudWitness -AccountName $witnessSaName -AccessKey $witnessSaKey

# Add available storage to the cluster as CSV
Get-ClusterAvailableDisk | Add-ClusterDisk | Add-ClusterSharedVolume

# Create a service account on AD for the SQL services
$sqlSvc = Get-AdUser -Filter * | ? Name -eq "SqlSvc"
if(!$sqlSvc) {
    $sqlSvc = New-AdUser -Name "SqlSvc" -AccountPassword ("Passw0rd.1" | ConvertTo-SecureString -AsPlainText -Force) -Enabled:$true
}

# Setup instance on first node
Install-DbaInstance -Version 2019 -ConfigurationFile ".\SHDFCI-SqlConfigFile-node01.ini" -Path C:\SQLServerFull

# Setup instance on second node. When prompted, enter credentials for an administrative account on the secondary node.
# You can alternatively connect to secondary node and execute the setup wizard with the configuration file
Install-DbaInstance -Version 2019 -ConfigurationFile .\SHDFCI-SqlConfigFile-node02.ini -Path C:\SQLServerFull -Credential (Get-Credential) -SqlInstance $sqlNodes[1]

## Update cluster cluster to use DNN
$sqlClusterGroup = Get-ClusterGroup | Where-Object Name -Like "*SQL SERVER*"
$sqlClusterVNN = $sqlClusterGroup| get-clusterresource | ? ResourceType -eq "Network Name"

# Get current DNS Name assigned to the SQL FCI
$sqlDnsName = $sqlClusterVNN | Get-ClusterParameter -Name DnsName | Select -ExpandProperty Value

# Stop and rename (both name and DnsName) the VNN
$sqlClusterVNN | Stop-ClusterResource
$sqlClusterVNN.Name = "$sqlDnsName-VNN"
$sqlClusterVNN | Set-ClusterParameter -Name "DnsName" -value "SQLFCI-VNN"
$sqlClusterVNN | Start-ClusterResource

# Create a DNN and assign it the original FCI DnsName
$sqlClusterDNN = Add-ClusterResource -Name "$sqlDnsName-DNN" `
                       -ResourceType "Distributed Network Name" `
                       -Group $sqlClusterGroup

$sqlClusterDNN | Set-ClusterParameter -Name "DnsName" -value $sqlDnsName

# Create a SQL Alias from VNN to DNN on both cluster nodes
# https://docs.microsoft.com/en-us/azure/azure-sql/virtual-machines/windows/failover-cluster-instance-dnn-interoperability
New-DbaClientAlias -ComputerName $sqlNodes[0] -Alias "SQLFCI-VNN" -ServerName $sqlDnsName
New-DbaClientAlias -ComputerName $sqlNodes[1] -Alias "SQLFCI-VNN" -ServerName $sqlDnsName


$sqlClusterGroup | Stop-ClusterGroup
$sqlClusterGroup | Start-ClusterGroup
