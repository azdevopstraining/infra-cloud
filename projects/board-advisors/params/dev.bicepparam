using '../main.bicep'

param environment = 'dev'
param location = 'eastus'
param resourceGroupName = 'rg-bicep-github-actions-dev'
param resourceGroupTags = {
  environment: 'dev'
  source: 'bicep-github-actions'
}
