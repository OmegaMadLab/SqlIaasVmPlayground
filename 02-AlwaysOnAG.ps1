. .\00-CommonVariables.ps1

# Deploy two cluster nodes
New-AzResourceGroupDeployment -Name "AVG-Node01" `
    -ResourceGroupName $rgName `
    -TemplateUri "https://raw.githubusercontent.com/OmegaMadLab/OptimizedSqlVm-v2/master/azuredeploy.json" `
    -TemplateParameterFile ".\AlwaysOnAG\azuredeploy.parameters.avg.cl01.json" `
    -AsJob

Start-Sleep -Seconds 30

New-AzResourceGroupDeployment -Name "AVG-Node02" `
    -ResourceGroupName $rgName `
    -TemplateUri "https://raw.githubusercontent.com/OmegaMadLab/OptimizedSqlVm-v2/master/azuredeploy.json" `
    -TemplateParameterFile ".\AlwaysOnAG\azuredeploy.parameters.avg.cl02.json" `
    -AsJob

# Now, copy the content of the AlwaysOnAG folder inside the first cluster node.
# Then, from there,  execute the script name AVG-GuestClusterConfig.ps1 to setup the cluster

# Add VMs to the ILB backend pool
# ILB is a standard SKU, so it will block outbound (internet) connectivity if an outbound configuration isn't enabled
# https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-outbound-rules-overview

$vmNames = @()
$vmNames += "SqlAgClNode01"
$vmNames += "SqlAgClNode02"

$ilb = Get-AzLoadBalancer -Name $agIlbName -ResourceGroupName $rgName
$bePool = $ilb | Get-AzLoadBalancerBackendAddressPoolConfig

foreach($vmName in $vmNames)
{
    $vm = Get-AzVM -ResourceGroupName $rgName `
            -Name $vmName 
    $nicName = ($vm.NetworkProfile.NetworkInterfaces[0].Id.Split('/') | Select-Object -last 1)
    $nic = Get-AzNetworkInterface -name $nicName `
                                        -ResourceGroupName $rgName
    $nic.IpConfigurations[0].LoadBalancerBackendAddressPools = $bePool
    Set-AzNetworkInterface -NetworkInterface $nic -AsJob
}


# After the first test session, deallocate the VMs and assign them to the PPG
# PPG is assigned to the availability set, since VMs are assigned to it
$ppg = Get-AzProximityPlacementGroup -Name $ppgName `
        -ResourceGroupName $rgName

$vmNames | % { Get-AzVm -Name $_ -ResourceGroupName $rgName | Stop-AzVM -Force }

$avSet = Get-AzAvailabilitySet -Name $agAvSetName -ResourceGroupName $rgName
Update-AzAvailabilitySet -AvailabilitySet $avSet -ProximityPlacementGroupId $ppg.Id

$vmNames | % { Get-AzVm -Name $_ -ResourceGroupName $rgName | Start-AzVM -asJob }
