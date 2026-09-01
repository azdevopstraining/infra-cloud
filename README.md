# infra-cloud — end-to-end guide

This repository deploys Azure infrastructure with **Bicep** from **GitHub Actions**. It logs into Azure with **OpenID Connect (OIDC)** / **workload identity federation**. There is no client secret in GitHub.

Read this document in order the first time. Each section builds on the previous one.

---

## 1. Words used in this pipeline

| Word | Meaning |
|---|---|
| **Workflow** | The YAML file that GitHub Actions runs. Ours is `.github/workflows/multistage-cicd-pipeline.yml`. The display name is `Bicep CI/CD`. |
| **Run** | One execution of that workflow (one row on the Actions tab). |
| **Trigger** | The event that starts a run: open/update a pull request, push/merge to `main`, or **Run workflow**. |
| **Job** | A block of work on its own virtual machine. Jobs can wait on other jobs (`needs`). |
| **Step** | One command or Action inside a job. Steps in a job run **top to bottom**. If a step fails, later steps in that job are skipped (unless the step has `if: success() \|\| failure()`). |
| **Action** | Reusable GitHub marketplace code, for example `actions/checkout@v3` or `azure/login@v1`. |
| **GitHub Environment** | A named bucket (`dev`, `staging`, `production`) that holds secrets and optional **required reviewers**. It is **not** an Azure region. |
| **OIDC / federated credential** | A trust rule: “GitHub may use this Azure identity only if the token’s subject matches.” |
| **Validate** | Azure checks whether the template *would* be accepted. Nothing is created. |
| **What-if** | Azure previews creates / updates / deletes. Nothing is created. |
| **Create** | Azure applies the template (`az deployment sub create`). This is the only step that builds real resources. |

---

## 2. What Azure gets from this repo

`main.bicep` deploys at **subscription** scope (`targetScope = 'subscription'`). It can create resource groups; it does not assume a group already exists.

It takes:

- `environment` — must be `dev`, `staging`, or `production`
- `location` — Azure region for the resource group

It creates **one resource group**:

| `environment` parameter | Resource group name |
|---|---|
| `dev` | `rg-bicep-github-actions-dev` |
| `staging` | `rg-bicep-github-actions-staging` |
| `production` | `rg-bicep-github-actions-production` |

Tags on the group: `environment` and `source: bicep-github-actions`.

Parameter files:

| File | Sets |
|---|---|
| `params/dev.bicepparam` | `environment = 'dev'` |
| `params/staging.bicepparam` | `environment = 'staging'` |
| `params/prod.bicepparam` | `environment = 'production'` |

`using '../main.bicep'` in each `.bicepparam` file means “these values belong to `main.bicep`.”

The workflow also sets `LOCATION: westus`. That value is passed as `--location` on `az deployment sub …`. At subscription scope, `--location` is where Azure stores the **deployment record**. The resource group’s region comes from the `location` parameter in the param file.

---

## 3. Repository files

```text
infra-cloud/
  main.bicep
  params/
    dev.bicepparam
    staging.bicepparam
    prod.bicepparam
  .github/workflows/
    multistage-cicd-pipeline.yml
  README.md
```

---

## 4. One-time setup (do this before the first green run)

Do these steps in this order. Skipping a step is the usual reason login or deploy fails.

### Step A — Azure: user-assigned managed identity

GitHub-hosted runners are not in your subscription, so use a **user-assigned** identity (not system-assigned on a VM).

1. Azure Portal → **Managed Identities** → **Create**.
2. Example names: `dev-mi`, `staging-mi`, `prod-mi` (one per environment is cleaner).
3. On **Overview**, copy:
   - **Client ID** → later `AZURE_CLIENT_ID` (never Principal ID)
   - You will still need tenant ID and subscription ID from the subscription

### Step B — Azure: Contributor role

1. **Subscriptions** → your subscription → **Access control (IAM)** → **Add role assignment**.
2. Role: **Contributor**.
3. Assign the managed identity (this uses **Principal ID** behind the scenes).
4. Wait a minute for RBAC to apply.

Without this, login can succeed and `validate` / `what-if` / `create` still fail.

### Step C — Azure: federated credentials (OIDC trust)

On each identity: **Federated credentials** → **Add credential**.

| Field | What to enter |
|---|---|
| Issuer URL | `https://token.actions.githubusercontent.com` (leave default) |
| Organization | GitHub user or org login, for example `azdevopstraining` |
| Organization ID | **Number** from the GitHub API, not the login name |
| Repository | `infra-cloud` (name only) |
| Repository ID | **Number** from the GitHub API |
| Entity | **Environment** |
| GitHub environment name | `dev` or `staging` or `production` (must match YAML) |
| Audience | `api://AzureADTokenExchange` (leave default) |

Look up IDs in a browser:

```text
https://api.github.com/users/OWNER
https://api.github.com/orgs/OWNER
https://api.github.com/repos/OWNER/infra-cloud
```

Use the `"id"` field. Example for [azdevopstraining/infra-cloud](https://github.com/azdevopstraining/infra-cloud):

- Organization / user: `azdevopstraining`
- Organization ID: `157454275`
- Repository: `infra-cloud`
- Repository ID: `1352027221`

You need **three** credentials if you have three environments (same repo IDs; entity name changes). Azure matches the subject **exactly**.

`azdevopstraining` is a GitHub **user**, not an org. The portal still labels the field Organization — put the username there.

### Step D — GitHub: Environments and secrets

Repo → **Settings** → **Environments** → create:

- `dev`
- `staging`
- `production`

Names must match YAML `environment:` and the federated credential entity.

On **each** environment, **Environment secrets** → add:

| Secret name | Value |
|---|---|
| `AZURE_CLIENT_ID` | That identity’s **Client ID** |
| `AZURE_TENANT_ID` | Entra **Directory (tenant) ID** |
| `AZURE_SUBSCRIPTION_ID` | Subscription ID |

Use environment secrets, not only repository secrets, so `dev` and `production` can use different client IDs.

### Step E — GitHub: required reviewers (approvals)

Still on each environment → **Deployment protection rules** → **Required reviewers**.

- Approvals are **not** written in YAML. The workflow only *names* the environment.
- Add at least one reviewer.
- To approve a run **you** started, leave **Prevent self-review** **off**.
- If **Prevent self-review** is on, another person must approve or the job waits forever.

Any job with `environment: dev` waits on `dev` reviewers. That includes **Validate and what-if (dev)**, not only **Deploy dev**. GitHub applies protection to the environment **name**, not to a single job.

---

## 5. How a workflow run starts (`on:`)

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:
```

| Trigger | When | Typical use |
|---|---|---|
| `pull_request` | PR opened or updated against `main` | Preview: lint, validate, what-if. **Does not** `az deployment sub create`. |
| `push` to `main` | Merge (or direct push) to `main` | Same jobs, **plus** create after approval. |
| `workflow_dispatch` | **Actions → Bicep CI/CD → Run workflow** | You pick one environment (`dev` / `staging` / `production`). Create runs (not a PR). |

Two runs for one change (PR, then merge) is **normal**. The PR run must not create resources. The merge run applies them.

`workflow_dispatch` input `environment` is a required choice: `dev`, `staging`, or `production`.

---

## 6. Shared workflow settings

### `env.LOCATION`

`LOCATION: "westus"` is a workflow variable. Jobs pass it as `--location $LOCATION` to Azure CLI subscription deployments.

### `permissions`

This limits what `GITHUB_TOKEN` and the OIDC token API can do. Unlisted permissions are denied.

| Permission | Meaning |
|---|---|
| `id-token: write` | Lets the job **request** a GitHub OIDC JWT. “Mint” = GitHub **creates and signs** that token. This is **not** Azure Contributor. Without it, `azure/login` fails even with correct secrets. |
| `contents: read` | Lets `actions/checkout` clone the repo (read-only). |
| `security-events: write` | Lets Checkov upload SARIF to GitHub code scanning. |
| `pull-requests: write` | Lets the workflow post the what-if comment on a PR. |

OIDC login path:

```text
Job has id-token: write
  → GitHub signs a JWT (repo, environment, …)
  → azure/login sends JWT to Entra
  → Entra matches a federated credential
  → Job gets a short-lived Azure token
  → az … runs as the managed identity
```

---

## 7. Jobs, in order (what waits on what)

```text
lint-and-scan
      │
      ▼
preview-dev          (needs lint-and-scan)
      │
      ▼
plan-deploy          (needs lint-and-scan AND preview-dev)
      │
      ▼
deploy (dev)         (needs plan-deploy; matrix; max-parallel: 1)
      │
      ▼
deploy (staging)
      │
      ▼
deploy (production)
```

If **lint-and-scan** fails, **preview-dev** is skipped (`needs`).  
If **preview-dev** fails, **plan-deploy** and **deploy** are skipped.

`deploy` uses a **matrix**. GitHub cannot use `matrix` in a job-level `if`, so **plan-deploy** writes the matrix JSON first. **deploy** reads it with `fromJson`.

`strategy.max-parallel: 1` means one environment at a time. `fail-fast: true` means if **dev** deploy fails, **staging** and **production** do not run.

---

## 8. Job 1 — Lint and security scan (`lint-and-scan`)

**Purpose:** Check Bicep **without Azure login**. No OIDC, no GitHub Environment.

**`runs-on: ubuntu-latest`:** GitHub starts a fresh Linux VM for this job.

### Step: Checkout (`actions/checkout@v3`)

Copies this repository onto the runner so `main.bicep` exists on disk.

### Step: Bicep Lint (`az bicep build --file main.bicep`)

Compiles Bicep to ARM JSON. Catches syntax errors, bad types, missing files. Does **not** talk to your subscription. Failure = the template cannot compile.

### Step: Run Checkov (`bridgecrewio/checkov-action`, `framework: bicep`)

Static security scan of Bicep (for example public storage, missing encryption). `id: checkov` names the step so outputs could be referenced. This is not Azure Policy.

### Step: Upload SARIF (`github/codeql-action/upload-sarif@v3`)

Uploads Checkov’s `results.sarif` to the repo **Security** tab.  
`if: success() || failure()` means upload even if Checkov failed, so findings still appear.  
`category: checkov` labels those alerts. Use **v3** (v1/v2 are deprecated).

Needs `security-events: write`. If GitHub Advanced Security is not enabled, this step may warn; lint can still succeed.

---

## 9. Job 2 — Validate and what-if (dev) (`preview-dev`)

**Purpose:** Ask Azure whether the **dev** template is valid and what would change. Does **not** run `az deployment sub create`.

**`needs: [lint-and-scan]`:** Runs only after lint succeeds.

**`environment: dev`:**

1. Loads secrets from GitHub Environment `dev`.
2. Sets OIDC subject to `environment:dev` (must match the federated credential).
3. If `dev` has required reviewers, this job **waits for approval** before steps start.

### Step: Checkout

Same as job 1: clone the repo.

### Step: Az CLI login (`azure/login@v1`)

OIDC login using:

- `client-id: ${{ secrets.AZURE_CLIENT_ID }}`
- `tenant-id: ${{ secrets.AZURE_TENANT_ID }}`
- `subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}`

These come from the **`dev`** environment secrets. After this, `az` commands run as `dev-mi` (or whichever identity that Client ID is).

### Step: Bicep Validate (`az deployment sub validate`)

| Flag | Meaning |
|---|---|
| `sub` | Subscription scope (matches `targetScope` in `main.bicep`) |
| `--name validate-dev-${{ github.run_id }}` | Unique name for this check (`run_id` is this Actions run) |
| `--template-file main.bicep` | Template to check |
| `--parameters params/dev.bicepparam` | `environment=dev` |
| `--location $LOCATION` | Deployment-record region (`westus`) |

Azure checks the template, parameters, and whether this identity **may** create the resources. Nothing is created.

### Step: What-If (`az deployment sub what-if`)

Same inputs as validate. Output is saved to a file named `whatif`. Preview only: Create / Ignore / Modify / Delete. Nothing is created.

### Step: Create String Output

Reads the `whatif` file and formats Markdown (collapsible details). Writes it to `$GITHUB_OUTPUT` as `summary` so later steps can reuse it. The random delimiter avoids breaking the output if the what-if text contains special characters.

### Step: Publish Whatif to Task Summary

Appends that Markdown to the Actions **job summary** (visible on the run page).

### Step: Push Whatif Output to PR

`if: github.event_name == 'pull_request'` — runs **only** on a PR. Posts the same Markdown as a PR comment (`pull-requests: write`). On push to `main` or a manual run, this step is skipped (there is no PR to comment on).

---

## 10. Job 3 — Plan deploy targets (`plan-deploy`)

**Purpose:** Decide **which** environments the **deploy** job should iterate. Does **not** call Azure.

**`needs: [lint-and-scan, preview-dev]`:** Both must succeed.

**`outputs.matrix`:** JSON consumed by the next job.

### Step: set-matrix

| `github.event_name` | Matrix |
|---|---|
| `workflow_dispatch` | One row: the environment you selected. `production` uses `params/prod.bicepparam`. |
| `pull_request` or `push` | Three rows: `dev`, `staging`, `production` with their param files. |

GitHub cannot put `matrix.environment` in a job-level `if`, so this job exists.

---

## 11. Job 4 — Deploy (`deploy`)

**Purpose:** For each planned environment: log in, what-if, and **create only if this is not a pull request**.

**`needs: [plan-deploy]`**

**`environment: name: ${{ matrix.environment }}`** — `dev`, then `staging`, then `production`. Each uses that environment’s secrets, OIDC subject, and reviewers.

**`strategy.matrix`:** From plan-deploy. **`max-parallel: 1`:** sequential. **`fail-fast: true`:** stop the chain on failure.

Job display name: `Deploy ${{ matrix.environment }}` (for example `Deploy dev`).

### Step: Checkout

Clone the repo again (new VM per job).

### Step: Az CLI login

Same as preview, but secrets come from **`dev` or `staging` or `production`**, matching the matrix row.

### Step: What-if (pre-deploy)

`az deployment sub what-if` with **that** environment’s param file. Second preview immediately before apply (or instead of apply on a PR).

### Step: Bicep Deployment

```yaml
if: github.event_name != 'pull_request'
```

| Event | This step |
|---|---|
| Pull request | **Skipped** — job still “succeeds”; Azure is not changed |
| Push to `main` | **Runs** `az deployment sub create` |
| `workflow_dispatch` | **Runs** `az deployment sub create` |

`az deployment sub create` is the **only** step that creates or updates `rg-bicep-github-actions-*`.

On a PR, seeing **Bicep Deployment** skipped is expected.

---

## 12. End-to-end: pull request

1. You open a PR into `main`.
2. GitHub starts **Bicep CI/CD** (`pull_request`).
3. **Lint and security scan** compiles Bicep and runs Checkov.
4. **Validate and what-if (dev)** may wait for `dev` reviewers, then OIDC login, validate, what-if, job summary, PR comment.
5. **Plan deploy targets** builds the three-environment matrix.
6. **Deploy dev** may wait for `dev` reviewers, login, what-if; **create is skipped**.
7. Same for **staging** and **production** (what-if only).
8. Azure resource groups are **not** created by this run.

---

## 13. End-to-end: merge to `main`

1. You merge the PR (or push to `main`).
2. GitHub starts a **new** run (`push`).
3. Lint → validate/what-if (dev) → plan (all three envs).
4. **Deploy dev**: approve if required → login → what-if → **create** `rg-bicep-github-actions-dev`.
5. **Deploy staging**: approve → what-if → **create** `rg-bicep-github-actions-staging`.
6. **Deploy production**: approve → what-if → **create** `rg-bicep-github-actions-production`.

If create fails on staging, production is not attempted (`fail-fast`).

---

## 14. End-to-end: Run workflow

1. **Actions → Bicep CI/CD → Run workflow** → pick `dev` or `staging` or `production`.
2. Plan-deploy outputs **one** matrix row.
3. Only that environment’s deploy job runs, including **create** (not a PR).

---

## 15. Local Azure CLI (same operations as the pipeline)

```bash
az deployment sub validate --location westus --template-file main.bicep --parameters params/dev.bicepparam
az deployment sub what-if  --location westus --template-file main.bicep --parameters params/dev.bicepparam
az deployment sub create   --location westus --template-file main.bicep --parameters params/dev.bicepparam
```

---

## 16. Common errors

| Error | Meaning | What to check |
|---|---|---|
| `AADSTS700016` | Entra has no app for that client ID in that tenant | `AZURE_CLIENT_ID` must be **Client ID**, not Principal ID; tenant ID must match the identity’s directory |
| No matching federated identity | JWT subject ≠ credential | Environment name (`dev` vs `dev-preview`), org/repo IDs, Entity type |
| Login failed / `id-token` | GitHub did not issue a JWT | `permissions: id-token: write` |
| Validate fails after login | Identity cannot create the resources | Contributor (or equivalent) on the subscription |
| Job skipped (`if`) | Condition false | For example create skipped on `pull_request` |
| Job skipped (`needs`) | An earlier job failed | Open lint or preview-dev logs |
| 403 on `git push` | Wrong GitHub user for that remote | Push as a user with write access, or change `origin` |
| CodeQL v1/v2 deprecated | Old Action version | `upload-sarif@v3` |
| `Unrecognized named-value: matrix` | `matrix` used in job-level `if` | Keep planning in **plan-deploy** |

---

## 17. Quick map: YAML name → Actions UI name

| YAML `jobs:` id | Name in the Actions UI |
|---|---|
| `lint-and-scan` | Lint and security scan |
| `preview-dev` | Validate and what-if (dev) |
| `plan-deploy` | Plan deploy targets |
| `deploy` | Deploy dev / Deploy staging / Deploy production |
