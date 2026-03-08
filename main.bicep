targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Environment prefix used in resource names. Keep short to satisfy naming limits.')
param namePrefix string = 'aksprod'

@description('Tags applied to all resources.')
param tags object = {
  Environment: 'Production'
  ManagedBy: 'Bicep'
  Workload: 'AKS'
}

@description('AKS version. Use an empty string to deploy the regional default.')
param kubernetesVersion string = ''

@description('Optional SSH public key for the private jumpbox VM in OpenSSH format.')
param jumpboxSshPublicKey string

@description('Admin username used by AKS Linux profile and jumpbox VM.')
param adminUsername string = 'azureuser'

@description('Virtual network CIDR block.')
param vnetAddressPrefix string = '10.42.0.0/16'

@description('Subnet CIDR used by AKS nodes.')
param aksSubnetPrefix string = '10.42.0.0/22'

@description('Subnet CIDR used by Azure Bastion. Must be /26 or larger.')
param bastionSubnetPrefix string = '10.42.4.0/26'

@description('Subnet CIDR used by the jumpbox VM.')
param jumpboxSubnetPrefix string = '10.42.4.64/27'

@description('Kubernetes service CIDR.')
param serviceCidr string = '10.43.0.0/16'

@description('Kubernetes DNS service IP. Must be inside serviceCidr.')
param dnsServiceIP string = '10.43.0.10'

@description('AKS DNS prefix. If empty, defaults to the cluster name.')
param dnsPrefix string = ''

@description('Enable optional spot worker node pool.')
param enableSpotPool bool = true

@description('System node pool VM size.')
param systemPoolVmSize string = 'Standard_D4s_v5'

@description('User node pool VM size.')
param userPoolVmSize string = 'Standard_D4s_v5'

@description('Spot node pool VM size.')
param spotPoolVmSize string = 'Standard_D4as_v5'

@description('System node pool minimum node count.')
param systemPoolMinCount int = 3

@description('System node pool maximum node count.')
param systemPoolMaxCount int = 6

@description('User node pool minimum node count.')
param userPoolMinCount int = 2

@description('User node pool maximum node count.')
param userPoolMaxCount int = 10

@description('Spot node pool minimum node count.')
param spotPoolMinCount int = 0

@description('Spot node pool maximum node count.')
param spotPoolMaxCount int = 10

@description('ACR SKU.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Premium'

@description('Enable private endpoint based access for ACR and Key Vault.')
param enablePrivateEndpoints bool = true

@description('Enable Defender profile for AKS.')
param enableDefender bool = true

@description('Enable managed Prometheus on AKS.')
param enableManagedPrometheus bool = true

@description('Allow Managed Grafana public network access. Disabled by default.')
param enableGrafanaPublicAccess bool = false

@description('Bastion SKU for jump host access.')
@allowed([
  'Standard'
  'Premium'
])
param bastionSku string = 'Premium'

@description('Name of the monitor workspace.')
param monitorWorkspaceName string = '${namePrefix}-amw'

@description('Name of the log analytics workspace.')
param logAnalyticsWorkspaceName string = '${namePrefix}-law'

@description('Name of the managed Grafana instance.')
param grafanaName string = '${namePrefix}-graf'

@description('Name of the ACR instance.')
param acrName string = take(replace('${namePrefix}acr', '-', ''), 50)

@description('Name of the Key Vault instance. Must be globally unique.')
param keyVaultName string = take(replace('${namePrefix}kv${uniqueString(subscription().id, resourceGroup().id)}', '-', ''), 24)

@description('Name of the AKS cluster.')
param aksName string = '${namePrefix}-aks'

@description('Name of the jumpbox VM.')
param jumpboxVmName string = '${namePrefix}-jump'

var vnetName = '${namePrefix}-vnet'
var bastionPublicIpName = '${namePrefix}-bas-pip'
var bastionName = '${namePrefix}-bas'
var jumpboxNicName = '${jumpboxVmName}-nic'
var jumpboxNsgName = '${jumpboxVmName}-nsg'
var jumpboxOsDiskName = '${jumpboxVmName}-osdisk'

var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var keyVaultSecretsUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
var monitoringReaderRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')

resource vnet 'Microsoft.Network/virtualNetworks@2022-09-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'aks-subnet'
        properties: {
          addressPrefix: aksSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
      {
        name: 'jumpbox-subnet'
        properties: {
          addressPrefix: jumpboxSubnetPrefix
          networkSecurityGroup: {
            id: jumpboxNsg.id
          }
        }
      }
    ]
  }
}

resource jumpboxNsg 'Microsoft.Network/networkSecurityGroups@2022-09-01' = {
  name: jumpboxNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowSshFromBastionSubnet'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 100
          protocol: 'Tcp'
          sourceAddressPrefix: bastionSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2022-09-01' = {
  name: bastionPublicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-11-01' = {
  name: bastionName
  location: location
  tags: tags
  sku: {
    name: bastionSku
  }
  properties: {
    enableTunneling: true
    enableShareableLink: false
    ipConfigurations: [
      {
        name: 'bastion-ip-config'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/AzureBastionSubnet'
          }
          publicIPAddress: {
            id: bastionPublicIp.id
          }
        }
      }
    ]
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource monitorWorkspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: monitorWorkspaceName
  location: location
  tags: tags
  properties: {}
}

resource grafana 'Microsoft.Dashboard/grafana@2023-09-01' = {
  name: grafanaName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    apiKey: 'Disabled'
    deterministicOutboundIP: 'Enabled'
    publicNetworkAccess: enableGrafanaPublicAccess ? 'Enabled' : 'Disabled'
    zoneRedundancy: 'Enabled'
    grafanaIntegrations: {
      azureMonitorWorkspaceIntegrations: [
        {
          azureMonitorWorkspaceResourceId: monitorWorkspace.id
        }
      ]
    }
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2022-12-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Disabled'
    networkRuleBypassOptions: 'AzureServices'
    policies: {
      quarantinePolicy: {
        status: 'enabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'enabled'
      }
      exportPolicy: {
        status: 'disabled'
      }
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'premium'
    }
    enableRbacAuthorization: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 90
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

resource acrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-09-01' = if (enablePrivateEndpoints) {
  name: '${acrName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: '${vnet.id}/subnets/aks-subnet'
    }
    privateLinkServiceConnections: [
      {
        name: '${acrName}-pls'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
}

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-09-01' = if (enablePrivateEndpoints) {
  name: '${keyVaultName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: '${vnet.id}/subnets/aks-subnet'
    }
    privateLinkServiceConnections: [
      {
        name: '${keyVaultName}-pls'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource acrPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enablePrivateEndpoints) {
  name: 'privatelink.azurecr.io'
  location: 'global'
  tags: tags
}

resource keyVaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enablePrivateEndpoints) {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}

resource acrPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enablePrivateEndpoints) {
  name: '${vnetName}-link'
  parent: acrPrivateDnsZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

resource keyVaultPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enablePrivateEndpoints) {
  name: '${vnetName}-link'
  parent: keyVaultPrivateDnsZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

resource acrPrivateEndpointZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-09-01' = if (enablePrivateEndpoints) {
  name: 'default'
  parent: acrPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'acr-private-dns'
        properties: {
          privateDnsZoneId: acrPrivateDnsZone.id
        }
      }
    ]
  }
}

resource keyVaultPrivateEndpointZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-09-01' = if (enablePrivateEndpoints) {
  name: 'default'
  parent: keyVaultPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'keyvault-private-dns'
        properties: {
          privateDnsZoneId: keyVaultPrivateDnsZone.id
        }
      }
    ]
  }
}

resource jumpboxNic 'Microsoft.Network/networkInterfaces@2022-09-01' = {
  name: jumpboxNicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnet.id}/subnets/jumpbox-subnet'
          }
        }
      }
    ]
  }
}

resource jumpboxVm 'Microsoft.Compute/virtualMachines@2022-11-01' = {
  name: jumpboxVmName
  location: location
  tags: tags
  properties: {
    securityProfile: {
      encryptionAtHost: true
    }
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: jumpboxVmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: jumpboxSshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: jumpboxOsDiskName
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: jumpboxNic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

var baseAgentPools = [
  {
    name: 'sysnp'
    mode: 'System'
    type: 'VirtualMachineScaleSets'
    vmSize: systemPoolVmSize
    vnetSubnetID: '${vnet.id}/subnets/aks-subnet'
    orchestratorVersion: empty(kubernetesVersion) ? null : kubernetesVersion
    osType: 'Linux'
    osSKU: 'AzureLinux'
    enableAutoScaling: true
    minCount: systemPoolMinCount
    maxCount: systemPoolMaxCount
    count: systemPoolMinCount
    maxPods: 50
    osDiskType: 'Ephemeral'
    enableEncryptionAtHost: true
    nodeLabels: {
      role: 'system'
    }
    nodeTaints: [
      'CriticalAddonsOnly=true:NoSchedule'
    ]
  }
  {
    name: 'usernp'
    mode: 'User'
    type: 'VirtualMachineScaleSets'
    vmSize: userPoolVmSize
    vnetSubnetID: '${vnet.id}/subnets/aks-subnet'
    orchestratorVersion: empty(kubernetesVersion) ? null : kubernetesVersion
    osType: 'Linux'
    osSKU: 'AzureLinux'
    enableAutoScaling: true
    minCount: userPoolMinCount
    maxCount: userPoolMaxCount
    count: userPoolMinCount
    maxPods: 50
    osDiskType: 'Ephemeral'
    enableEncryptionAtHost: true
    nodeLabels: {
      role: 'user'
    }
  }
]

var spotAgentPool = {
  name: 'spotnp'
  mode: 'User'
  type: 'VirtualMachineScaleSets'
  vmSize: spotPoolVmSize
  vnetSubnetID: '${vnet.id}/subnets/aks-subnet'
  orchestratorVersion: empty(kubernetesVersion) ? null : kubernetesVersion
  osType: 'Linux'
  osSKU: 'AzureLinux'
  enableAutoScaling: true
  minCount: spotPoolMinCount
  maxCount: spotPoolMaxCount
  count: spotPoolMinCount
  maxPods: 50
  osDiskType: 'Ephemeral'
  enableEncryptionAtHost: true
  scaleSetPriority: 'Spot'
  scaleSetEvictionPolicy: 'Delete'
  spotMaxPrice: -1
  nodeLabels: {
    role: 'spot'
    lifecycle: 'spot'
  }
  nodeTaints: [
    'kubernetes.azure.com/scalesetpriority=spot:NoSchedule'
  ]
}

var allAgentPools = enableSpotPool ? concat(baseAgentPools, [spotAgentPool]) : baseAgentPools

resource aks 'Microsoft.ContainerService/managedClusters@2023-05-01' = {
  name: aksName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Base'
    tier: 'Standard'
  }
  properties: {
    kubernetesVersion: empty(kubernetesVersion) ? null : kubernetesVersion
    dnsPrefix: empty(dnsPrefix) ? aksName : dnsPrefix
    supportPlan: 'KubernetesOfficial'
    disableLocalAccounts: true
    publicNetworkAccess: 'Disabled'
    enableRBAC: true
    apiServerAccessProfile: {
      enablePrivateCluster: true
      enablePrivateClusterPublicFQDN: false
      authorizedIPRanges: []
    }
    linuxProfile: {
      adminUsername: adminUsername
      ssh: {
        publicKeys: [
          {
            keyData: jumpboxSshPublicKey
          }
        ]
      }
    }
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      adminGroupObjectIDs: []
    }
    autoUpgradeProfile: {
      upgradeChannel: 'stable'
    }
    oidcIssuerProfile: {
      enabled: true
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      dnsServiceIP: dnsServiceIP
      serviceCidr: serviceCidr
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }
    agentPoolProfiles: allAgentPools
    addonProfiles: {
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
      azurepolicy: {
        enabled: true
      }
      kubeDashboard: {
        enabled: false
      }
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalytics.id
          useAADAuth: 'true'
        }
      }
    }
    securityProfile: {
      defender: {
        securityMonitoring: {
          enabled: enableDefender
        }
      }
      workloadIdentity: {
        enabled: true
      }
      imageCleaner: {
        enabled: true
        intervalHours: 48
      }
    }
    azureMonitorProfile: {
      metrics: {
        enabled: enableManagedPrometheus
      }
    }
  }
}

resource aksToAcrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, aks.id, 'AcrPullRoleAssignment')
  scope: acr
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource aksToKeyVaultSecretsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, aks.id, 'KvSecretsUserRoleAssignment')
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
    principalId: aks.properties.addonProfiles.azureKeyvaultSecretsProvider.identity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource grafanaMonitoringReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(monitorWorkspace.id, grafana.id, 'GrafanaMonitoringReader')
  scope: monitorWorkspace
  properties: {
    roleDefinitionId: monitoringReaderRoleDefinitionId
    principalId: grafana.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output aksResourceId string = aks.id
output aksNameOut string = aks.name
output aksPrivateFqdn string = aks.properties.privateFQDN
output bastionNameOut string = bastion.name
output jumpboxPrivateIp string = jumpboxNic.properties.ipConfigurations[0].properties.privateIPAddress
output grafanaUrl string = grafana.properties.endpoint
output logAnalyticsWorkspaceId string = logAnalytics.id
output monitorWorkspaceId string = monitorWorkspace.id
output acrLoginServer string = acr.properties.loginServer
output keyVaultUri string = keyVault.properties.vaultUri
