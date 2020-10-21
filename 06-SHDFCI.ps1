. .\00-CommonVariables.ps1

. .\01-EnvironmentPreparation.ps1

$avSet = New-AzAvailabilitySet -Name $shdAvSetName `
            -ResourceGroupName $rgName `
            -Location $location `
            -PlatformUpdateDomainCount 3 `
            -PlatformFaultDomainCount 3 `
            -Sku "Aligned" `
            -ProximityPlacementGroupId $ppg.Id

# Deploy two cluster nodes
New-AzResourceGroupDeployment -Name "SHDFCI-Node01" `
    -ResourceGroupName $rgName `
    -TemplateUri "https://raw.githubusercontent.com/OmegaMadLab/OptimizedSqlVm-v2/master/azuredeploy.json" `
    -TemplateParameterFile ".\SHDFCI\azuredeploy.parameters.shdfci.cl01.json" `
    -AsJob

Start-Sleep -Seconds 30

New-AzResourceGroupDeployment -Name "SHDFCI-Node02" `
    -ResourceGroupName $rgName `
    -TemplateUri "https://raw.githubusercontent.com/OmegaMadLab/OptimizedSqlVm-v2/master/azuredeploy.json" `
    -TemplateParameterFile ".\SHDFCI\azuredeploy.parameters.shdfci.cl02.json"
    

# Create two Shared Disks to host database data and log file
$diskConfig = New-AzDiskConfig `
                -Location $location `
                -DiskSizeGB 512 `
                -MaxSharesCount 2 `
                -AccountType Premium_LRS `
                -CreateOption Empty

$dataDisk = New-AzDisk -ResourceGroupName $rgName `
                -DiskName 'SharedDataDisk' -Disk $diskconfig

$logDisk = New-AzDisk -ResourceGroupName $rgName `
                -DiskName 'SharedLogDisk' -Disk $diskconfig

# Add Shared Disks to the VMs
$vmNames = @()
$vmNames += "SqlShdClNode01"
$vmNames += "SqlShdClNode02"

$vm = $vmNames | % { Get-AzVm -Name $_ -ResourceGroupName $rgName }
$vm | Stop-AzVM -Force
                
$vm | % { 
    Add-AzVMDataDisk -VM $_ `
        -Name $dataDisk.Name `
        -CreateOption Attach `
        -ManagedDiskId $dataDisk.Id `
        -Lun 0 `
        -Caching None # Using cache=none for data disks due to Shared Disks preview limits
    
    Add-AzVMDataDisk -VM $_ `
        -Name $logDisk.Name `
        -CreateOption Attach `
        -ManagedDiskId $logDisk.Id `
        -Lun 1 `
        -Caching None
}

$vm | Update-AzVm

$vm | Start-AzVM -asJob 

# Now, copy the content of the SHDFCI folder inside the first cluster node.
# Then, from there,  execute the script name SHDFCI-GuestClusterConfig.ps1 to setup the cluster




