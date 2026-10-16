// Entry point. Owns deployment-level configuration (naming, tags, parameters)
// and calls one module per concern. The resource group is created once,
// outside the pipeline, so the pipeline identity only needs rights on that RG.
targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Azure region. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Short workload name used in resource names and tags.')
param workload string = 'seclab'

@allowed(['dev', 'test', 'prod'])
@description('Environment short name used in resource names and tags.')
param environment string = 'prod'

@description('Address space(s) for the virtual network.')
param vnetAddressPrefixes array = ['10.0.0.0/16']

@description('Subnets to create: [{ name, addressPrefix }]. Validated by network.bicep.')
param subnets array = [
  {
    name: 'snet-secure-prod'
    addressPrefix: '10.0.0.0/24'
  }
]

@description('Extra NSG rules (priorities 1000-3999). Validated by network.bicep.')
param customRules array = []

@description('Allow Azure Load Balancer health probes inbound.')
param enableLoadBalancerProbes bool = false

@description('Apply CanNotDelete locks to network resources (needs lock-write rights).')
param enableLocks bool = false

@description('Extra tags merged with the standard set.')
param extraTags object = {}

// ---------------------------------------------------------------------------
// Naming and tags (single source of truth for every module)
// ---------------------------------------------------------------------------

var nsgName = 'nsg-${workload}-${environment}'
var vnetName = 'vnet-${workload}-${environment}'

var tags = union({
  workload: workload
  environment: environment
  managedBy: 'bicep'
}, extraTags)

// ---------------------------------------------------------------------------
// Modules
// ---------------------------------------------------------------------------

module network './network.bicep' = {
  name: 'networkDeployment'
  params: {
    location: location
    nsgName: nsgName
    vnetName: vnetName
    tags: tags
    vnetAddressPrefixes: vnetAddressPrefixes
    subnets: subnets
    customRules: customRules
    enableLoadBalancerProbes: enableLoadBalancerProbes
    enableLocks: enableLocks
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output nsgResourceId string = network.outputs.nsgResourceId
output vnetResourceId string = network.outputs.vnetResourceId
