# Sql Iaas Vm Playground

This repository contains scripts to deploy several Azure IaaS architectures for SQL Server.
All the scripts are meant to be executed one block at a time.

If you need to customize names or other parameters, have a look into the script **00-CommonVariables.ps1**.
You can start deploying from the script **01-EnvironmentPreparation.ps1**: it provisions all the infrastructural resources, as well as an Active Directory domain controller.

Then, you can choose between:

- **02-AlwaysOnAG.ps1** to deploy a two-node a cluster with an Always On Availability Group. Databases are hosted on the disks attached to each cluster node, and replica happens at the database level. 
  
- **03-S2DFCI.ps1** to deploy a two-node SQL Failover Cluster Instance, with the storage layer based on Storage Spaces Direct. Databases are hosted on CSV volumes; data are replicated via S2D storage replica, between disks attached to each cluster node.  
  
- **04-PFSFCI.ps1** to deploy a two-node SQL Failover Cluster Instance, with the storage layer based on an Azure Premium File Share. Databases are hosted on the file share, accessible from both nodes.  
  
- **05-SingleVM.ps1** to deploy a standalone domain-joined SQL VM.  
  
- **06-SHDFCI.ps1** to deploy a two-node SQL Failover Cluster Instance, with the storage layer based on Azure Premium Shared Disks. Also, it avoids using the Azure Load Balancer to manage the clustered IPs, since it's using [Distributed Network Names](https://docs.microsoft.com/en-us/azure/azure-sql/virtual-machines/windows/hadr-distributed-network-name-dnn-configure#rename-the-vnn) both at the cluster and SQL Server level.  
Both these features are still in preview.  
While in preview, Shared Disks have a series of [limitations](https://docs.microsoft.com/it-it/azure/virtual-machines/windows/disks-shared#premium-ssds), starting with their availability that is currently limited to the West Central US region. For this reason, the script starts by calling **00b-CommonVariables-WestCentralUS.ps1** and **01b-EnvironmentPreparation-WestCentralUS.ps1** that deploy an isolated infrastructure (virtual network, DC, availability sets, and so on) in WestCentralUS. Then, it adds the two SQL Server nodes.  
Distributed Network Names are supported (in preview) starting by SQL Server 2019 CU2. Even if I managed to automate all the steps needed to deploy them, some parts are still not clear in the documentation.

All the deployments are based upon my [ARM template](https://github.com/OmegaMadLab/OptimizedSqlVm-v2), that leverage on SQL VM IaaS Provider and some custom PowerShell to deploy an optimized SQL Server VM.

You can find additional info on my blog:  
**[SQL Server High Availability Solutions on Azure VMs](https://www.omegamadlab.com/sql-server-high-availability-solutions-on-azure-vms/)**  
**[A new era for SQL Server FCI on Azure VMs](https://www.omegamadlab.com/a-new-era-for-sql-server-fci-on-azure-vms/)**

These demo scripts were used during the following sessions:

**Global Azure Virtual 2020 - What's new on Azure IaaS for SQL VMs**  
[Slide](https://www.slideshare.net/MarcoObinu/global-azure-virtual-2020-whats-new-on-azure-iaas-for-sql-vms)  
[Video](https://youtu.be/7o80CJUtnh4)

**HomeGen - Azure VM 101**  
[Slide](https://www.slideshare.net/MarcoObinu/azure-vm-101-homegen-by-cloudgen-verona)  
[Video](https://youtu.be/C8v6c6EkJ9A)
