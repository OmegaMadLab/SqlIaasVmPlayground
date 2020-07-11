. .\00-CommonVariables.ps1

# Deploy two cluster nodes
New-AzResourceGroupDeployment -Name "SingleVM" `
    -ResourceGroupName $rgName `
    -TemplateUri "https://raw.githubusercontent.com/OmegaMadLab/OptimizedSqlVm-v2/master/azuredeploy.json" `
    -TemplateParameterFile ".\SingleVM\azuredeploy.parameters.singleVM.json" 
