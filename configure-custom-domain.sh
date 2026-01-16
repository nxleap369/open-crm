#!/bin/bash
# Configure custom domain for Twenty CRM on Azure Container Apps

echo "Step 1: Verify DNS records..."
echo "TXT Record: asuid.sandbox-crm.neuqa.io -> D5722E55F7C686CDC36FB762B1C31A0160EC1EE07827A32A0C4A30E8840423AE"
echo "CNAME Record: sandbox-crm.neuqa.io -> twentycrm-app.calmbush-6aa2662b.centralus.azurecontainerapps.io"
echo ""

# Check DNS propagation
echo "Checking DNS propagation..."
dig TXT asuid.sandbox-crm.neuqa.io +short
dig CNAME sandbox-crm.neuqa.io +short
echo ""

# Add custom domain (run after DNS is configured)
echo "Step 2: Adding custom domain to Container App..."
az containerapp hostname add \
  --hostname sandbox-crm.neuqa.io \
  --name twentycrm-app \
  --resource-group twentycrm-prod

# Bind SSL certificate (auto-provisioned)
echo "Step 3: Binding SSL certificate..."
az containerapp hostname bind \
  --hostname sandbox-crm.neuqa.io \
  --name twentycrm-app \
  --resource-group twentycrm-prod \
  --validation-method CNAME

echo "✅ Custom domain configured with SSL!"
echo "Access your CRM at: https://sandbox-crm.neuqa.io"
