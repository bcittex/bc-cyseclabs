targetScope = 'subscription'

param location string = 'eastus'
param resourceGroupName string = 'rg-security-lab-prod'

// 1. Create the Isolated Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
}

// 2. Deploy Network Security Group & Rules inside the Resource Group 
module securityResources 'br/public:avm/res/network/network-security-group:0.5.0' = {
  scope: rg
  name: 'nsg-deploy'
  params: {
    name: 'nsg-core-prod'
    location: location
    securityRules: [
      {
        name: 'Deny-All-Inbound'
        properties: {
          description: 'Zero-trust perimeter default deny rule'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4000
          direction: 'Inbound'
        }
      }
    ]
  }
}

// 3. Deploy Virtual Network and Subnet linked to the NSG
module vnetResources 'br/public:avm/res/network/virtual-network:0.5.1' = {
  scope: rg
  name: 'vnet-deploy'
  params: {
    name: 'vnet-secure-prod'
    location: location
    addressPrefixes: [
      '10.0.0.0/16'
    ]
    subnets: [
      {
        name: 'snet-secure-prod'
        addressPrefix: '10.0.0.0/24'
        networkSecurityGroupResourceId: securityResources.outputs.resourceId
      }
    ]
  }
}
