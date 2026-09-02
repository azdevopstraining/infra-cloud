# board-advisors

Subscription-scoped Bicep that creates an Azure resource group per environment. The group is defined in a reusable module; each environment supplies its name, location, and tags through a `.bicepparam` file.

## Layout

```text
board-advisors/
├── main.bicep                          # Orchestrator (subscription scope)
├── modules/
│   └── resource-group.bicep            # Resource group module
├── params/
│   ├── dev.bicepparam
│   ├── staging.bicepparam
│   └── prod.bicepparam
└── .github/workflows/
    └── multistage-cicd-pipeline.yml
```

`main.bicep` does not declare the resource group inline. It calls `modules/resource-group.bicep` and forwards values from the param file.

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `environment` | Target environment: `dev`, `staging`, or `production` | required |
| `location` | Azure region for the resource group | `deployment().location` |
| `resourceGroupName` | Resource group name | `rg-bicep-github-actions-${environment}` |
| `resourceGroupTags` | Tags applied to the resource group | `environment`, `source: bicep-github-actions` |

Current values in the param files:

| Environment | Param file | Resource group | Location |
|-------------|------------|----------------|----------|
| dev | `params/dev.bicepparam` | `rg-bicep-github-actions-dev` | eastus |
| staging | `params/staging.bicepparam` | `rg-bicep-github-actions-staging` | eastus |
| production | `params/prod.bicepparam` | `rg-bicep-github-actions-production` | eastus |

Change the group name, region, or tags in the matching param file. Do not add a separate `.bicepparam` for the module; modules receive values from `main.bicep`.

## Local deploy

Prerequisite: Azure CLI with the Bicep extension, and a subscription you can deploy to.

```bash
az login
az account set --subscription <subscription-id>

# Preview
az deployment sub what-if \
  --name whatif-dev \
  --location westus \
  --template-file main.bicep \
  --parameters params/dev.bicepparam

# Deploy
az deployment sub create \
  --name deploy-dev \
  --location westus \
  --template-file main.bicep \
  --parameters params/dev.bicepparam
```

`--location` on the `az deployment sub` command is the subscription deployment location. The resource group region comes from `location` in the param file.

Swap `params/dev.bicepparam` for `params/staging.bicepparam` or `params/prod.bicepparam` to target another environment.

Compile without deploying:

```bash
az bicep build --file main.bicep
```

## CI/CD

The workflow `.github/workflows/multistage-cicd-pipeline.yml` runs on pull requests to `main`, pushes to `main`, and manual `workflow_dispatch`.

1. **Lint and security scan** — `az bicep build` and Checkov.
2. **Preview (dev)** — subscription validate and what-if using `params/dev.bicepparam`. What-if output is posted to the PR and the job summary.
3. **Deploy** — on merge to `main`, deploys **dev → staging → production** one environment at a time. A manual run can target a single environment.

Azure login uses OIDC (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`). GitHub Environments must be named exactly `dev`, `staging`, and `production`. Enable required reviewers on those environments for approval gates.

## Adding resources in the group

Scope later modules to the group created by this template so they wait for it:

```bicep
module storage 'modules/storage.bicep' = {
  name: 'storage-${environment}'
  scope: resourceGroup(rg.outputs.name)
  params: {
    location: rg.outputs.location
  }
}
```

The resource group module outputs `name`, `id`, and `location`.
