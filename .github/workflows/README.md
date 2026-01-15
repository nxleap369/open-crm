# GitHub Actions Workflows

This directory contains CI/CD workflows for Twenty CRM deployment to Azure Container Apps.

## Workflows

### `deploy-azure.yml`
Deploys the application to Azure Container Apps (sandbox-crm.neuqa.io) on every push to `main` branch.

**Triggers:**
- Push to `main` branch (automatic)
- Manual workflow dispatch

**Required Secrets** (Passwordless Deployment!):
- `AZURE_CREDENTIALS`: Azure service principal credentials (JSON format)
- `APP_SECRET`: Application secret (generate with `openssl rand -base64 32`)

**Note**: Only 2 secrets needed! This deployment uses Azure Managed Identities for passwordless authentication to:
- ✅ PostgreSQL (Entra ID authentication)
- ✅ Redis Cache (managed identity authentication)
- ✅ Storage Account (managed identity with RBAC)

### `pr-checks.yml`
Runs linting and tests on pull requests to ensure code quality.

**Triggers:**
- Pull requests to `main` branch

## Setup Instructions

### 1. Create Azure Infrastructure

**See [copilot-instructions.md](../copilot-instructions.md) for complete setup commands.**

Quick reference:
```bash
az login
az account set --subscription "neuqa"

az group create --name twentycrm-prod --location eastus

# Create Container Registry, PostgreSQL, Redis, Container Apps Environment
# Follow detailed instructions in copilot-instructions.md
```

### 2. Create Service Principal for GitHub Actions

```bash
# Create service principal with contributor role
az ad sp create-for-rbac \
  --name "twentycrm-github-actions" \
  --role contributor \
  --scopes /subscriptions/<subscription-id>/resourceGroups/twentycrm-prod \
  --sdk-auth

# Copy entire JSON output to GitHub secret: AZURE_CREDENTIALS
```

### 3. Configure GitHub Secrets (Minimal - Passwordless!)

1. Go to repository **Settings → Secrets and variables → Actions**
2. Add only 2 secrets:
   ```bash
   # Generate APP_SECRET
   openssl rand -base64 32

   # Add to GitHub:
   # - AZURE_CREDENTIALS (from service principal step)
   # - APP_SECRET (generated above)
   ```

**That's it!** No database passwords, Redis keys, or storage keys needed thanks to managed identities.

### 4. Deploy

1. Commit and push to `main` branch:
   ```bash
   git add .
   git commit -m "Configure Azure Container Apps deployment"
   git push origin main
   ```

2. Monitor deployment:
   - Go to **Actions** tab in GitHub
   - View "Deploy to Azure Container Apps" workflow

## Monitoring

### View Deployment Status
- **GitHub**: Actions tab → Deploy to Azure Container Apps
- **Azure Portal**: Container Apps → twentycrm-app → Revisions

### Check Application Health
```bash
# From local machine
curl https://sandbox-crm.neuqa.io/healthz

# View container logs
az containerapp logs show \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --follow
```

### View Revisions
```bash
az containerapp revision list \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --output table
```

## Rollback

Activate a previous revision:

```bash
# List revisions
az containerapp revision list \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --output table

# Activate specific revision
az containerapp revision activate \
  --revision <previous-revision-name> \
  --name twentycrm-app \
  --resource-group twentycrm-prod
```

Or re-run a previous successful workflow in GitHub Actions.

## Security Benefits of Managed Identity

This deployment uses **Azure Managed Identities** for a passwordless, zero-trust security model:

### What This Means
- ✅ **No Credentials in Code**: No database passwords, Redis keys, or storage account keys stored anywhere
- ✅ **Automatic Credential Rotation**: Azure handles credential lifecycle automatically
- ✅ **Least Privilege Access**: RBAC controls exactly what resources the app can access
- ✅ **Audit Trail**: All access logged in Azure Activity Log
- ✅ **Reduced Attack Surface**: No credentials to leak or steal
- ✅ **Compliance Ready**: Meets SOC 2, ISO 27001, and other security frameworks

### How It Works
1. Container App has a **system-assigned managed identity** (automatically managed by Azure)
2. This identity is granted specific RBAC roles:
   - **PostgreSQL**: Entra ID admin (database authentication)
   - **Redis**: Cache Contributor (cache access)
   - **Storage**: Blob/Queue Data Contributor (file uploads/jobs)
3. Application code uses Azure SDK with `DefaultAzureCredential` to authenticate
4. Azure automatically obtains tokens and handles authentication

### Configuration Required
Only **2 GitHub secrets** needed:
- `AZURE_CREDENTIALS`: Service principal for GitHub Actions (deployment only)
- `APP_SECRET`: Application encryption key (not for Azure services)

**Traditional approach would need**: Database passwords, Redis keys, storage keys, connection strings (6+ secrets)

## Troubleshooting

### Deployment Fails
1. Check GitHub Actions logs for specific error
2. Verify `AZURE_CREDENTIALS` secret is valid
3. Check container app logs: `az containerapp logs show`

### Authentication Errors
- Verify service principal has contributor role
- Ensure subscription ID is correct

### Container Fails to Start
- Check environment variables are set correctly
- Verify PostgreSQL and Redis connection strings
- Check port 3000 is exposed in Dockerfile

### Domain/SSL Issues
- Verify DNS CNAME points to Container App FQDN
- Azure manages SSL automatically (wait 5-10 minutes after binding)
- Check custom domain binding in Container App settings

### Managed Identity Issues
- Verify Container App has system-assigned managed identity enabled:
  ```bash
  az containerapp show --name twentycrm-app --resource-group twentycrm-prod --query identity
  ```
- Check PostgreSQL Entra ID admin is configured with managed identity
- Verify RBAC roles assigned to managed identity:
  - PostgreSQL: Entra ID admin access
  - Redis: "Redis Cache Contributor" role
  - Storage: "Storage Blob Data Contributor" and "Storage Queue Data Contributor" roles
- Ensure environment variables use managed identity flags:
  - `PG_DATABASE_USE_MANAGED_IDENTITY=true`
  - `REDIS_USE_MANAGED_IDENTITY=true`
  - `STORAGE_USE_MANAGED_IDENTITY=true`
