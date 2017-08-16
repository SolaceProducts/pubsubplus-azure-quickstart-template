# Install a Solace Message Router onto a Linux Virtual Machine using Docker and Custom Extensions

The Solace Virtual Message Router (VMR) provides enterprise-grade messaging capabilities deployable in any computing environment. The VMR provides the same rich feature set as Solace’s proven hardware appliances, with the same open protocol support, APIs and common management. The VMR can be deployed in the datacenter or natively within all popular private and public clouds. 

How to Deploy a VMR
-------------------

VMRs can either be deployed as a 3 node HA cluster or a single node.  For simple test enviroments that need to validate application functionality, a simple single instance will suffice, but in production or any enviroment where message loss can not be tolerated then a HA cluster is required.

![alt text](https://raw.githubusercontent.com/SolaceLabs/solace-azure-quickstart-template/addHA/images/ha-cluster.png "HA Cluster Deployment")

![alt text](https://raw.githubusercontent.com/SolaceLabs/solace-azure-quickstart-template/addHA/images/single-vmr.png "Single Node Deployment")

This is a 2 step process:

* Go to the Solace Developer portal and request a Solace Community edition VMR. This process will return an email with a Download link. Do a right click "Copy Hyperlink" on the "Download the VMR Community Edition for Docker" download hyperlink.  This will be needed in the following section.

 COMMUNITY EDITION FOR SINGLE NODE | EVALUTAION EDITION FOR HA CLUSTER
       --- | --- |

<a href="http://dev.solace.com/downloads/download_vmr-ce-docker" target="_blank">
    <img src="https://raw.githubusercontent.com/SolaceLabs/solace-azure-quickstart-template/master/images/register.png"/>
</a>

<a href="http://dev.solace.com/downloads/download-vmr-evaluation-edition-docker/" target="_blank">
    <img src="https://raw.githubusercontent.com/SolaceLabs/solace-azure-quickstart-template/master/images/register.png"/>
</a>


* Hit the "Deploy to Azure" button and in the deployment template add in the link to the VMR provided by Solace. 

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FSolaceLabs%2Fsolace-azure-quickstart-template%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FSolaceLabs%2Fsolace-azure-quickstart-template%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

The fields that you need to fill out are:
1. Resource Group - A new group or an existing group available in pulldown menu once "Use existing" is selected.
2. Location - Select region most suitable to you.
3. Storage Account Name – New or existing storage account, your VHD will be stored here.
4. Admin Username - Username for the virtual Machine.
5. Admin Password - Password for the virtual Machine.
6. Security Group Name – New or existing security group, VMR default ports will be made publically available.
7. DNS Name – Public DNS name for the virtual machine.
8. CentOS version – Use Centos 7.2 or CentOS 7.3
9. VM Size – Use Standard_D2_V2 or Standard_F2s
10. Solace VMR URI – The URI link to the community edition VMR received in the registration process
11. Deployment Model - High Availability, Single Node

# Gaining admin access to the VMR

For persons used to working with Solace message router console access, this is still available with the Azure instance.  The [connect] button to the upper left displays this information: Use the "Admin Username" and "Admin Password" provided.

![alt text](https://raw.githubusercontent.com/SolaceLabs/solace-azure-quickstart-template/master/images/remote_access.png "console with SolOS cli")

Once you have access to the base OS command line you can access the SolOS CLI with the following command:
```
sudo docker exec -it solace /usr/sw/loads/currentload/bin/cli -A
```
It would be advised to change the SolOS cli admin user password as per these [instructions](http://docs.solace.com/Configuring-and-Managing-Routers/Configuring-Internal-CLI-User-Accounts.htm#Changing-CLI-User-Passwords)


For persons who are unfamiliar with the Solace mesage router, or would prefer an administration application, the SolAdmin management application is available.  For more information on SolAdmin see the [SolAdmin page](http://dev.solace.com/tech/soladmin/).  To get SolAdmin, visit the Solace [download page](http://dev.solace.com/downloads/) and select OS version desired.  Management IP will be the External IP associated with your Azure instance and the port will be 8080 by default.

![alt text](https://raw.githubusercontent.com/SolaceLabs/solace-azure-quickstart-template/master/images/azure-soladmin.png "soladmin connection to gce")

# Testing data access to the VMR

To test data traffic though the newly created VMR instance, visit the Solace developer portal and and select your preferred programming language to [send and receive messages](http://dev.solace.com/get-started/send-receive-messages/). Under each language there is a Publish/Subscribe tutorial that will help you get started.

![alt text](https://raw.githubusercontent.com/SolaceLabs/solace-azure-quickstart-template/master/images/solace_tutorial.png "getting started publish/subscribe")

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct, and the process for submitting pull requests to us.

## Authors

See the list of [contributors](https://github.com/azure-quickstart-templates/solace-community-edition/graphs/contributors) who participated in this project.

## License

This project is licensed under the Apache License, Version 2.0. - See the [LICENSE](LICENSE) file for details.

## Resources

For more information about writing Azure Resource Manager(ARM) templates and Azure quickstart templates try these resources:

- [Authoring Azure Resource Manager templates](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-authoring-templates)
- [Azure Quickstart Templates](https://azure.microsoft.com/en-us/resources/templates/)

For more information about Solace technology in general please visit these resources:

- The Solace Developer Portal website at: http://dev.solace.com
- Understanding [Solace technology.](http://dev.solace.com/tech/)
- Ask the [Solace community](http://dev.solace.com/community/).
