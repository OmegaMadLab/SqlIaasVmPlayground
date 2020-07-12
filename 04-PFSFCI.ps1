. .\00-CommonVariables.ps1

# Deploy two cluster nodes
New-AzResourceGroupDeployment -Name "PFSFCI-Node01" `
    -ResourceGroupName $rgName `
    -TemplateUri "https://raw.githubusercontent.com/OmegaMadLab/OptimizedSqlVm-v2/master/azuredeploy.json" `
    -TemplateParameterFile ".\PFSFCI\azuredeploy.parameters.pfsfci.cl01.json" `
    -AsJob

Start-Sleep -Seconds 30

New-AzResourceGroupDeployment -Name "PFSFCI-Node02" `
    -ResourceGroupName $rgName `
    -TemplateUri "https://raw.githubusercontent.com/OmegaMadLab/OptimizedSqlVm-v2/master/azuredeploy.json" `
    -TemplateParameterFile ".\PFSFCI\azuredeploy.parameters.pfsfci.cl02.json" `
    -AsJob

# Create a Premium File Share to host databases
$fsSa = New-AzStorageAccount -ResourceGroupName $rgName `
            -Name ("demostor$(Get-Random -Maximum 999999999)") `
            -SkuName "Premium_LRS" `
            -Location $location `
            -Kind "FileStorage"

$pfs = New-AzStorageShare `
            -Name "sqldemo" `
            -Context $fsSa.Context 

$pfs | Set-AzStorageShareQuota -Quota 2048

# Now, copy the content of the PFSFCI folder inside the first cluster node.
# Then, from there,  execute the script name PFSFCI-GuestClusterConfig.ps1 to setup the cluster



# Add VMs to the ILB backend pool
# ILB is a standard SKU, so it will block outbound (internet) connectivity if an outbound configuration isn't enabled
# https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-outbound-rules-overview

$vmNames = @()
$vmNames += "SqlPfsClNode01"
$vmNames += "SqlPfsClNode02"

$ilb = Get-AzLoadBalancer -Name $pfsIlbName -ResourceGroupName $rgName
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

$avSet = Get-AzAvailabilitySet -Name $pfsAvSetName -ResourceGroupName $rgName
Update-AzAvailabilitySet -AvailabilitySet $avSet -ProximityPlacementGroupId $ppg.Id

$vmNames | % { Get-AzVm -Name $_ -ResourceGroupName $rgName | Start-AzVM -asJob }
