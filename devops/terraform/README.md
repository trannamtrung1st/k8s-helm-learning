# Terraform (Azure)

This directory provisions Azure foundation resources for Workbench using the **azurerm** provider. Authentication is controlled by **`use_oidc`** in your tfvars (default **`false`** for local **`az login`**; set **`true`** for GitHub Actions / workload identity federation with no client secret).

## Layout

```text
devops/terraform/
  README.md
  main.tf              # backend "azurerm", provider, resource group
  variables.tf
  outputs.tf
  vars/
    terraform.tfvars        # optional local overrides (placeholders)
    prod.tfvars             # tenant_id, subscription_id, client_id, use_oidc, …
    secrets.tfvars          # Key Vault secret values (gitignored; create locally)
    secrets.tfvars.example  # template for secrets.tfvars
  .terraform.lock.hcl

scripts/                 # run from repository root
  lib/terraform-varfiles.sh   # shared -var-file logic (prod + secrets)
  terraform-init.sh      # provision workbench-tf RG + storage (az), then terraform init
  terraform-plan.sh      # plan only (run init first)
  terraform-apply.sh     # apply (options: -y, --plan-first, --target, …)
  terraform-destroy.sh   # destroy (options: -y, --plan-first, --target)
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) **1.x**
- An Azure **subscription** and permission to create resource groups (and assign RBAC if you set up the app yourself)
- For **OIDC / CI**: access to **Microsoft Entra ID** to register an application and add a **federated credential**
- For **local plan**: [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) and **`az login`**

Provider pin: **azurerm** `4.73.0` (see `main.tf`).

## Quick start (repo root)

```bash
az login   # required for first-time backend provisioning (local)

# Identity / subscription (required) — create vars/prod.tfvars (see example below)

# Key Vault secret values (optional until you apply secrets)
cp vars/secrets.tfvars.example vars/secrets.tfvars
# edit vars/secrets.tfvars — set manage_workbench_kv_secrets = true and workbench_secrets { … }

./scripts/terraform-init.sh    # creates state RG + storage (if missing), then terraform init
./scripts/terraform-plan.sh    # uses vars/prod.tfvars + vars/secrets.tfvars when present
./scripts/terraform-apply.sh --plan-first
```

When **`vars/secrets.tfvars`** exists, **`terraform-plan.sh`**, **`terraform-apply.sh`**, and **`terraform-destroy.sh`** automatically add **`-var-file=vars/secrets.tfvars`** after **`vars/prod.tfvars`**. With no secrets file, only **`prod.tfvars`** is used (Key Vault secret resources stay off while **`manage_workbench_kv_secrets`** defaults to **`false`**).

If **`terraform init`** fails with **403** on the storage account, assign **Storage Blob Data Contributor** (local user or Entra app) — [Remote state RBAC](#remote-state-rbac-storage-blob-data-roles).

### Apply (`terraform-apply.sh`)

| Option | Description |
| ------ | ----------- |
| `-y`, `--auto-approve` | Apply without Terraform’s confirmation prompt |
| `--plan-first` | Run **`terraform plan`** first; prompt before apply (skipped with `-y`) |
| `--refresh-only` | Run **`terraform apply -refresh-only`** |
| `--target <resource>` | Limit to one resource (repeatable), e.g. `azurerm_resource_group.workbench` |
| `--replace <resource>` | Force replace on apply (repeatable) |
| `--destroy` | Alias for **`terraform-destroy.sh`** (prefer the destroy script) |

```bash
./scripts/terraform-apply.sh --plan-first
./scripts/terraform-apply.sh -y
./scripts/terraform-apply.sh --target=azurerm_resource_group.workbench -y
```

### Destroy (`terraform-destroy.sh`)

| Option | Description |
| ------ | ----------- |
| `-y`, `--auto-approve` | Destroy without Terraform’s confirmation prompt |
| `--plan-first` | Run **`terraform plan -destroy`** first; prompt before destroy (skipped with `-y`) |
| `--target <resource>` | Destroy only this resource (repeatable) |

```bash
./scripts/terraform-destroy.sh --plan-first
./scripts/terraform-destroy.sh -y
./scripts/terraform-destroy.sh --target=azurerm_resource_group.workbench --plan-first
```

Override var files:

```bash
VAR_FILE=vars/terraform.tfvars ./scripts/terraform-apply.sh -y
USE_SECRETS_TFVARS=false ./scripts/terraform-plan.sh    # skip secrets.tfvars even if present
USE_SECRETS_TFVARS=true ./scripts/terraform-plan.sh     # require vars/secrets.tfvars
SECRETS_VAR_FILE=vars/my-secrets.tfvars ./scripts/terraform-plan.sh
```

| Environment variable   | Default                 | Description |
| ---------------------- | ----------------------- | ----------- |
| `VAR_FILE`             | `vars/prod.tfvars`      | Subscription / Entra IDs |
| `SECRETS_VAR_FILE`     | `vars/secrets.tfvars`   | `workbench_secrets`, `manage_workbench_kv_secrets` |
| `USE_SECRETS_TFVARS`   | `auto`                  | `auto`: include secrets file when it exists; `true`: require it; `false`: never include |

**`terraform-init.sh`** provisions (when missing):

| Azure resource  | Default name                                    |
| --------------- | ----------------------------------------------- |
| Resource group  | `workbench-tf` (`TF_STATE_RG`)                  |
| Storage account | `workbenchstorage77` (`TF_STATE_STORAGE_ACCOUNT`) |
| Blob container  | `workbench-tf` (`TF_STATE_CONTAINER`)           |

Skip provisioning if resources already exist: `./scripts/terraform-init.sh --skip-provision` or `SKIP_TF_BACKEND_PROVISION=1`.

Refresh providers/modules after constraint changes: `./scripts/terraform-init.sh --upgrade` (or combine with `--skip-provision`).

`VAR_FILE` / `SECRETS_VAR_FILE` apply to **`terraform-plan.sh`**, **`terraform-apply.sh`**, **`terraform-destroy.sh`**, and **`pre-commit-terraform-validate.sh`** (when **`vars/prod.tfvars`** exists).

## Variables

### Identity and region (`vars/prod.tfvars`)

| Variable           | Required | Default           | Description                                                                                      |
| ------------------ | -------- | ----------------- | ------------------------------------------------------------------------------------------------ |
| `tenant_id`        | yes      | —                 | Entra **Directory (tenant) ID**                                                                  |
| `subscription_id`  | yes      | —                 | Azure **subscription ID**                                                                        |
| `client_id`        | yes      | —                 | Entra **Application (client) ID** used for OIDC / service principal                              |
| `use_oidc`         | no       | `false`           | `true` = OIDC token auth (`ARM_OIDC_TOKEN` / GitHub); `false` = Azure CLI or other non-OIDC auth |
| `main_rg_name`     | no       | `workbench`       | Main resource group name                                                                         |
| `main_rg_location` | no       | `South East Asia` | Azure region                                                                                     |

Example **`vars/prod.tfvars`** (add `use_oidc` for CI):

```hcl
tenant_id       = "<tenant-id>"
subscription_id = "<subscription-id>"
client_id       = "<application-client-id>"
use_oidc        = true   # false for local: az login
```

Do not commit real IDs to a public repository.

### Key Vault secrets (`vars/secrets.tfvars`)

Copy **`vars/secrets.tfvars.example`** → **`vars/secrets.tfvars`** (listed in **`.gitignore`**). Set **`manage_workbench_kv_secrets = true`** to create **`azurerm_key_vault_secret`** resources in **`workbench-kv`**.

| Terraform variable              | Key Vault secret names (examples) |
| ------------------------------- | --------------------------------- |
| `workbench_secrets.postgres_*`  | `workbench-postgres-connection-string`, `workbench-postgres-user`, `workbench-postgres-password`, `workbench-postgres-database` |
| `workbench_secrets.rabbitmq_*`  | `workbench-rabbitmq-uri`, `workbench-rabbitmq-password` |
| `workbench_secrets.redis_*`     | `workbench-redis-connection-string`, `workbench-redis-user`, `workbench-redis-password` |

Values align with Helm **`global.workbenchPostgres`**, **`global.workbenchRabbitMq`**, and **`global.workbenchRedis`** (see **`devops/clusters/local/global-values.yaml`** for local placeholders).

Example **`vars/secrets.tfvars`**:

```hcl
manage_workbench_kv_secrets = true

workbench_secrets = {
  postgres_connection_string = "Host=...;Port=5432;Database=workbench;Username=workbench;Password=..."
  postgres_user              = "workbench"
  postgres_password          = "..."
  postgres_database          = "workbench"
  rabbitmq_uri               = "amqp://workbench:...@...:5672/"
  rabbitmq_password          = "..."
  redis_connection_string    = "...:6379,user=workbench,password=..."
  redis_user                 = "workbench"
  redis_password             = "..."
}
```

Manual Terraform (same var files as the scripts):

```bash
terraform -chdir=devops/terraform plan \
  -var-file=vars/prod.tfvars \
  -var-file=vars/secrets.tfvars
```

## Authentication

### Local (`use_oidc = false`)

1. `az login` (and `az account set --subscription <id>` if needed).
2. Ensure **`vars/prod.tfvars`** sets **`use_oidc = false`** (or omit it; default is `false`).
3. Run **`./scripts/terraform-init.sh`** then **`./scripts/terraform-plan.sh`**.

The provider still needs **`tenant_id`**, **`subscription_id`**, and **`client_id`** in tfvars when using OIDC-related settings; for pure Azure CLI auth, **`client_id`** can match your app registration if you use one, or follow [azurerm provider docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) for your auth mode.

### CI / OIDC (`use_oidc = true`)

Set in tfvars or environment:

```bash
export TF_VAR_use_oidc=true
```

Provider / ARM environment variables:

| Variable              | Purpose                                                                       |
| --------------------- | ----------------------------------------------------------------------------- |
| `ARM_USE_OIDC`        | `true`                                                                        |
| `ARM_CLIENT_ID`       | Same as **`client_id`** in tfvars                                             |
| `ARM_TENANT_ID`       | Same as **`tenant_id`**                                                       |
| `ARM_SUBSCRIPTION_ID` | Same as **`subscription_id`**                                                 |
| `ARM_OIDC_TOKEN`      | OIDC token from the workload (GitHub Actions supplies this via `azure/login`) |

Backend init (remote state) uses **`use_oidc`** on the storage backend via **`scripts/terraform-init.sh`** (`TF_BACKEND_USE_OIDC`, default `true`). For local init against remote state without OIDC, run init manually with **`-backend-config=use_oidc=false`** or set **`TF_BACKEND_USE_OIDC=false ./scripts/terraform-init.sh`**.

---

## Entra ID — register app and federate OIDC (CI)

Use this when **`use_oidc = true`** (e.g. GitHub Actions). No client secret is required.

### Step 1 — Register an application

[Microsoft Entra admin center](https://entra.microsoft.com/) → **Applications** → **App registrations** → **New registration**.

1. **Name:** e.g. `workbench-terraform`
2. **Supported account types:** single tenant
3. **Redirect URI:** none
4. **Register** and note **Application (client) ID** and **Directory (tenant) ID**

Put those IDs in **`vars/prod.tfvars`** as **`client_id`** and **`tenant_id`**.

### Step 2 — Service principal

```bash
export APP_ID="<application-client-id>"
az ad sp create --id "$APP_ID"
```

### Step 3 — Federated credential

App registration → **Certificates & secrets** → **Federated credentials** → **Add credential**.

- **Scenario:** GitHub Actions deploying Azure resources (or **Other issuer**)
- **Repository / branch** (example): `repo:<ORG>/k8s-helm-learning:ref:refs/heads/main`
- **Audience:** `api://AzureADTokenExchange`

See [Create a trust relationship](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust).

### Step 4 — Azure RBAC (subscription + remote state)

Grant the Entra app’s service principal permission to manage Azure resources **and** to read/write Terraform state blobs (see **[Remote state RBAC](#remote-state-rbac-storage-blob-data-roles)** below).

**Subscription** (create resource groups, storage accounts, etc.):

```bash
export APP_ID="<application-client-id>"
export SUBSCRIPTION_ID="<subscription-id>"

az role assignment create \
  --assignee "$APP_ID" \
  --role "Contributor" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}"
```

**Remote state storage** (required when `use_azuread_auth=true` on the backend):

```bash
export TF_STATE_RG="${TF_STATE_RG:-workbench-tf}"
export TF_STATE_STORAGE_ACCOUNT="${TF_STATE_STORAGE_ACCOUNT:-workbenchstorage77}"

az role assignment create \
  --assignee "$APP_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${TF_STATE_RG}/providers/Microsoft.Storage/storageAccounts/${TF_STATE_STORAGE_ACCOUNT}"
```

Use **`Storage Blob Data Owner`** instead of **Storage Blob Data Contributor** only if you need to manage blob ownership/ACLs; for Terraform state, **Contributor** is usually enough.

### Step 5 — GitHub Actions (minimal)

```yaml
permissions:
  id-token: write
  contents: read

env:
  ARM_USE_OIDC: true
  ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

steps:
  - uses: actions/checkout@v4
  - uses: azure/login@v2
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  - run: ./scripts/terraform-init.sh
  - run: ./scripts/terraform-plan.sh
  - run: ./scripts/terraform-apply.sh --plan-first -y
```

Ensure **`vars/prod.tfvars`** (or CI-generated tfvars) sets **`use_oidc = true`**. For Key Vault secrets in CI, add a protected **`vars/secrets.tfvars`** (or inject **`TF_VAR_workbench_secrets`** / merge into a generated tfvars file). Federated credential **subject** must match the workflow (repo, ref, environment).

---

## Remote state

`main.tf` declares **`backend "azurerm" {}`**. Partial settings are passed at **init** only (`-backend-config` is **not** valid for **`plan`**).

**`scripts/terraform-init.sh`** provisions the backend (see table above), then passes:

| Backend key            | Default / source                                                           |
| ---------------------- | -------------------------------------------------------------------------- |
| `resource_group_name`  | `workbench-tf` (`TF_STATE_RG`)                                             |
| `storage_account_name` | `workbenchstorage77` (`TF_STATE_STORAGE_ACCOUNT`)                            |
| `container_name`       | `workbench-tf` (`TF_STATE_CONTAINER`)                                      |
| `key`                  | `terraform.tfstate` (`TF_STATE_KEY`)                                       |
| `use_azuread_auth`     | `true`                                                                     |
| `use_oidc`             | `true` (`TF_BACKEND_USE_OIDC`; use `false` with `az login` for local init) |
| `tenant_id`            | from **`vars/prod.tfvars`** (`TENANT_ID` env overrides)                    |

Region for the state resource group defaults to **`southeastasia`** (`TF_STATE_LOCATION`), or follows **`main_rg_location`** from your var file when set.

**Subscription:** **Contributor** (or equivalent) is needed to **create** the state resource group and storage account (`terraform-init.sh` provisioning).

**State blob access:** With **`use_azuread_auth=true`**, Terraform uses the **data plane** (not storage account keys). You must assign **Storage Blob Data Contributor** or **Storage Blob Data Owner** on the storage account or container — **in addition to** any subscription-level roles. See the next section.

### Remote state RBAC (Storage Blob Data roles)

| Role | Use for Terraform state |
| ---- | ------------------------ |
| **Storage Blob Data Contributor** | Recommended — read/write state blobs |
| **Storage Blob Data Owner** | Same data access plus permission to manage blob ACLs (usually unnecessary) |

**Scope** (pick one):

- **Storage account** (recommended):  
  `/subscriptions/<subscription-id>/resourceGroups/workbench-tf/providers/Microsoft.Storage/storageAccounts/<storage-account-name>`
- **Container** (narrower):  
  `.../storageAccounts/<storage-account-name>/blobServices/default/containers/workbench-tf`

Default names match **`terraform-init.sh`**: RG **`workbench-tf`**, account **`workbenchstorage77`**, container **`workbench-tf`**.

#### Option A — Local user (`az login`)

Used when you run **`./scripts/terraform-init.sh`** with **`TF_BACKEND_USE_OIDC=false`** (default for local) or **`use_oidc = false`** in tfvars. The signed-in user must have the blob role on the state storage account.

**Azure Portal**

1. Open the storage account (e.g. **workbenchstorage77**) → **Access control (IAM)**.
2. **Add** → **Add role assignment**.
3. **Role:** **Storage Blob Data Contributor** (or **Storage Blob Data Owner**).
4. **Members:** **User, group, or service principal** → **+ Select members** → search for your user → **Review + assign**.

**Azure CLI**

```bash
export SUBSCRIPTION_ID="<subscription-id>"
export TF_STATE_RG="${TF_STATE_RG:-workbench-tf}"
export TF_STATE_STORAGE_ACCOUNT="${TF_STATE_STORAGE_ACCOUNT:-workbenchstorage77}"

STATE_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${TF_STATE_RG}/providers/Microsoft.Storage/storageAccounts/${TF_STATE_STORAGE_ACCOUNT}"

# Signed-in user (after az login)
USER_ID="$(az ad signed-in-user show --query id -o tsv)"

az role assignment create \
  --assignee "${USER_ID}" \
  --role "Storage Blob Data Contributor" \
  --scope "${STATE_SCOPE}"
```

Role assignments can take a few minutes to propagate. If **`terraform init`** fails with **403** / **AuthorizationPermissionMismatch**, confirm the assignment on the **storage account** scope and retry.

#### Option B — Entra app / federated credential (CI / OIDC)

Used when **`use_oidc = true`**, **`TF_BACKEND_USE_OIDC=true`**, or GitHub Actions **`azure/login`**. Assign the blob role to the **same application (client) ID** as **`client_id`** in **`vars/prod.tfvars`** (the service principal behind the federated credential).

**Azure Portal**

1. Storage account → **Access control (IAM)** → **Add role assignment**.
2. **Role:** **Storage Blob Data Contributor**.
3. **Members:** **User, group, or service principal** → select the app registration (e.g. **workbench-terraform**), not the federated credential name itself.
4. **Review + assign**.

**Azure CLI**

```bash
export APP_ID="<application-client-id>"   # same as client_id in prod.tfvars
export SUBSCRIPTION_ID="<subscription-id>"
export TF_STATE_RG="${TF_STATE_RG:-workbench-tf}"
export TF_STATE_STORAGE_ACCOUNT="${TF_STATE_STORAGE_ACCOUNT:-workbenchstorage77}"

STATE_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${TF_STATE_RG}/providers/Microsoft.Storage/storageAccounts/${TF_STATE_STORAGE_ACCOUNT}"

az role assignment create \
  --assignee "${APP_ID}" \
  --role "Storage Blob Data Contributor" \
  --scope "${STATE_SCOPE}"
```

For CI, assign this **after** the storage account exists (run once per subscription/storage account, or include in your bootstrap pipeline after **`terraform-init.sh`** provisioning).

#### Verify role assignments

```bash
az role assignment list \
  --scope "${STATE_SCOPE}" \
  --query "[].{principal:principalName, role:roleDefinitionName}" \
  -o table
```

Manual init (if you created the backend yourself):

```bash
terraform -chdir=devops/terraform init \
  -backend-config="resource_group_name=workbench-tf" \
  -backend-config="storage_account_name=workbenchstorage77" \
  -backend-config="container_name=workbench-tf" \
  -backend-config="key=terraform.tfstate" \
  -backend-config="use_azuread_auth=true" \
  -backend-config="use_oidc=true" \
  -backend-config="tenant_id=<tenant-id>"
```

## What this stack creates

- **`azurerm_resource_group.workbench`** — `main_rg_name`, `main_rg_location`
- **`azurerm_key_vault.workbench`** — `workbench-kv` (RBAC-enabled)
- **`azurerm_role_assignment.workbench_kv_secrets_officer`** — Terraform principal can manage secrets
- **`azurerm_key_vault_secret.workbench`** — nine secrets when **`manage_workbench_kv_secrets = true`** in **`vars/secrets.tfvars`**
- **`azurerm_container_registry.acr`** — `workbenchacr77` (`acr_login_server`: `workbenchacr77.azurecr.io`)
- **Outputs:** `resource_group_*`, `key_vault_*`, `key_vault_secret_names`, `acr_*`

## Review notes (config)

| Topic                      | Status                                                                          |
| -------------------------- | ------------------------------------------------------------------------------- |
| Backend block in `main.tf` | Required for `terraform-init.sh`; script can create `workbench-tf` RG + storage |
| `use_oidc` default `false` | Fits local `az login`; set `true` in tfvars for CI                              |
| `client_id` in tfvars      | Required by provider block; must match Entra app used for OIDC                  |
| `vars/secrets.tfvars`      | Gitignored; scripts auto-`-var-file` when the file exists                       |
| `vars/prod.tfvars`         | Not gitignored — avoid committing real subscription / tenant IDs                |

## Related docs

- [devops/README.md](../README.md) — Helm / Kubernetes
- [azurerm — OIDC](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/oidc)
- [Workload identity federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation)
