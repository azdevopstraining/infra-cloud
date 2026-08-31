# infra-cloud

Azure infrastructure as code with **Bicep**, deployed from **GitHub Actions** using **OpenID Connect** (workload identity federation). No client secrets.

The template creates one resource group per environment:

| Environment | Resource group |
|---|---|
| `dev` | `rg-bicep-github-actions-dev` |
| `staging` | `rg-bicep-github-actions-staging` |
| `production` | `rg-bicep-github-actions-production` |

## Layout

```text
main.bicep
params/dev.bicepparam
params/staging.bicepparam
params/prod.bicepparam
.github/workflows/multistage-cicd-pipeline.yml
```

## Pipeline

Workflow: `.github/workflows/multistage-cicd-pipeline.yml`

| Job | What it does |
|---|---|
| Lint and security scan | `az bicep build` and Checkov |
| Validate and what-if (dev) | ARM validate + what-if with `params/dev.bicepparam`; comments the preview on a PR |
| Plan deploy targets | Builds the env matrix (`dev` → `staging` → `production`, or one env on a manual run) |
| Deploy | Login, what-if, then `az deployment sub create` **only when not a pull request** |

### When it runs

| Trigger | Lint / validate / what-if / deploy jobs | `az deployment sub create` |
|---|---|---|
| Pull request into `main` | Yes | **Skipped** |
| Merge or push to `main` | Yes | **Runs** (after environment approval) |
| Actions → Run workflow | Yes | **Runs** (selected environment) |

A PR run and a merge run are expected. The PR does not create Azure resources. Merge applies them.

## Authentication (OIDC)

Jobs that talk to Azure use `azure/login` with:

- `AZURE_CLIENT_ID` — **Client ID** of the user-assigned managed identity (not Principal ID)
- `AZURE_TENANT_ID` — Entra directory ID
- `AZURE_SUBSCRIPTION_ID` — subscription ID

`permissions.id-token: write` is required so GitHub can mint the OIDC token.

Each Azure login job sets `environment: <name>` so the token subject matches a federated credential, for example:

```text
repo:OWNER/REPO:environment:dev
```

With the portal’s ID-based format, the subject looks like:

```text
repo:OWNER@ORG_ID/REPO@REPO_ID:environment:dev
```

### GitHub IDs (example)

For [azdevopstraining/infra-cloud](https://github.com/azdevopstraining/infra-cloud):

| Field | Value |
|---|---|
| Organization (GitHub user/org login) | `azdevopstraining` |
| Organization ID | `157454275` |
| Repository | `infra-cloud` |
| Repository ID | `1352027221` |

Look up IDs:

```text
https://api.github.com/users/OWNER
https://api.github.com/orgs/OWNER
https://api.github.com/repos/OWNER/REPO
```

Use the `"id"` number in **Organization ID** / **Repository ID**. The login name is not a valid ID.

### Managed identity (per environment)

1. Create a user-assigned identity (for example `dev-mi`).
2. Assign **Contributor** on the subscription (uses Principal ID).
3. Add a federated credential: GitHub Actions, Entity **Environment**, name exactly `dev` / `staging` / `production`.
4. Repeat for staging and production identities, or reuse one identity with three credentials.

## GitHub Environments

**Settings → Environments.** Create `dev`, `staging`, and `production` (names must match the YAML).

On **each** environment, add secrets:

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | That environment’s managed identity **Client ID** |
| `AZURE_TENANT_ID` | Directory (tenant) ID |
| `AZURE_SUBSCRIPTION_ID` | Subscription ID |

### Approvals

Approvals are **not** in YAML. On each environment: **Deployment protection rules → Required reviewers**.

- Add yourself (or a teammate) as a reviewer.
- To approve a run you started, leave **Prevent self-review** **off**.
- If **Prevent self-review** is on, another person must approve.

Any job that uses `environment: dev` waits on `dev` reviewers, including **Validate and what-if (dev)**. Required reviewers apply to the environment name, not to a single job. Deploy jobs use `dev` / `staging` / `production` and wait in that order (`max-parallel: 1`).

## Local commands

```bash
az deployment sub validate \
  --location westus \
  --template-file main.bicep \
  --parameters params/dev.bicepparam

az deployment sub what-if \
  --location westus \
  --template-file main.bicep \
  --parameters params/dev.bicepparam

az deployment sub create \
  --location westus \
  --template-file main.bicep \
  --parameters params/dev.bicepparam
```

## Common errors

| Error | Typical cause |
|---|---|
| `AADSTS700016` Application not found | Wrong `AZURE_CLIENT_ID` (Principal ID) or wrong `AZURE_TENANT_ID` |
| No matching federated identity | Environment name / repo / org ID does not match the credential subject |
| 403 on `git push` | GitHub user does not have write access to that remote |
| `matrix` in job `if` | Job-level `if` cannot use `matrix`; plan targets in a previous job |
| CodeQL Action v2 deprecated | Use `github/codeql-action/upload-sarif@v3` |
