. .\00b-CommonVariables-WestCentralUS.ps1

# Get or create the resource group
$rg = Get-AzResourceGroup -Name $rgName `
        -Location $location `
        -ErrorAction SilentlyContinue

if(!$rg) {
    $rg = New-AzResourceGroup -Name $rgName `
            -Location $location
}

# Create a vnet and a DC
New-AzResourceGroupDeployment -Name "vnet" `
    -ResourceGroupName $rgName `
    -TemplateUri "https://raw.githubusercontent.com/OmegaMadLab/LabTemplates/master/vnet.json" `
    -vnetName $vnetName `
    -subnetName $subnetName

$dcDeployment = New-AzResourceGroupDeployment -Name "DC" `
                    -ResourceGroupName $rgName `
                    -TemplateUri "https://raw.githubusercontent.com/OmegaMadLab/LabTemplates/master/addc.json" `
                    -envPrefix "Demo" `
                    -vmName "DC" `
                    -genericVmSize "Standard_E4-2s_v4" `
                    -adminUserName $adminName `
                    -adminPassword $adminPwd `
                    -domainName $domainName `
                    -vnetName $vnetName `
                    -subnetName $subnetName
                    
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName
$vnet.DhcpOptions.DnsServers = $dcDeployment.Outputs.dcPrivateIp.Value
$vnet | Set-AzVirtualNetwork

Restart-AzVm -Name "Demo-DC" -resourceGroupName $rgName 

# Create a storage account for cluster witness
$sa = New-AzStorageAccount -ResourceGroupName $rgName `
        -Name $saName `
        -SkuName "Standard_LRS" `
        -Kind "Storage" `
        -Location $location

$key1 = ($sa | Get-AzStorageAccountKey).Value[0]
Write-Host "Storage account name: $($sa.StorageAccountName)"
Write-Host "Storage account key1: $key1"


