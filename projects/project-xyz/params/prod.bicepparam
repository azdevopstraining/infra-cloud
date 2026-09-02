using '../main.bicep'

param environment = 'production'
param location = 'eastus'
param resourceGroupName = 'rg-project-production'
param resourceGroupTags = {
  environment: 'production'
  source: 'bicep-github-actions'
}
