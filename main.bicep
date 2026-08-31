// =========== main.bicep ===========
targetScope = 'subscription'

@allowed(['dev', 'staging', 'production'])
param environment string

param location string = deployment().location

var resourceGroupName = 'rg-bicep-github-actions-${environment}'

resource rg 'Microsoft.Resources/resourceGroups@2021-01-01' = {
  name: resourceGroupName
  location: location
  tags: {
    environment: environment
    source: 'bicep-github-actions'
  }
}
