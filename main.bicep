// main.bicep
targetScope = 'subscription'

param resourceGroupName string
param location string

// Create Resource Group in East US
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
}

// Deploy Network Module into Resource Group
module network './network.bicep' = {
  name: 'networkDeployment'
  scope: rg
  params: {
    location: location
  }
}
