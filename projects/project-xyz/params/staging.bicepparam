using '../main.bicep'

param environment = 'staging'
param location = 'eastus'
param resourceGroupName = 'rg-project-staging'
param resourceGroupTags = {
  environment: 'staging'
  source: 'bicep-github-actions'
}
