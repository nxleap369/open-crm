# Azure Deployment Setup Guide

This guide explains how to set up automated deployments to Azure Container Apps via GitHub Actions.

## Prerequisites

- Azure subscription: `neuqa`
- Azure resources already deployed in `twentycrm-prod` resource group
- GitHub repository with Actions enabled

## GitHub Environment Setup

We use **GitHub Environments** for better security and deployment control. Secrets are scoped to the `production` environment with optional protection rules.

### Step 1: Create Production Environment

1. Go to **Settings → Environments** in your GitHub repository
2. Click **New environment**
3. Name: `production`
4. Click **Configure environment**
5. (Optional) Add protection rules:
   - ✅ Required reviewers (specify team members who must approve deployments)
   - ✅ Wait timer (delay before deployment starts)
   - ✅ Deployment branches (restrict to `main` only)

### Step 2: Add Environment Secrets

In the `production` environment configuration, scroll to **Environment secrets** and add the following:

## Required Environment Secrets

### 1. AZURE_CREDENTIALS

Azure service principal credentials for GitHub Actions authentication.

**Create the service principal:**

```bash
az ad sp create-for-rbac \
  --name "twentycrm-github-actions" \
  --role contributor \
  --scopes /subscriptions/33f6e71b-de42-4d46-ac21-3f8cfc9fd138/resourceGroups/twentycrm-prod \
  --sdk-auth
```

**Copy the entire JSON output** and save it as the `AZURE_CREDENTIALS` secret. It should look like:

```json
{
  "clientId": "...",
  "clientSecret": "...",
  "subscriptionId": "33f6e71b-de42-4d46-ac21-3f8cfc9fd138",
  "tenantId": "...",
  "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
  "resourceManagerEndpointUrl": "https://management.azure.com/",
  "activeDirectoryGraphResourceId": "https://graph.windows.net/",
  "sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
  "galleryEndpointUrl": "https://gallery.azure.com/",
  "managementEndpointUrl": "https://management.core.windows.net/"
}
```

### 2. APP_SECRET

Application secret key for Twenty CRM.

**To get current value:**
```bash
# Get from currently deployed container
az containerapp show \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --query "properties.template.containers[0].env[?name=='APP_SECRET'].value" -o tsv
```

**To generate a new secret (for rotation):**
```bash
openssl rand -base64 32
```

### 3. PG_DATABASE_URL

PostgreSQL connection string.

**Format:**
```
postgresql://[username]:[url-encoded-password]@[server].postgres.database.azure.com/[database]?sslmode=require
```

**Get current connection string:**
```bash
# Get from currently deployed container
az containerapp show \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --query "properties.template.containers[0].env[?name=='PG_DATABASE_URL'].value" -o tsv
```

### 4. REDIS_URL

Redis connection string.

**Get current credentials:**
```bash
# Get Redis hostname
REDIS_HOST=$(az redis show \
  --name twentycrm-redis-1768504249 \
  --resource-group twentycrm-prod \
  --query hostName -o tsv)

# Get Redis key
REDIS_KEY=$(az redis list-keys \
  --name twentycrm-redis-1768504249 \
  --resource-group twentycrm-prod \
  --query primaryKey -o tsv)

# Construct Redis URL
echo "rediss://:${REDIS_KEY}@${REDIS_HOST}:6380"
```

**Format:**
```
rediss://:[access-key]@[redis-server].redis.cache.windows.net:6380
```

## Deployment Workflow

The GitHub Actions workflow (`.github/workflows/deploy-azure.yml`) automatically:

1. **Triggers on:**
   - Push to `main` branch (with optional required reviewers approval)
   - Manual workflow dispatch

2. **Environment:**
   - Uses `production` environment
   - Loads secrets from environment scope
   - Respects protection rules (if configured)

3. **Build process:**
   - Checks out code
   - Installs Node.js 24.5.0 and dependencies
   - Builds Docker image with `REACT_APP_SERVER_BASE_URL=https://sandbox-crm.neuqa.io`
   - Pushes to Azure Container Registry

3. **Deployment:**
   - Updates Container App with new image
   - Sets environment variables
   - Waits for deployment to stabilize

4. **Verification:**
   - Checks health endpoint at https://sandbox-crm.neuqa.io/healthz
   - Creates deployment summary
   - Shows recent logs if deployment fails

## Manual Deployment

To trigger a manual deployment:

1. Go to **Actions** tab in GitHub
2. Select **Deploy to Azure Container Apps**
3. Click **Run workflow**
4. Select branch (usually `main`)
5. Click **Run workflow**

## Monitoring Deployments

### View workflow runs
```bash
# In GitHub: Actions tab → Deploy to Azure Container Apps
```

### Check Container App status
```bash
az containerapp revision list \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --output table
```

### View container logs
```bash
az containerapp logs show \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --follow
```

### Test deployment
```bash
# Health check
curl https://sandbox-crm.neuqa.io/healthz

# Frontend
curl -I https://sandbox-crm.neuqa.io/welcome
```

## Rollback Procedure

If a deployment fails or introduces issues:

### Option 1: Re-run previous workflow
1. Go to **Actions** tab
2. Find last successful workflow run
3. Click **Re-run all jobs**

### Option 2: Manual rollback via Azure CLI
```bash
# List revisions
az containerapp revision list \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --query "[].{Name:name,Active:properties.active,Traffic:properties.trafficWeight,Created:properties.createdTime}" \
  --output table

# Activate previous revision
az containerapp revision activate \
  --revision <previous-revision-name> \
  --name twentycrm-app \
  --resource-group twentycrm-prod
```

### Option 3: Rollback image tag
```bash
# Find previous working image
az acr repository show-tags \
  --name twentycrmacr \
  --repository twenty \
  --orderby time_desc \
  --output table

# Deploy previous image
az containerapp update \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --image twentycrmacr.azurecr.io/twenty:<previous-commit-sha>
```

## Troubleshooting

### Deployment fails with authentication error
- Verify `AZURE_CREDENTIALS` secret is correct and service principal has contributor access
- Check service principal hasn't expired: `az ad sp show --id <client-id>`

### Health check fails after deployment
```bash
# Check recent logs
az containerapp logs show \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --tail 100

# Check if database migrations ran
# Look for "Successfully migrated DB!" in logs
```

### Frontend shows wrong API endpoint
- Verify workflow builds with correct `REACT_APP_SERVER_BASE_URL`
- Frontend build arg is set at **build time**, not runtime
- Rebuild and redeploy if URL changed

### Database connection issues
- Verify `PG_DATABASE_URL` secret is correctly URL-encoded
- Check PostgreSQL firewall allows Azure services:
  ```bash
  az postgres flexible-server firewall-rule list \
    --resource-group twentycrm-prod \
    --name twentycrm-postgres \
    --output table
  ```

## Security Best Practices

✅ **Current setup:**
- Service principal scoped to single resource group
- Secrets stored in GitHub Secrets (encrypted)
- SSL/TLS enforced for all connections
- PostgreSQL requires SSL (`sslmode=require`)
- Redis uses TLS (port 6380)

⚠️ **TODO - Future improvements:**
- Migrate to Azure Managed Identities (passwordless authentication)
- Implement secret rotation automation
- Add GitHub Environment protection rules
- Enable Azure Container Apps authentication

## Resources

- **Application URL**: https://sandbox-crm.neuqa.io
- **Azure Portal**: [twentycrm-prod Resource Group](https://portal.azure.com/#@/resource/subscriptions/33f6e71b-de42-4d46-ac21-3f8cfc9fd138/resourceGroups/twentycrm-prod)
- **GitHub Actions**: Repository Actions tab
- **Container Registry**: twentycrmacr.azurecr.io
- **PostgreSQL**: twentycrm-postgres.postgres.database.azure.com
- **Redis**: twentycrm-redis-1768504249.redis.cache.windows.net
