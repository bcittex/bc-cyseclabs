// main.bicep
targetScope = 'subscription'

param resourceGroupName string = 'rg-my-app-dev'
param location string = 'eastus'

// Create the resource group at subscription scope
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
}

// Deploy network.bicep into the created resource group
module network './network.bicep' = {
  name: 'networkDeployment'
  params: {
    location: location
    resourceGroupName: resourceGroupName
  }
}
