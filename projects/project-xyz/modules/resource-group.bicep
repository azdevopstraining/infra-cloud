targetScope = 'subscription'

@description('Name of the resource group to create or update.')
param name string

@description('Azure region for the resource group.')
param location string

@description('Tags applied to the resource group.')
param tags object = {}

resource rg 'Microsoft.Resources/resourceGroups@2021-01-01' = {
  name: name
  location: location
  tags: tags
}

output name string = rg.name
output id string = rg.id
output location string = rg.location
