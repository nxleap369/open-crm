# Twenty CRM Development Guide

## Project Overview
Twenty is an open-source CRM built as an Nx monorepo with React 18 (frontend) and NestJS (backend). The architecture separates concerns into specialized packages with strict module boundaries enforced via ESLint.

## Essential Commands

### Development Workflow
```bash
# Start full stack (frontend + backend + worker) - primary dev command
yarn start

# Start individual services
npx nx start twenty-front       # React app on port 3001
npx nx start twenty-server      # NestJS API on port 3000
npx nx run twenty-server:worker # Background job processor

# Fastest linting (recommended) - only changed files vs main
npx nx lint:diff-with-main twenty-front --configuration=fix
npx nx lint:diff-with-main twenty-server --configuration=fix
```

### Database Operations
```bash
npx nx database:reset twenty-server                          # Reset database
npx nx run twenty-server:command workspace:sync-metadata     # Sync metadata schema

# Generate migration (replace [name] with descriptive name)
npx nx run twenty-server:typeorm migration:generate \
  src/database/typeorm/core/migrations/common/[name] \
  -d src/database/typeorm/core/core.datasource.ts
```

### Testing Strategy
```bash
# Run specific test file (PREFERRED - fast iteration)
npx jest packages/twenty-front/src/path/to/test.test.ts \
  --config=packages/twenty-front/jest.config.mjs

# Full test suites (slower)
npx nx test twenty-front        # Frontend unit tests
npx nx test twenty-server       # Backend unit tests
npx nx run twenty-server:test:integration:with-db-reset  # Integration with DB reset

# Storybook development
npx nx storybook:serve-and-test:static twenty-front
```

## Code Conventions (Critical)

### TypeScript Strict Rules
- **NO `any` type** - strict typing enforced
- **Types over interfaces** (except when extending third-party libraries)
- **String literals over enums** (except GraphQL enums)
- **Named exports only** - NO default exports
- **Functional components only** - NO class components

### React Patterns
```typescript
// ✅ Event handlers over useEffect for state updates
const handleClick = () => setCount(prev => prev + 1);

// ❌ Avoid useEffect for simple state updates
useEffect(() => { setCount(count + 1); }, [dependency]);

// ✅ Extract useEffect logic into sibling components to prevent re-renders
// ✅ Use Recoil atom families for dynamic data collections
```

### State Management
- **Recoil** for global state (atoms, selectors, atom families)
- **Apollo Client** for GraphQL cache management
- Component state with React hooks (prefer multiple `useState` over complex objects)

### Naming & Style
```typescript
// Variables/functions: camelCase
const userBalance = 100;

// Constants: SCREAMING_SNAKE_CASE
const API_BASE_URL = '/api';

// Types/Classes: PascalCase
type UserData = { id: string };
type ButtonProps = { label: string }; // Props suffix with 'Props'

// Files: kebab-case (user-profile.component.tsx)

// ❌ NEVER abbreviate variable names
// Bad: const u = users.find(u => u.id === id)
// Good: const user = users.find(user => user.id === id)
```

## Architecture Patterns

### Monorepo Structure
```
packages/
├── twenty-front/      # React app (Vite, Recoil, Emotion)
├── twenty-server/     # NestJS API (TypeORM, GraphQL Yoga, BullMQ)
├── twenty-ui/         # Shared UI component library
├── twenty-shared/     # Common types and utilities
└── twenty-emails/     # React Email templates
```

### Backend: NestJS Module Organization
- **Core modules** (`src/engine/core-modules/`) - Infrastructure (auth, workspace, users)
- **Metadata modules** (`src/engine/metadata-modules/`) - Dynamic schema management
- **Standard objects** (`src/modules/*/standard-objects/`) - Business entities with `.workspace-entity.ts` suffix
- **BullMQ** for async jobs via `MESSAGE_QUEUES` enum
- **TypeORM** with PostgreSQL + Redis caching

### Frontend: Module Boundaries
- Use `@/` path mappings for internal imports (configured via tsconfig paths)
- Prefer absolute imports over relative for cross-module references
- Components in own directories with co-located tests (`*.test.tsx`) and types

### GraphQL Code Generation
```bash
# Regenerate types after schema changes
npx nx run twenty-front:graphql:generate
```

## Testing Best Practices
- **AAA pattern** (Arrange, Act, Assert) for all tests
- Query by user-visible elements (text, roles, labels) over test IDs
- Test behavior, not implementation details
- Frontend: `.test.ts` extension | Backend: `.spec.ts` extension
- Use `npx jest <file-path> --config=<jest.config.mjs>` for single file execution

## Common Pitfalls to Avoid
- Don't use `React.memo()` - prefer Recoil selectors for optimization
- Don't use `useEffect` for simple state updates - use event handlers
- Never create default exports - use named exports
- Don't abbreviate variable names (e.g., `u` for `user`)
- Avoid generic comments - explain WHY, not WHAT
- Use `// comments`, not `/** JSDoc blocks */` for regular code comments

## Development Environment
- **Node**: v24.5.0+ required
- **Yarn**: 4.0.2+ (NO npm allowed)
- **Nx**: 22.0.3 for monorepo orchestration
- **Prettier**: 2-space indentation, single quotes, trailing commas

## Key Files Reference
- `nx.json` - Nx workspace task configuration and caching
- `tsconfig.base.json` - TypeScript path mappings for `@/` imports
- `eslint.config.mjs` - Root ESLint with module boundary enforcement
- `.cursor/rules/*.mdc` - Detailed development guidelines (auto-applied by file pattern)

## Azure Deployment with Container Apps

### Prerequisites
- **Azure Subscription**: "neuqa" subscription
- **Azure CLI**: Installed and authenticated
- **Docker**: Installed locally for building images
- **GitHub Actions**: CI/CD automation configured
- **Custom Domain**: sandbox-crm.neuqa.io with SSL managed by Azure

### Initial Azure Infrastructure Setup

```bash
# Login to Azure and set subscription
az login
az account set --subscription "neuqa"

# Create resource group
az group create \
  --name twentycrm-prod \
  --location eastus

# Create Azure Container Registry
az acr create \
  --resource-group twentycrm-prod \
  --name twentycrmacr \
  --sku Basic \
  --admin-enabled true

# Create Azure Database for PostgreSQL with Entra ID (Azure AD) authentication
az postgres flexible-server create \
  --resource-group twentycrm-prod \
  --name twentycrm-postgres \
  --location eastus \
  --admin-user pgadmin \
  --admin-password <strong-password> \
  --sku-name Standard_B2s \
  --tier Burstable \
  --storage-size 32 \
  --version 14 \
  --active-directory-auth Enabled \
  --password-auth Disabled

# Create database
az postgres flexible-server db create \
  --resource-group twentycrm-prod \
  --server-name twentycrm-postgres \
  --database-name twenty

# Configure firewall to allow Azure services
az postgres flexible-server firewall-rule create \
  --resource-group twentycrm-prod \
  --name twentycrm-postgres \
  --rule-name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# Create Azure Cache for Redis
az redis create \
  --resource-group twentycrm-prod \
  --name twentycrm-redis \
  --location eastus \
  --sku Basic \
  --vm-size c0

# Create Container Apps environment
az containerapp env create \
  --name twentycrm-env \
  --resource-group twentycrm-prod \
  --location eastus

# Create Container App with system-assigned managed identity
az containerapp create \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --environment twentycrm-env \
  --image twentycrmacr.azurecr.io/twenty:latest \
  --target-port 3000 \
  --ingress external \
  --registry-server twentycrmacr.azurecr.io \
  --cpu 1.0 \
  --memory 2Gi \
  --min-replicas 1 \
  --max-replicas 3 \
  --system-assigned

# Get the managed identity principal ID
IDENTITY_ID=$(az containerapp show \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --query identity.principalId -o tsv)

echo "Container App Managed Identity: $IDENTITY_ID"
```

### Configure Managed Identity Access (Passwordless Authentication)

```bash
# Get managed identity principal ID
IDENTITY_ID=$(az containerapp show \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --query identity.principalId -o tsv)

# Grant PostgreSQL access (Entra ID authentication)
az postgres flexible-server ad-admin create \
  --resource-group twentycrm-prod \
  --server-name twentycrm-postgres \
  --display-name twentycrm-app \
  --object-id $IDENTITY_ID

# Grant Redis access (Data Contributor role for passwordless access)
REDIS_ID=$(az redis show \
  --name twentycrm-redis \
  --resource-group twentycrm-prod \
  --query id -o tsv)

az role assignment create \
  --assignee $IDENTITY_ID \
  --role "Redis Cache Contributor" \
  --scope $REDIS_ID

# Grant Storage Account access (Blob Data Contributor role)
STORAGE_ID=$(az storage account show \
  --name neuqastorage \
  --resource-group twentycrm-prod \
  --query id -o tsv)

az role assignment create \
  --assignee $IDENTITY_ID \
  --role "Storage Blob Data Contributor" \
  --scope $STORAGE_ID

az role assignment create \
  --assignee $IDENTITY_ID \
  --role "Storage Queue Data Contributor" \
  --scope $STORAGE_ID

echo "✅ Managed identity configured for passwordless access to all services!"
```

### Configure Custom Domain with SSL

```bash
# Add custom domain to Container App (Azure manages SSL automatically)
az containerapp hostname add \
  --hostname sandbox-crm.neuqa.io \
  --name twentycrm-app \
  --resource-group twentycrm-prod

# Bind SSL certificate (auto-provisioned by Azure)
az containerapp hostname bind \
  --hostname sandbox-crm.neuqa.io \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --validation-method CNAME

# Update DNS CNAME record to point to Container App FQDN
# Get FQDN:
az containerapp show \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --query properties.configuration.ingress.fqdn -o tsv
```

### Environment Variables Configuration (Passwordless with Managed Identity)

```bash
# Set environment variables on Container App (NO PASSWORDS REQUIRED!)
az containerapp update \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --set-env-vars \
    SERVER_URL=https://sandbox-crm.neuqa.io \
    APP_SECRET=<generate-with-openssl-rand-base64-32> \
    PG_DATABASE_HOST=twentycrm-postgres.postgres.database.azure.com \
    PG_DATABASE_NAME=twenty \
    PG_DATABASE_PORT=5432 \
    PG_DATABASE_USE_MANAGED_IDENTITY=true \
    REDIS_HOST=twentycrm-redis.redis.cache.windows.net \
    REDIS_PORT=6380 \
    REDIS_USE_TLS=true \
    REDIS_USE_MANAGED_IDENTITY=true \
    STORAGE_TYPE=s3 \
    STORAGE_S3_REGION=eastus \
    STORAGE_S3_NAME=twentycrm-storage \
    STORAGE_S3_ENDPOINT=https://neuqastorage.blob.core.windows.net \
    STORAGE_USE_MANAGED_IDENTITY=true

# Note: Managed identity authentication means:
# ✅ No passwords stored in environment variables
# ✅ No secrets rotation needed
# ✅ Azure handles authentication automatically
# ✅ Better security posture
```

### Monitoring & Maintenance

```bash
# View container logs
az containerapp logs show \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --follow

# Check container app status
az containerapp show \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --query properties.runningStatus

# Scale replicas
az containerapp update \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --min-replicas 2 \
  --max-replicas 5

# View revisions (for rollback)
az containerapp revision list \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --output table

# Rollback to previous revision
az containerapp revision activate \
  --name <revision-name> \
  --app twentycrm-app \
  --resource-group twentycrm-prod
```

### Database Backups

```bash
# Azure Database for PostgreSQL has automated backups enabled by default
# Restore to point-in-time:
az postgres flexible-server restore \
  --resource-group twentycrm-prod \
  --name twentycrm-postgres-restored \
  --source-server twentycrm-postgres \
  --restore-time "2024-01-15T13:10:00Z"

# Manual backup
az postgres flexible-server db dump \
  --resource-group twentycrm-prod \
  --server-name twentycrm-postgres \
  --database-name twenty \
  --output backup_$(date +%Y%m%d).sql
```

### Production Checklist

- [ ] SSL certificate auto-managed by Azure Container Apps
- [ ] Custom domain sandbox-crm.neuqa.io configured
- [ ] **Managed Identity enabled on Container App (passwordless!)**
- [ ] **PostgreSQL Entra ID authentication configured**
- [ ] **Redis passwordless access granted to managed identity**
- [ ] **Storage Account access granted to managed identity**
- [ ] PostgreSQL Flexible Server with SSL enforcement
- [ ] Redis Cache configured with TLS
- [ ] Azure Blob Storage for file uploads
- [ ] Environment variables configured (no passwords!)
- [ ] Auto-scaling rules set (min 1, max 3 replicas)
- [ ] Database backups enabled (automatic)
- [ ] Container Registry integrated

**Reference**: [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)

## GitHub Actions CI/CD Setup

### Required GitHub Secrets

Navigate to your repository: **Settings → Secrets and variables → Actions**

Add these secrets:

```
AZURE_CREDENTIALS=<service-principal-credentials-json>
APP_SECRET=<generated-with-openssl-rand-base64-32>
```

**Note**: Only 2 secrets needed! PostgreSQL, Redis, and Storage use managed identities for passwordless authentication.

### Create Azure Service Principal

```bash
# Create service principal for GitHub Actions
az ad sp create-for-rbac \
  --name "twentycrm-github-actions" \
  --role contributor \
  --scopes /subscriptions/<subscription-id>/resourceGroups/twentycrm-prod \
  --sdk-auth

# Output will be JSON like:
{
  "clientId": "...",
  "clientSecret": "...",
  "subscriptionId": "...",
  "tenantId": "...",
  ...
}

# Copy this entire JSON output to AZURE_CREDENTIALS secret
```

### GitHub Actions Workflow

The workflow in `.github/workflows/deploy-azure.yml`:

- **Triggers**: Push to `main` branch or manual workflow dispatch
- **Build**: Lints, tests, builds Docker image
- **Deploy**: Pushes image to ACR, updates Container App
- **Verify**: Checks health endpoint after deployment

### Deployment Steps

1. **Create GitHub Secrets:**
   ```bash
   # Generate app secret (only secret needed!)
   openssl rand -base64 32

   # Add to GitHub Secrets as APP_SECRET
   # AZURE_CREDENTIALS already created in service principal step
   ```

   **Passwordless Authentication**: No database passwords, Redis keys, or storage account keys needed!
   ```bash
   git add .github/workflows/
   git commit -m "Add GitHub Actions CI/CD pipeline for Azure Container Apps"
   git push origin main
   ```

3. **Monitor deployment:**
   - Go to Actions tab in GitHub
   - Select "Deploy to Azure Container Apps"
   - View workflow run details

### Monitoring Deployments

```bash
# View container app logs
az containerapp logs show \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --follow

# Check deployment status
az containerapp revision list \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --output table

# View health endpoint
curl https://sandbox-crm.neuqa.io/healthz
```

### Rollback Procedure

```bash
# List revisions
az containerapp revision list \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --output table

# Activate previous revision
az containerapp revision activate \
  --revision <previous-revision-name> \
  --name twentycrm-app \
  --resource-group twentycrm-prod

# Or rollback via GitHub Actions:
# 1. Go to Actions tab
# 2. Find successful previous workflow run
# 3. Click "Re-run jobs"
```
