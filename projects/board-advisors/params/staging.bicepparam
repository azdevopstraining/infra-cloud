using '../main.bicep'

param environment = 'staging'
param location = 'eastus'
param resourceGroupName = 'rg-bicep-github-actions-staging'
param resourceGroupTags = {
  environment: 'staging'
  source: 'bicep-github-actions'
}
