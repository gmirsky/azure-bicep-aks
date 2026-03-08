using './main.bicep'

param location = 'eastus2'
param namePrefix = 'corpaks'
param tags = {
  Environment: 'Production'
  CostCenter: 'Platform'
  Owner: 'CloudPlatformTeam'
}

param kubernetesVersion = ''
param adminUsername = 'azureuser'
param jumpboxSshPublicKey = 'ssh-rsa REPLACE_WITH_YOUR_PUBLIC_KEY'

param vnetAddressPrefix = '10.42.0.0/16'
param aksSubnetPrefix = '10.42.0.0/22'
param bastionSubnetPrefix = '10.42.4.0/26'
param jumpboxSubnetPrefix = '10.42.4.64/27'

param serviceCidr = '10.43.0.0/16'
param dnsServiceIP = '10.43.0.10'
param dnsPrefix = ''

param enableSpotPool = true

param systemPoolVmSize = 'Standard_D4s_v5'
param userPoolVmSize = 'Standard_D4s_v5'
param spotPoolVmSize = 'Standard_D4as_v5'

param systemPoolMinCount = 3
param systemPoolMaxCount = 6
param userPoolMinCount = 2
param userPoolMaxCount = 10
param spotPoolMinCount = 0
param spotPoolMaxCount = 10

param acrSku = 'Premium'
param enablePrivateEndpoints = true
param enableDefender = true
param enableManagedPrometheus = true
param enableGrafanaPublicAccess = false
param bastionSku = 'Premium'
param enablePrivateOnlyBastion = true

param monitorWorkspaceName = 'corpaks-amw'
param logAnalyticsWorkspaceName = 'corpaks-law'
param grafanaName = 'corpaks-graf'
param acrName = 'corpaksacr'
param keyVaultName = 'corpakskv1234567890'
param aksName = 'corpaks-aks'
param jumpboxVmName = 'corpaks-jump'
