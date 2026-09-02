// =========== main.bicep ===========
targetScope = 'subscription'

@allowed(['dev', 'staging', 'production'])
param environment string

param location string = deployment().location

@description('Name of the resource group to create or update.')
param resourceGroupName string = 'rg-project-${environment}'

@description('Tags applied to the resource group.')
param resourceGroupTags object = {
  environment: environment
  source: 'bicep-github-actions'
}

module rg 'modules/resource-group.bicep' = {
  name: 'rg-${environment}'
  params: {
    name: resourceGroupName
    location: location
    tags: resourceGroupTags
  }
}
