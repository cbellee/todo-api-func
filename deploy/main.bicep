param location string
param appName string
param environment string
param sqlAdminUserName string = 'sqladmin'
param containerImageName string
param acrName string
param sqlDbName string = 'todosDb'

@secure()
param sqlAdminUserPassword string

var prefix = uniqueString(resourceGroup().id)
var funcAppName = '${prefix}-${environment}-${appName}'
var userManagedIdentityName = '${prefix}-umid'
var funcStorageAccountName = '${prefix}stor'
var hostingPlanName = '${prefix}-asp'
var appInsightsName = '${prefix}-ai'
var sqlServerName = '${prefix}-sql-server'
var vnetName = '${prefix}-vnet'
var dbCxnString = 'server=${sqlServer.properties.fullyQualifiedDomainName};user id=${sqlAdminUserName};password=${sqlAdminUserPassword};port=1433;database=${sqlDbName}'
var acrPullRoleDefinitionId = resourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var tags = {
  environment: environment
  costCenter: '1234567890'
}

resource acr 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' existing = {
  name: acrName
}

resource userManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: userManagedIdentityName
  location: location
}

resource userManagedIdentityRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, acr.id, acrPullRoleDefinitionId)
  scope: acr
  properties: {
    principalId: userManagedIdentity.properties.principalId
    roleDefinitionId: acrPullRoleDefinitionId
  }
  dependsOn: [
    acr
    userManagedIdentity
  ]
}
resource vnet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'vnetIntegrationSubnet'
        properties: {
          addressPrefix: '10.0.0.0/24'
          delegations: [
            {
              name: 'appSvcDelegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          serviceEndpoints: [
            {
              locations: [
                location
              ]
              service: 'Microsoft.Sql'
            }
          ]
        }
      }
    ]
  }
}

resource sqlServer 'Microsoft.Sql/servers@2021-11-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminUserName
    administratorLoginPassword: sqlAdminUserPassword
    publicNetworkAccess: 'Enabled'
  }
}

resource sqlServerVnetRules 'Microsoft.Sql/servers/virtualNetworkRules@2021-11-01-preview' = {
  parent: sqlServer
  name: 'firewall'
  properties: {
    virtualNetworkSubnetId: vnet.properties.subnets[0].id
  }
}

resource sqlDb 'Microsoft.Sql/servers/databases@2021-11-01-preview' = {
  location: location
  name: sqlDbName
  parent: sqlServer
  sku: {
    name: 'Basic'
  }
  properties: {
    requestedBackupStorageRedundancy: 'Local'
  }
  tags: tags
}

resource funcStorageAccount 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: funcStorageAccountName
  kind: 'StorageV2'
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    supportsHttpsTrafficOnly: true
  }
}

resource hostingPlan 'Microsoft.Web/serverfarms@2020-06-01' = {
  name: hostingPlanName
  location: location
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
  }
  kind: 'elastic'
  properties: {
    reserved: true
    maximumElasticWorkerCount: 20
  }
}

resource funcApp 'Microsoft.Web/sites@2021-01-01' = {
  dependsOn: [
    appInsights
  ]
  name: funcAppName
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userManagedIdentity.id}': {}
    }
  }
  kind: 'functionapp,linux'
  location: location
  tags: {}
  properties: {
    siteConfig: {
      vnetRouteAllEnabled: false
      acrUseManagedIdentityCreds: true
      acrUserManagedIdentityID: userManagedIdentity.properties.clientId
      linuxFxVersion: 'DOCKER|${containerImageName}'
      appSettings: [
        {
          name: 'DSN'
          value: dbCxnString // KeyVault reference doesn't seem to work for custom container images? '@Microsoft.KeyVault(SecretUri=${secret.properties.secretUri})'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: reference('microsoft.insights/components/${appInsightsName}', '2015-05-01').InstrumentationKey
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${funcStorageAccount.name};AccountKey=${listKeys(funcStorageAccount.id, '2019-06-01').keys[0].value};'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${funcStorageAccount.name};AccountKey=${listKeys(funcStorageAccount.id, '2019-06-01').keys[0].value};'
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE' // https://github.com/Azure/Azure-Functions/wiki/When-and-Why-should-I-set-WEBSITE_ENABLE_APP_SERVICE_STORAGE
          value: 'false'
        }
      ]
      use32BitWorkerProcess: false
    }
    serverFarmId: hostingPlan.id
    clientAffinityEnabled: false
  }
}

resource vnetIntegration 'Microsoft.Web/sites/networkConfig@2021-03-01' = {
  name: 'virtualNetwork'
  parent: funcApp
  properties: {
    subnetResourceId: vnet.properties.subnets[0].id
    swiftSupported: true
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: appInsightsName
  kind: 'web'
  location: location
  tags: {}
  properties: {
    Application_Type: 'web'
  }
}

output functionFqdn string = funcApp.properties.defaultHostName
output dbName string = sqlDb.name
