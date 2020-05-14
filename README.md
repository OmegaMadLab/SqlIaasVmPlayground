# Sql Iaas Vm Playground

This repository contains scripts to deploy several Azure IaaS architectures for SQL Server.
All the scripts are meant to be executed one block at a time.

If you need to customize names or other parameters, have a look into the script **00-CommonVariables.ps1**.
You can start deploying from the script **01-EnvironmentPreparation.ps1**: it provisions all the infrastructural resources, as well as an Active Directory domain controller.

Then, you can choose between:
- **02-S2DFCI.ps1** to deploy a two-node SQL Failover Cluster Instance, with the storage layer based on Storage Spaces Direct. Databases are hosted on CSV volumes; data are replicated via S2D storage replica, between disks attached to each cluster node.
- **03-PFSFCI.ps1** to deploy a two-node SQL Failover Cluster Instance, with the storage layer based on an Azure Premium File Share. Databases are hosted on the file share, accessible from both nodes.
- **04-AlwaysOnAG.ps1** to deploy a two-node a cluster with an Always On Availability Group. Databases are hosted on the disks attached to each cluster node, and replica happens at database level.
- **05-SingleVM.ps1** to deploy a standalone domain-joined SQL VM.

All the deployments are based upon my [ARM template](https://github.com/OmegaMadLab/OptimizedSqlVm-v2), that leverage on SQL VM IaaS Provider and some custom PowerShell to deploy an optimized SQL Server VM.

These demo scripts were used during the following sessions:

**Global Azure Virtual 2020 - What's new on Azure IaaS for SQL VMs**  
[Slide](https://www.slideshare.net/MarcoObinu/global-azure-virtual-2020-whats-new-on-azure-iaas-for-sql-vms)  
[Video](https://youtu.be/7o80CJUtnh4)

**HomeGen - Azure VM 101**  
[Slide](https://www.slideshare.net/MarcoObinu/azure-vm-101-homegen-by-cloudgen-verona)  
[Video](https://youtu.be/C8v6c6EkJ9A)
