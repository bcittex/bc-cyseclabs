// Reusable network module: NSG with a zero-trust rule baseline plus a VNet whose
// subnets are all bound to that NSG. Called from main.bicep.
targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

@description('Simplified NSG rule. Every address/port field is an array so rules scale without schema changes.')
type ruleType = {
  name: string
  @minValue(100)
  @maxValue(4096)
  priority: int
  direction: 'Inbound' | 'Outbound'
  access: 'Allow' | 'Deny'
  protocol: '*' | 'Tcp' | 'Udp' | 'Icmp'
  sourceAddressPrefixes: string[]
  destinationAddressPrefixes: string[]
  destinationPortRanges: string[]
  description: string?
}

type subnetType = {
  name: string
  addressPrefix: string
}

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Azure region for all resources.')
param location string

@description('NSG name.')
param nsgName string

@description('Virtual network name.')
param vnetName string

@description('Tags applied to every resource in this module.')
param tags object

@description('Address space(s) for the virtual network.')
param vnetAddressPrefixes string[]

@description('Subnets to create. Each one is attached to the NSG.')
param subnets subnetType[]

@description('Workload-specific rules layered on top of the zero-trust baseline. Use priorities 1000-3999. A rule can use one service tag or *, or a list of IPs/CIDRs, but not a mix of tags and IPs.')
param customRules ruleType[] = []

@description('Allow Azure Load Balancer health probes inbound. Only needed if a load balancer fronts the subnet.')
param enableLoadBalancerProbes bool = false

@description('Apply CanNotDelete locks. Off by default because writing locks needs Microsoft.Authorization rights that a Contributor pipeline identity lacks.')
param enableLocks bool = false

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var nsgLock = enableLocks ? { kind: 'CanNotDelete', name: 'lock-${nsgName}' } : null
var vnetLock = enableLocks ? { kind: 'CanNotDelete', name: 'lock-${vnetName}' } : null

// Priority convention:
//   100-499   platform / baseline allows
//   500-999   shared services (DNS, identity, monitoring)
//   1000-3999 workload rules (customRules)
//   4096      explicit deny-all (highest custom priority number)
var loadBalancerRules ruleType[] = enableLoadBalancerProbes ? [
  {
    name: 'Allow-AzureLoadBalancer-Inbound'
    priority: 100
    direction: 'Inbound'
    access: 'Allow'
    protocol: '*'
    sourceAddressPrefixes: ['AzureLoadBalancer']
    destinationAddressPrefixes: ['*']
    destinationPortRanges: ['*']
    description: 'Health probes. Overridden default rule, so it must be explicit once deny-all exists.'
  }
] : []

var baselineRules ruleType[] = [
  {
    name: 'Allow-AzurePlatform-Outbound'
    priority: 200
    direction: 'Outbound'
    access: 'Allow'
    protocol: '*'
    sourceAddressPrefixes: ['*']
    destinationAddressPrefixes: ['168.63.129.16']
    destinationPortRanges: ['53', '80', '32526']
    description: 'Azure DNS and VM agent/wire server. Required for VMs once outbound is denied.'
  }
  {
    name: 'Allow-EntraID-Outbound'
    priority: 500
    direction: 'Outbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefixes: ['*']
    destinationAddressPrefixes: ['AzureActiveDirectory']
    destinationPortRanges: ['443']
    description: 'Identity and authentication.'
  }
  {
    name: 'Allow-AzureMonitor-Outbound'
    priority: 510
    direction: 'Outbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefixes: ['*']
    destinationAddressPrefixes: ['AzureMonitor']
    destinationPortRanges: ['443']
    description: 'Log Analytics / Sentinel telemetry.'
  }
  {
    name: 'Deny-All-Inbound'
    priority: 4096
    direction: 'Inbound'
    access: 'Deny'
    protocol: '*'
    sourceAddressPrefixes: ['*']
    destinationAddressPrefixes: ['*']
    destinationPortRanges: ['*']
    description: 'Zero trust: nothing in unless explicitly allowed above.'
  }
  {
    name: 'Deny-All-Outbound'
    priority: 4096
    direction: 'Outbound'
    access: 'Deny'
    protocol: '*'
    sourceAddressPrefixes: ['*']
    destinationAddressPrefixes: ['*']
    destinationPortRanges: ['*']
    description: 'Zero trust: nothing out unless explicitly allowed above.'
  }
]

var allRules = concat(loadBalancerRules, baselineRules, customRules)

// Translate the simplified rule shape into the NSG properties shape.
// Azure does not accept '*' or a service tag inside the plural properties, so a
// single value goes in the singular property and only real lists use the plural one.
var securityRules = map(allRules, rule => {
  name: rule.name
  properties: {
    description: rule.?description ?? rule.name
    priority: rule.priority
    direction: rule.direction
    access: rule.access
    protocol: rule.protocol
    sourcePortRange: '*'
    sourceAddressPrefix: length(rule.sourceAddressPrefixes) == 1 ? rule.sourceAddressPrefixes[0] : null
    sourceAddressPrefixes: length(rule.sourceAddressPrefixes) > 1 ? rule.sourceAddressPrefixes : null
    destinationAddressPrefix: length(rule.destinationAddressPrefixes) == 1 ? rule.destinationAddressPrefixes[0] : null
    destinationAddressPrefixes: length(rule.destinationAddressPrefixes) > 1 ? rule.destinationAddressPrefixes : null
    destinationPortRange: length(rule.destinationPortRanges) == 1 ? rule.destinationPortRanges[0] : null
    destinationPortRanges: length(rule.destinationPortRanges) > 1 ? rule.destinationPortRanges : null
  }
})

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------

module nsg 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'deploy-${nsgName}'
  params: {
    name: nsgName
    location: location
    tags: tags
    lock: nsgLock
    securityRules: securityRules
  }
}

module vnet 'br/public:avm/res/network/virtual-network:0.5.1' = {
  name: 'deploy-${vnetName}'
  params: {
    name: vnetName
    location: location
    tags: tags
    lock: vnetLock
    addressPrefixes: vnetAddressPrefixes
    subnets: map(subnets, subnet => {
      name: subnet.name
      addressPrefix: subnet.addressPrefix
      networkSecurityGroupResourceId: nsg.outputs.resourceId
    })
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output nsgResourceId string = nsg.outputs.resourceId
output vnetResourceId string = vnet.outputs.resourceId
