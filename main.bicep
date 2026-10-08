// main.bicep
targetScope = 'subscription'

param resourceGroupName string
param location string

// Create the Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
}

// Deploy network module into the created Resource Group
module network './network.bicep' = {
  name: 'networkDeployment'
  scope: rg
  params: {
    location: location
  }
}
