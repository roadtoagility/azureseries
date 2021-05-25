#!/bin/bash

MainTextColor=$'\e[1;33m'
OutputTextColor=$'\e[0;32m'
ParameterColor=$'\e[0;97m'

echo "$MainTextColor Enter the project alias $ParameterColor"
read projectAlias

echo -e "\n$MainTextColor Enter the resource group to be used $ParameterColor"
read resourceGroup

echo -e "\n$MainTextColor using '$resourceGroup' as resource group. Enter the location $ParameterColor"
read location

echo -e "\n$MainTextColor Creating resource group '$resourceGroup' on $location $OutputTextColor"

az group create --name $resourceGroup --location $location

echo -e "\n$MainTextColor Creating virtual network $OutputTextColor"

echo -e "\n$MainTextColor Enter the name of the network $ParameterColor"
read networkName

echo -e "\n$MainTextColor Enter the name of the subnet $ParameterColor"
read subnetName

echo -e "$OutputTextColor"

echo -e "\n$MainTextColor Enter admin-username for Virtual Machines $ParameterColor"
read username

echo -e "\n$MainTextColor Enter admin-password for Virtual Machines $ParameterColor"
echo "$MainTextColor The password length must be between 12 and 123. Password must have the 3 of the following: 1 lower case character, 1 upper case character, 1 number and 1 special character. $ParameterColor"
read password

az network vnet create --resource-group $resourceGroup --location $location --name $networkName --address-prefixes 10.1.0.0/16 --subnet-name $subnetName --subnet-prefixes 10.1.0.0/24
 
echo -e "\n$MainTextColor Creating the public IP address for the bastion host $OutputTextColor"

az network public-ip create --resource-group $resourceGroup --name BastionIP --sku Standard

echo -e "\n$MainTextColor Creating the bastion subnet $OutputTextColor"

az network vnet subnet create --resource-group $resourceGroup --name AzureBastionSubnet --vnet-name $networkName --address-prefixes 10.1.1.0/24

echo -e "\n$MainTextColor Creating the bastion host $OutputTextColor"

az network bastion create --resource-group $resourceGroup --name bastionNetwork --public-ip-address BastionIP --vnet-name $networkName --location $location

echo -e "\n$MainTextColor Creating a network security group $OutputTextColor"

az network nsg create --resource-group $resourceGroup --name $projectAlias\NSG

echo -e "\n$MainTextColor Creating a network security group rule $OutputTextColor"

az network nsg rule create --resource-group $resourceGroup --nsg-name $projectAlias\NSG --name $projectAlias\NSGRuleHTTP --protocol '*' --direction inbound --source-address-prefix '*' --source-port-range '*' --destination-address-prefix '*' --destination-port-range 80 --access allow --priority 200

echo -e "\n$MainTextColor Creating backend servers $OutputTextColor"

array=(myNicVM1 myNicVM2 myNicVM3)
for vmnic in "${array[@]}"
do
az network nic create --resource-group $resourceGroup --name $vmnic --vnet-name $networkName --subnet $subnetName --network-security-group $projectAlias\NSG
done

az vm availability-set create --name AvailabilitySet --resource-group $resourceGroup --location $location 

az vm create --resource-group $resourceGroup --name myVM1 --nics myNicVM1 --image win2019datacenter --admin-username $username --admin-password $password --availability-set AvailabilitySet --no-wait
	
az vm create \
    --resource-group $resourceGroup \
    --name myVM2 \
    --nics myNicVM2 \
    --image win2019datacenter \
    --admin-username $username \
	--admin-password $password \
    --availability-set AvailabilitySet \
    --no-wait

az vm create \
    --resource-group $resourceGroup \
    --name myVM3 \
    --nics myNicVM3 \
    --image win2019datacenter \
    --admin-username $username \
	--admin-password $password \
    --availability-set AvailabilitySet \
    --no-wait
	
echo -e "\n$MainTextColor Creating the public IP address $OutputTextColor"

az network public-ip create \
    --resource-group $resourceGroup \
    --name $projectAlias\PublicIP \
    --sku Basic
	
echo -e "\n$MainTextColor Creating the load balancer $OutputTextColor"

az network lb create \
    --resource-group $resourceGroup \
    --name $projectAlias\LoadBalancer \
    --sku Basic \
    --public-ip-address $projectAlias\PublicIP \
    --frontend-ip-name $projectAlias\FrontEnd \
    --backend-pool-name $projectAlias\BackEndPool 

echo -e "\n$MainTextColor Creating the health probe $OutputTextColor"
az network lb probe create \
    --resource-group $resourceGroup \
    --lb-name $projectAlias\LoadBalancer \
    --name $projectAlias\HealthProbe \
    --protocol tcp \
    --port 80
	
echo -e "\n$MainTextColor Creating the load balancer rule $OutputTextColor"
az network lb rule create \
    --resource-group $resourceGroup \
    --lb-name $projectAlias\LoadBalancer \
    --name $projectAlias\HTTPRule \
    --protocol tcp \
    --frontend-port 80 \
    --backend-port 80 \
    --frontend-ip-name $projectAlias\FrontEnd \
    --backend-pool-name $projectAlias\BackEndPool \
    --probe-name $projectAlias\HealthProbe \
    --idle-timeout 15
	
echo -e "\n$MainTextColor Put the VM's into the load balancer backend pool $OutputTextColor"
array=(myNicVM1 myNicVM2 myNicVM3)
for vmnic in "${array[@]}"
do
	az network nic ip-config address-pool add \
	 --address-pool $projectAlias\BackendPool \
	 --ip-config-name ipconfig1 \
	 --nic-name $vmnic \
	 --resource-group $resourceGroup \
	 --lb-name $projectAlias\LoadBalancer
done

echo -e "\n$MainTextColor Configuring IIS $OutputTextColor"
array=(myVM1 myVM2 myVM3)
for vm in "${array[@]}"
	do
	az vm extension set --publisher Microsoft.Compute --version 1.8 --name CustomScriptExtension --vm-name $vm --resource-group azureseries --settings '{"commandToExecute":"powershell Add-WindowsFeature Web-Server; powershell Add-Content -Path \"C:\\inetpub\\wwwroot\\Default.htm\" -Value $($env:computername)"}'
done

echo -e "\n$MainTextColor Test the load balancer $OutputTextColor"

az network public-ip show \
    --resource-group $resourceGroup \
    --name roadtestePublicIP \
    --query ipAddress \
    --output tsv

