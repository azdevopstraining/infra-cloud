# infra-cloud

This repository is the **Infrastructure as Code (IaC)** home for Azure resources.

Instead of creating resource groups (and later storage, networks, apps) by clicking in the Azure Portal, you describe them in **Bicep** files and let Azure create or update them. The same files can be deployed to **dev**, **staging**, and **production** by changing only a parameter file.

Think of it this way:

| Portal click | This repo |
|--------------|-----------|
| You create a resource group by hand | Bicep declares the group |
| You remember the name and region | A `.bicepparam` file stores them |
| You repeat the same clicks for staging and prod | You reuse the same template with a different param file |
| Nobody knows what changed last week | Git history + GitHub Actions show every change |

Remote: [azdevopstraining/infra-cloud](https://github.com/azdevopstraining/infra-cloud).

---

## What this repo does today

Right now each project deploys **one Azure resource group** per environment.

| Project | Folder | Dev group | Staging group | Production group |
|---------|--------|-----------|---------------|------------------|
| board-advisors | `projects/board-advisors/` | `rg-bicep-github-actions-dev` | `rg-bicep-github-actions-staging` | `rg-bicep-github-actions-production` |
| project-xyz | `projects/project-xyz/` | `rg-project-dev` | `rg-project-staging` | `rg-project-production` |

All of those groups are created in **eastus** (set in the param files). Later you can add more modules (storage, Key Vault, and so on) under the same group without changing this overall pattern.

---

## Why the repo is split by project

`projects/` holds one folder per application or workload.

- **board-advisors** and **project-xyz** do not share a resource group.
- Each project has its own `main.bicep`, param files, module, and pipeline.
- You can add `projects/another-app/` later without mixing names or tags.

That keeps ownership clear: change board-advisors infrastructure in its folder; leave project-xyz alone.

---

## Full folder map

```text
infra-cloud/
├── README.md                          ← this file (repo overview)
└── projects/
    ├── board-advisors/
    │   ├── main.bicep                 ← entry point: calls modules
    │   ├── main.json                  ← compiled ARM (from az bicep build)
    │   ├── modules/
    │   │   └── resource-group.bicep   ← creates the Azure resource group
    │   ├── params/
    │   │   ├── dev.bicepparam         ← values for the dev group
    │   │   ├── staging.bicepparam     ← values for the staging group
    │   │   └── prod.bicepparam        ← values for the production group
    │   └── .github/workflows/
    │       └── multistage-cicd-pipeline.yml
    └── project-xyz/
        ├── main.bicep
        ├── main.json
        ├── modules/
        │   └── resource-group.bicep
        ├── params/
        │   ├── dev.bicepparam
        │   ├── staging.bicepparam
        │   └── prod.bicepparam
        └── .github/workflows/
            └── multistage-cicd-pipeline.yml
```

Both projects follow the **same pattern**. Only the resource group names differ.

---

## Important words (read this first)

**Bicep**  
A language from Microsoft for Azure resources. It is easier to read than raw ARM JSON. Azure still converts Bicep to ARM JSON before deploying.

**ARM template (`main.json`)**  
The compiled form of `main.bicep`. Created when you run `az bicep build --file main.bicep`. You edit `.bicep` files, not this JSON.

**Subscription scope**  
A resource group is an Azure subscription object, not something that lives *inside* another group. That is why `main.bicep` and `resource-group.bicep` start with:

```bicep
targetScope = 'subscription'
```

Deployments therefore use `az deployment sub ...` (subscription), not `az deployment group ...` (inside a group).

**Module**  
A separate `.bicep` file that `main.bicep` calls. One job per file (here: “create a resource group”). `main.bicep` is the orchestrator; modules do the work.

**Parameter file (`.bicepparam`)**  
A list of values for one environment. The template stays the same; only these values change.

```bicep
using '../main.bicep'          // “these values belong to main.bicep”

param environment = 'dev'
param location = 'eastus'
param resourceGroupName = 'rg-project-dev'
```

Modules do **not** have their own param files. `main.bicep` reads the env file and **forwards** `name`, `location`, and `tags` into the module.

**What-if**  
A dry run. Azure tells you what it *would* create, change, or delete. Nothing is applied.

**OIDC**  
GitHub Actions logs into Azure with a federated identity. There is no long-lived password in the repo. The workflow uses three secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.

---

## How a deploy actually works

One flow, every time:

```text
  params/dev.bicepparam
           │
           │  environment, location, resourceGroupName, resourceGroupTags
           ▼
       main.bicep
           │
           │  module rg 'modules/resource-group.bicep'
           ▼
  modules/resource-group.bicep
           │
           │  Microsoft.Resources/resourceGroups
           ▼
     Azure subscription
           │
           ▼
  Resource group exists (or is updated)
```

1. You (or the pipeline) pick a param file, for example `params/dev.bicepparam`.
2. Azure CLI runs a **subscription** deployment of `main.bicep` with those parameters.
3. `main.bicep` calls the resource group module and passes name, location, and tags.
4. The module creates or updates that group in Azure.
5. The module returns `name`, `id`, and `location` so later modules can deploy *into* that group.

If you deploy again with the same values, Azure sees no change and does nothing harmful. Bicep is **idempotent**: run it many times; you get the same result.

---

## File-by-file: what each file is for

### `main.bicep` (the orchestrator)

This is the only file you point Azure CLI or the pipeline at.

| Line / idea | Purpose |
|-------------|---------|
| `targetScope = 'subscription'` | Deploy at subscription level so a resource group can be created. |
| `param environment` | Must be `dev`, `staging`, or `production`. |
| `param location` | Region for the group. Default is the deployment location if a param file omits it. |
| `param resourceGroupName` | The actual Azure name. Default is project-specific if the param file omits it. |
| `param resourceGroupTags` | Tags on the group (`environment`, `source`). |
| `module rg 'modules/resource-group.bicep'` | Calls the reusable module instead of declaring the group inline. |

`name: 'rg-${environment}'` on the module is the **nested deployment name** in Azure (a label for that module run). It is not the resource group name. The group name is `params.name` → `resourceGroupName`.

### `modules/resource-group.bicep` (the worker)

This file only knows how to create a resource group. It does not know about “dev” or “board-advisors”.

| Piece | Purpose |
|-------|---------|
| `param name` | Group name, from `main.bicep`. |
| `param location` | Azure region. |
| `param tags` | Optional tags (default empty object). |
| `resource rg 'Microsoft.Resources/resourceGroups@2021-01-01'` | The real Azure resource. |
| `output name / id / location` | Values the parent (or later modules) can use. |

Why a module instead of putting the resource in `main.bicep`?

- One file, one job — easier to read and reuse.
- The same module can be called from another project’s `main.bicep`.
- Later resources (storage, Key Vault) become more modules; `main.bicep` just lists them.

### `params/*.bicepparam` (environment values)

| File | When to use it |
|------|----------------|
| `params/dev.bicepparam` | Local tests and the pipeline’s preview + first deploy |
| `params/staging.bicepparam` | Staging after dev |
| `params/prod.bicepparam` | Production (file is named `prod`, environment value is `production`) |

Example (`projects/board-advisors/params/dev.bicepparam`):

```bicep
using '../main.bicep'

param environment = 'dev'
param location = 'eastus'
param resourceGroupName = 'rg-bicep-github-actions-dev'
param resourceGroupTags = {
  environment: 'dev'
  source: 'bicep-github-actions'
}
```

To rename a group or move it to another region, edit **this file**, not the module.

**Two different “locations”**

- `location` in the param file → where the **resource group** is created (`eastus`).
- `--location westus` on `az deployment sub` → where Azure stores the **deployment record**. That is metadata, not the group’s region.

### `main.json`

Output of `az bicep build`. Azure Resource Manager understands this JSON. You do not edit it by hand. Safe to regenerate after you change Bicep. You can commit it or ignore it; the source of truth is `.bicep`.

### `.github/workflows/multistage-cicd-pipeline.yml`

The GitHub Actions workflow that lints, previews, and deploys. Each project has a copy. See [CI/CD](#cicd-the-pipeline-explained) below.

> **Monorepo note:** GitHub only auto-runs workflows in the **repository root** folder `.github/workflows/`. These YAML files currently live under each project. If this stays one git repo, copy or move the workflow to the repo root (or add a root workflow that calls them) so Actions actually runs. If each project later becomes its own repo, the current path is correct.

---

## The two projects

### board-advisors

| Item | Value |
|------|--------|
| Folder | `projects/board-advisors/` |
| Default name pattern | `rg-bicep-github-actions-${environment}` |
| Dev | `rg-bicep-github-actions-dev` |
| Staging | `rg-bicep-github-actions-staging` |
| Production | `rg-bicep-github-actions-production` |
| Region | eastus |

### project-xyz

| Item | Value |
|------|--------|
| Folder | `projects/project-xyz/` |
| Default name pattern | `rg-project-${environment}` |
| Dev | `rg-project-dev` |
| Staging | `rg-project-staging` |
| Production | `rg-project-production` |
| Region | eastus |

Same code shape, different names so the two workloads do not collide in Azure.

---

## Deploy from your laptop

You need Azure CLI with the Bicep extension and rights to create resource groups on the subscription.

```bash
az login
az account set --subscription <subscription-id>
cd projects/board-advisors
```

**Compile (no Azure changes):**

```bash
az bicep build --file main.bicep
```

**Preview:**

```bash
az deployment sub what-if \
  --name whatif-dev \
  --location westus \
  --template-file main.bicep \
  --parameters params/dev.bicepparam
```

**Create or update:**

```bash
az deployment sub create \
  --name deploy-dev \
  --location westus \
  --template-file main.bicep \
  --parameters params/dev.bicepparam
```

Use `params/staging.bicepparam` or `params/prod.bicepparam` for the other environments. For project-xyz, `cd projects/project-xyz` first.

---

## CI/CD: the pipeline explained

File: `projects/<name>/.github/workflows/multistage-cicd-pipeline.yml`.

### When it runs

| Trigger | What happens |
|---------|----------------|
| Pull request to `main` | Lint, scan, and what-if against **dev**. No deploy. |
| Push / merge to `main` | Same preview, then deploy **dev → staging → production** one at a time. |
| Manual **Run workflow** | You pick one environment and only that one deploys. |

OIDC federated credentials are tied to specific branches, so the workflow is limited to `main` and PRs into `main` (no branch wildcards).

### Job 1 — Lint and security scan

- `az bicep build --file main.bicep` — template must compile.
- [Checkov](https://www.checkov.io/) — static checks for risky Bicep.
- Uploads a SARIF report to GitHub so findings show on the PR.

This job uses a **self-hosted** runner labeled `self-hosted, linux, ubuntu, azure`.

### Job 2 — Preview (dev)

Runs after lint. Logs in with OIDC (`environment: dev`).

1. `az deployment sub validate` — Azure accepts the template and params.
2. `az deployment sub what-if` — planned changes, written to a file.
3. That report is added to the job summary and, on a PR, posted as a comment.

This is the “show me what would happen” step before anyone merges.

### Job 3 — Plan deploy targets

Builds a **matrix** of environments:

- Merge to `main` → all three (`dev`, `staging`, `production`).
- Manual run → only the environment you selected.  
  `production` uses `params/prod.bicepparam` (file name ≠ environment name).

PRs still run this job so the graph stays complete, but the next job skips deploy on PRs.

### Job 4 — Deploy

Runs only on `push` to `main` or `workflow_dispatch`.

- `max-parallel: 1` and `fail-fast: true` → **dev, then staging, then production**. If staging fails, production does not start.
- Each matrix row uses a GitHub Environment with the same name (`dev`, `staging`, `production`) so you can add **required reviewers** in GitHub (Settings → Environments). Approvals are not in the YAML; you turn them on in the UI.
- Each environment logs in again (OIDC subject includes that environment name).
- What-if runs once more, then `az deployment sub create`.

### Secrets the pipeline expects

Set these on the GitHub repo or on each Environment:

| Secret | Meaning |
|--------|---------|
| `AZURE_CLIENT_ID` | App registration (service principal) client ID |
| `AZURE_TENANT_ID` | Microsoft Entra tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription |

The workflow also needs `id-token: write` so GitHub can mint the OIDC token.

---

## Adding more Azure resources later

The resource group module already outputs `name`, `id`, and `location`. A child module must run **inside** that group, so you set `scope`:

```bicep
module storage 'modules/storage.bicep' = {
  name: 'storage-${environment}'
  scope: resourceGroup(rg.outputs.name)
  params: {
    location: rg.outputs.location
  }
}
```

`scope: resourceGroup(rg.outputs.name)` does two things:

1. Deploys the child at **resource group** scope (normal for storage, apps, and so on).
2. Waits until the group module has finished, so the group exists first.

---

## Adding a new project

1. Copy `projects/project-xyz/` (or board-advisors) to `projects/<new-name>/`.
2. Change `resourceGroupName` in each `params/*.bicepparam` so names stay unique.
3. Update the default in `main.bicep` if you want a new naming pattern.
4. Point the pipeline (or a root workflow) at that folder’s `main.bicep`.

Do not reuse another project’s group names.

---

## Quick troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| `az deployment group ...` fails | Resource groups need **subscription** deploy (`az deployment sub`). |
| Wrong group name in Azure | Check the env `.bicepparam`, not the module. |
| Group in the “wrong” region | Param `location` is the group region. `--location` on the CLI is only the deployment record. |
| GitHub Actions never runs | Workflow YAML is under `projects/.../.github/`, not the repo root. |
| Login fails in Actions | Missing OIDC secrets, or GitHub Environment name is not exactly `dev` / `staging` / `production`. |
| Production did not deploy | Staging failed (`fail-fast`), or this was a PR (deploy is skipped), or a reviewer has not approved. |

---

## Mental model (one sentence each)

- **This repo** = source of truth for Azure infrastructure.
- **`projects/<name>/`** = one workload’s infrastructure.
- **`main.bicep`** = “what to deploy and in what order.”
- **`modules/resource-group.bicep`** = “how to create a resource group.”
- **`params/*.bicepparam`** = “values for this environment.”
- **The pipeline** = lint → preview on PRs → deploy in order on merge.
- **Azure** = creates or updates the real resources to match the files.
