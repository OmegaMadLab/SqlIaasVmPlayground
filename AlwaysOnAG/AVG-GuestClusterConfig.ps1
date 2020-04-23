$clusterName = 'DemoClusterAG'
$agName = "DEMO-SQL-AG"

$ipAddr = '10.0.0.120'
$probePort = '59990'
$witnessSaName = 'sqlfcisawitness'
### To be updated with your SA key!!! ###
$witnessSaKey = '6QabCmN+38hBe48cl2STlQLnA3M5D2qixN7FKrkb5mr/KEVuFQyyW5vgANCwxP0y9iY/T+Bdo05l0olo3tK1sQ=='
$sqlNodes = 'SqlAgClNode01','SqlAgClNode02'

# Disable firewall on Domain profile - only for demo purposes!
Set-NetFirewallProfile -Profile Domain -Enabled False
$cimSession = New-CimSession -ComputerName $sqlNodes[1]
Set-NetFirewallProfile -Profile Domain -Enabled False -CimSession $cimSession

Import-Module FailoverClusters

# Create WSFC 
Test-Cluster -Node $sqlNodes –Include "Inventory", "Network", "System Configuration"
New-Cluster -Name $clusterName -Node $sqlNodes -NoStorage

# Change cluster quorum configuration to storage account
Set-ClusterQuorum -CloudWitness -AccountName $witnessSaName -AccessKey $witnessSaKey

# Set SQL service account to a domain account
$sqlSvc = Get-AdUser -Filter * | ? Name -eq "SqlSvc"
if(!$sqlSvc) {
    $sqlSvc = New-AdUser -Name "SqlSvc" -AccountPassword ("Passw0rd.1" | ConvertTo-SecureString -AsPlainText -Force) -Enabled:$true
}

Get-DbaService -ComputerName $sqlNodes -ServiceName "MSSQLSERVER" |
    Update-DbaServiceAccount -Username "CONTOSO\sqlsvc" -SecurePassword ("Passw0rd.1" | ConvertTo-SecureString -AsPlainText -Force)

# Enable Always ON HA
$sqlNodes | Enable-DbaAgHadr -Force

# Create a dummy DB on first SQL node
$db = New-DbaDataBase -Name "DummyDB" `
        -SqlInstance $sqlNodes[0]

# Execute an initial full backup
Backup-DbaDatabase -SqlInstance $sqlNodes[0] -Database $Db.Name

# Create a new availability group and put the DB inside it
New-DbaAvailabilityGroup -Primary $sqlNodes[0] `
    -Secondary $sqlNodes[1] `
    -Name $agName `
    -ClusterType 'Wsfc' `
    -AvailabilityMode 'SynchronousCommit' `
    -FailoverMode 'Automatic' `
    -Database $db.Name `
    -SeedingMode 'Automatic' `
    -IPAddress $ipAddr `
    -verbose

# Update cluster IP with probe details
$clusterNetwork = Get-ClusterNetwork

$sqlClusterGroup = Get-ClusterGroup | Where-Object Name -eq $agName
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

