# GEMINI.md

This file provides guidance to Gemini when working with code in this repository.

## Project Overview

This is an n8n deployment project for Google Cloud Platform (GCP). It demonstrates a production-ready deployment using Cloud Run, Cloud SQL, Identity-Aware Proxy, and comprehensive infrastructure as code with Terraform and Cloud Build.

## Critical Terraform + Cloud Build Learnings

### Resource Management Challenges

**Problem**: Terraform deployments often fail with "resource already exists" errors when infrastructure partially exists.

**Solution**: Implement comprehensive resource import strategy:
```yaml
# Always import existing resources before Terraform apply
- name: 'hashicorp/terraform:1.2.5'
  id: 'terraform-import-global-ip'
  entrypoint: 'sh'
  args:
    - '-c'
    - 'cd terraform && terraform import google_compute_global_address.default projects/${PROJECT_ID}/global/addresses/resource-name || echo "Import skipped"'
```

**Key Learning**: Use the `|| echo "Import skipped"` pattern to gracefully handle cases where resources don't exist.

### Service Account Permission Requirements

**Problem**: Cloud Build's Compute Engine default service account lacks permissions for complex deployments.

**Required Roles** (learned through trial and error):
- `roles/serviceusage.serviceUsageAdmin` - For enabling APIs
- `roles/artifactregistry.admin` - For container registry operations
- `roles/cloudsql.admin` - For database management
- `roles/compute.admin` - For networking and load balancer resources
- `roles/iap.admin` - For Identity-Aware Proxy configuration
- `roles/vpcaccess.admin` - For VPC connector management
- `roles/run.admin` - For Cloud Run service management
- `roles/iam.serviceAccountUser` - For service account operations

**Key Learning**: Grant permissions incrementally as deployment fails, rather than trying to guess upfront.

### API Enablement Strategy

**Problem**: Terraform operations fail when required APIs aren't enabled.

**Solution**: Enable ALL APIs upfront in Cloud Build pipeline:
```yaml
- name: 'gcr.io/cloud-builders/gcloud'
  id: 'enable-apis'
  args:
    - 'services'
    - 'enable'
    - 'compute.googleapis.com'
    - 'run.googleapis.com'
    - 'sqladmin.googleapis.com'
    - 'iap.googleapis.com'
    - 'servicenetworking.googleapis.com'
    - 'vpcaccess.googleapis.com'
    - 'artifactregistry.googleapis.com'
    - 'cloudbuild.googleapis.com'
    - 'secretmanager.googleapis.com'
```

**Key Learning**: API enablement can take several minutes - do it early in the pipeline.

### Cloud Run Deployment Gotchas

#### Reserved Environment Variables
**Problem**: Cloud Run v2 automatically sets `PORT` environment variable - overriding it causes deployment failure.

**Solution**: Remove PORT from environment variables, let Cloud Run set it automatically.

**Key Learning**: Check Cloud Run documentation for reserved environment variables.

#### Database Connection Configuration
**Problem**: n8n failed to start due to database connection issues.

**Root Causes and Solutions**:
1. **Wrong database name**: Secret contained Cloud SQL instance name instead of actual database name
2. **Connection timeout**: Default 20s timeout too short for Cloud SQL connections
3. **Private IP setup**: Required VPC connector and service networking configuration

**Solution Pattern**:
```yaml
env {
  name  = "DB_POSTGRESDB_HOST"
  value = data.google_sql_database_instance.instance.private_ip_address
}
env {
  name  = "DB_POSTGRESDB_CONNECTION_TIMEOUT"
  value = "60000"
}
```

### VPC and Private Networking

**Problem**: Cloud Run couldn't connect to Cloud SQL private IP.

**Solution Sequence**:
1. Enable Service Networking API
2. Create VPC peering for private services access:
   ```bash
   gcloud compute addresses create google-managed-services-default --global --purpose=VPC_PEERING --prefix-length=16 --network=default
   gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com --ranges=google-managed-services-default --network=default
   ```
3. Configure Cloud SQL for private IP
4. Set up VPC Access Connector with proper throughput limits

**Key Learning**: Private networking requires multiple components to work together - test connectivity systematically.

### IAP Configuration Pitfalls

**Problem**: IAP brand configuration used wrong project reference.

**Solution**: Use project number, not project ID:
```hcl
resource "google_iap_brand" "project_brand" {
  project = data.google_project.project.number  # Not var.project_id
}
```

**Key Learning**: Different GCP resources require different project identifiers (ID vs number).

### Debugging Best Practices

#### Named Steps
Always use descriptive step IDs for easier debugging:
```yaml
- name: 'hashicorp/terraform:1.2.5'
  id: 'terraform-import-global-forwarding-rule'  # Descriptive!
  # vs
  id: 'terraform-import'  # Too generic
```

#### Log Analysis
For Cloud Run issues, check specific revision logs:
```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=SERVICE_NAME AND resource.labels.revision_name=REVISION_NAME"
```

### Conditional Resource Creation Pattern

Instead of Terraform conditionals, use Cloud Build imports:
```yaml
# This pattern handles both existing and new resources
- name: 'hashicorp/terraform:1.2.5'
  id: 'terraform-import-resource'
  entrypoint: 'sh'
  args:
    - '-c'
    - 'cd terraform && terraform import RESOURCE || echo "Resource does not exist, will be created"'
```

### Secret Management Strategy

Create secrets conditionally in Cloud Build:
```bash
create_secret_if_not_exists() {
  local secret_name=$1
  local secret_value=$2
  if ! gcloud secrets describe $secret_name --quiet 2>/dev/null; then
    echo -n "$secret_value" | gcloud secrets create $secret_name --data-file=-
  else
    echo "Secret $secret_name already exists"
  fi
}
```

## Production Deployment Workflow

Based on our experience, the optimal deployment sequence is:

1. **Enable APIs** (first, as they take time)
2. **Create/verify secrets** (conditional creation)
3. **Import existing resources** (systematic approach)
4. **Build and push container images**
5. **Apply Terraform configuration**

## Common Failure Patterns and Solutions

1. **"Resource already exists"** → Add import statement
2. **"Permission denied"** → Grant role to Compute Engine SA
3. **"API not enabled"** → Add to API enablement list
4. **Container startup failure** → Check Cloud Run logs for specific revision
5. **Database connection timeout** → Verify VPC setup and increase timeout
6. **IAP redirect loops** → Check project number vs ID usage

## Key Architecture Decisions

- **Private networking**: Used VPC connector instead of public database access for security
- **IAP authentication**: Preferred over basic auth for enterprise-grade security  
- **Secret Manager**: Centralized credential management instead of environment variables
- **Cloud Build**: Chosen over manual Terraform for reproducible deployments
- **Resource imports**: Implemented to handle partial infrastructure states gracefully

### IAP OAuth Client Management Issue

**Problem**: Terraform kept creating new OAuth clients instead of reusing existing ones, leading to OAuth client proliferation.

**Root Cause**: No import logic for existing IAP OAuth clients.

**Solution Pattern**:
```yaml
# Step 1: Get existing client ID from Secret Manager
- name: 'gcr.io/cloud-builders/gcloud'
  id: 'get-iap-client-id'
  entrypoint: 'bash'
  args:
    - '-c'
    - |
      CLIENT_ID=$$(gcloud secrets versions access latest --secret="oauth-client-id-secret" 2>/dev/null || echo "")
      echo "$$CLIENT_ID" > /workspace/iap_client_id.txt

# Step 2: Import existing client if found
- name: 'hashicorp/terraform:1.2.5'
  id: 'terraform-import-iap-client'
  entrypoint: 'sh'
  args:
    - '-c'
    - |
      if [ -f /workspace/iap_client_id.txt ] && [ -s /workspace/iap_client_id.txt ]; then
        CLIENT_ID=$$(cat /workspace/iap_client_id.txt)
        cd terraform
        terraform import google_iap_client.project_client projects/PROJECT_NUMBER/brands/PROJECT_NUMBER/identityAwareProxyClients/$$CLIENT_ID || echo "Import skipped"
      fi
```

**Critical Learning**: 
- IAP client import requires **project number**, not project ID
- Use dynamic import based on stored credentials
- Implement two-step pattern: retrieve → import

### Terraform Sensitive Value Extraction Issue

**Problem**: Secret Manager contains corrupted OAuth client secrets with literal text `"secret = (sensitive value)"` instead of actual secret values, causing IAP Error code 11.

**Root Cause**: Terraform intentionally hides sensitive values in `terraform state show` output for security. Parsing this output extracts the placeholder text, not the actual secret.

**Evidence**: When extracted secrets contain ANSI color codes and text like:
```
    [1m[0msecret[0m[0m       = (sensitive value)
```

**Solution**: Use proper APIs instead of parsing Terraform state output:
```yaml
# WRONG: Parsing terraform state show (extracts placeholder text)
CLIENT_SECRET=$(terraform state show google_iap_client.project_client | grep "secret" | cut -d'"' -f2)

# CORRECT: Use IAP API to get actual secret value
ACCESS_TOKEN=$(gcloud auth print-access-token)
CLIENT_SECRET=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://iap.googleapis.com/v1/projects/PROJECT_NUMBER/brands/PROJECT_NUMBER/identityAwareProxyClients/$CLIENT_ID" \
  | grep -o '"secret":"[^"]*"' | cut -d'"' -f4)
```

**Critical Lessons**:
- **Never parse `terraform state show` for sensitive values** - it only shows placeholders
- **Always validate extracted secrets** before storing in Secret Manager
- **Use dedicated APIs** when available instead of parsing command output
- **Terraform's security features** can interfere with automation - work with them, not against them
- **Corrupted secrets cause IAP Error code 11** - check Secret Manager content with `hexdump -C`

**Prevention**: Implement secret validation in Cloud Build pipelines:
```bash
# Validate that extracted secret looks like a real OAuth client secret
if [[ "$CLIENT_SECRET" =~ ^GOCSPX-[A-Za-z0-9_-]{28}$ ]]; then
  echo "Valid OAuth client secret format"
else
  echo "ERROR: Invalid OAuth client secret format: $CLIENT_SECRET"
  exit 1
fi
```

This deployment pattern is now battle-tested and can be used as a template for similar Cloud Run + Cloud SQL deployments with IAP authentication.

### Cloud Build `bash` Step Variable Handling
**Problem**: `gcloud builds submit` fails with `invalid value for 'build.substitutions'` or `key ... is not matched in the template`.

**Root Cause**: Cloud Build uses `# GEMINI.md

This file provides guidance to Gemini when working with code in this repository.

## Project Overview

This is an n8n deployment project for Google Cloud Platform (GCP). It demonstrates a production-ready deployment using Cloud Run, Cloud SQL, Identity-Aware Proxy, and comprehensive infrastructure as code with Terraform and Cloud Build.

## Critical Terraform + Cloud Build Learnings

### Resource Management Challenges

**Problem**: Terraform deployments often fail with "resource already exists" errors when infrastructure partially exists.

**Solution**: Implement comprehensive resource import strategy:
```yaml
# Always import existing resources before Terraform apply
- name: 'hashicorp/terraform:1.2.5'
  id: 'terraform-import-global-ip'
  entrypoint: 'sh'
  args:
    - '-c'
    - 'cd terraform && terraform import google_compute_global_address.default projects/${PROJECT_ID}/global/addresses/resource-name || echo "Import skipped"'
```

**Key Learning**: Use the `|| echo "Import skipped"` pattern to gracefully handle cases where resources don't exist.

### Service Account Permission Requirements

**Problem**: Cloud Build's Compute Engine default service account lacks permissions for complex deployments.

**Required Roles** (learned through trial and error):
- `roles/serviceusage.serviceUsageAdmin` - For enabling APIs
- `roles/artifactregistry.admin` - For container registry operations
- `roles/cloudsql.admin` - For database management
- `roles/compute.admin` - For networking and load balancer resources
- `roles/iap.admin` - For Identity-Aware Proxy configuration
- `roles/vpcaccess.admin` - For VPC connector management
- `roles/run.admin` - For Cloud Run service management
- `roles/iam.serviceAccountUser` - For service account operations

**Key Learning**: Grant permissions incrementally as deployment fails, rather than trying to guess upfront.

### API Enablement Strategy

**Problem**: Terraform operations fail when required APIs aren't enabled.

**Solution**: Enable ALL APIs upfront in Cloud Build pipeline:
```yaml
- name: 'gcr.io/cloud-builders/gcloud'
  id: 'enable-apis'
  args:
    - 'services'
    - 'enable'
    - 'compute.googleapis.com'
    - 'run.googleapis.com'
    - 'sqladmin.googleapis.com'
    - 'iap.googleapis.com'
    - 'servicenetworking.googleapis.com'
    - 'vpcaccess.googleapis.com'
    - 'artifactregistry.googleapis.com'
    - 'cloudbuild.googleapis.com'
    - 'secretmanager.googleapis.com'
```

**Key Learning**: API enablement can take several minutes - do it early in the pipeline.

### Cloud Run Deployment Gotchas

#### Reserved Environment Variables
**Problem**: Cloud Run v2 automatically sets `PORT` environment variable - overriding it causes deployment failure.

**Solution**: Remove PORT from environment variables, let Cloud Run set it automatically.

**Key Learning**: Check Cloud Run documentation for reserved environment variables.

#### Database Connection Configuration
**Problem**: n8n failed to start due to database connection issues.

**Root Causes and Solutions**:
1. **Wrong database name**: Secret contained Cloud SQL instance name instead of actual database name
2. **Connection timeout**: Default 20s timeout too short for Cloud SQL connections
3. **Private IP setup**: Required VPC connector and service networking configuration

**Solution Pattern**:
```yaml
env {
  name  = "DB_POSTGRESDB_HOST"
  value = data.google_sql_database_instance.instance.private_ip_address
}
env {
  name  = "DB_POSTGRESDB_CONNECTION_TIMEOUT"
  value = "60000"
}
```

### VPC and Private Networking

**Problem**: Cloud Run couldn't connect to Cloud SQL private IP.

**Solution Sequence**:
1. Enable Service Networking API
2. Create VPC peering for private services access:
   ```bash
   gcloud compute addresses create google-managed-services-default --global --purpose=VPC_PEERING --prefix-length=16 --network=default
   gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com --ranges=google-managed-services-default --network=default
   ```
3. Configure Cloud SQL for private IP
4. Set up VPC Access Connector with proper throughput limits

**Key Learning**: Private networking requires multiple components to work together - test connectivity systematically.

### IAP Configuration Pitfalls

**Problem**: IAP brand configuration used wrong project reference.

**Solution**: Use project number, not project ID:
```hcl
resource "google_iap_brand" "project_brand" {
  project = data.google_project.project.number  # Not var.project_id
}
```

**Key Learning**: Different GCP resources require different project identifiers (ID vs number).

### Debugging Best Practices

#### Named Steps
Always use descriptive step IDs for easier debugging:
```yaml
- name: 'hashicorp/terraform:1.2.5'
  id: 'terraform-import-global-forwarding-rule'  # Descriptive!
  # vs
  id: 'terraform-import'  # Too generic
```

#### Log Analysis
For Cloud Run issues, check specific revision logs:
```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=SERVICE_NAME AND resource.labels.revision_name=REVISION_NAME"
```

### Conditional Resource Creation Pattern

Instead of Terraform conditionals, use Cloud Build imports:
```yaml
# This pattern handles both existing and new resources
- name: 'hashicorp/terraform:1.2.5'
  id: 'terraform-import-resource'
  entrypoint: 'sh'
  args:
    - '-c'
    - 'cd terraform && terraform import RESOURCE || echo "Resource does not exist, will be created"'
```

### Secret Management Strategy

Create secrets conditionally in Cloud Build:
```bash
create_secret_if_not_exists() {
  local secret_name=$1
  local secret_value=$2
  if ! gcloud secrets describe $secret_name --quiet 2>/dev/null; then
    echo -n "$secret_value" | gcloud secrets create $secret_name --data-file=-
  else
    echo "Secret $secret_name already exists"
  fi
}
```

## Production Deployment Workflow

Based on our experience, the optimal deployment sequence is:

1. **Enable APIs** (first, as they take time)
2. **Create/verify secrets** (conditional creation)
3. **Import existing resources** (systematic approach)
4. **Build and push container images**
5. **Apply Terraform configuration**

## Common Failure Patterns and Solutions

1. **"Resource already exists"** → Add import statement
2. **"Permission denied"** → Grant role to Compute Engine SA
3. **"API not enabled"** → Add to API enablement list
4. **Container startup failure** → Check Cloud Run logs for specific revision
5. **Database connection timeout** → Verify VPC setup and increase timeout
6. **IAP redirect loops** → Check project number vs ID usage

## Key Architecture Decisions

- **Private networking**: Used VPC connector instead of public database access for security
- **IAP authentication**: Preferred over basic auth for enterprise-grade security  
- **Secret Manager**: Centralized credential management instead of environment variables
- **Cloud Build**: Chosen over manual Terraform for reproducible deployments
- **Resource imports**: Implemented to handle partial infrastructure states gracefully

### IAP OAuth Client Management Issue

**Problem**: Terraform kept creating new OAuth clients instead of reusing existing ones, leading to OAuth client proliferation.

**Root Cause**: No import logic for existing IAP OAuth clients.

**Solution Pattern**:
```yaml
# Step 1: Get existing client ID from Secret Manager
- name: 'gcr.io/cloud-builders/gcloud'
  id: 'get-iap-client-id'
  entrypoint: 'bash'
  args:
    - '-c'
    - |
      CLIENT_ID=$$(gcloud secrets versions access latest --secret="oauth-client-id-secret" 2>/dev/null || echo "")
      echo "$$CLIENT_ID" > /workspace/iap_client_id.txt

# Step 2: Import existing client if found
- name: 'hashicorp/terraform:1.2.5'
  id: 'terraform-import-iap-client'
  entrypoint: 'sh'
  args:
    - '-c'
    - |
      if [ -f /workspace/iap_client_id.txt ] && [ -s /workspace/iap_client_id.txt ]; then
        CLIENT_ID=$$(cat /workspace/iap_client_id.txt)
        cd terraform
        terraform import google_iap_client.project_client projects/PROJECT_NUMBER/brands/PROJECT_NUMBER/identityAwareProxyClients/$$CLIENT_ID || echo "Import skipped"
      fi
```

**Critical Learning**: 
- IAP client import requires **project number**, not project ID
- Use dynamic import based on stored credentials
 for its own substitution variables (e.g., `$PROJECT_ID`, `${_FOO}`), which conflicts with standard `bash` syntax for shell variables (`$VAR`) and command substitution (`$(command)`). The Cloud Build pre-processor attempts to substitute `bash` variables, causing an error when they are not found in the build's substitutions list.

**Solution**: When using `bash` in a Cloud Build step, you must escape the dollar signs for any variables or command substitutions that are intended for the shell to interpret at runtime.
- **Shell Variables**: Use `$VAR` instead of `$VAR`.
- **Command Substitution**: Use `$(command)` instead of `$(command)`.
- **Cloud Build Substitutions**: Leave these as-is (e.g., `$PROJECT_ID`, `${_FOO}`).

### Application URL Configuration behind IAP
**Problem**: The application loads, but some internal API calls or static asset loads fail with 401 Unauthorized or 404 Not Found errors.

**Root Cause**: The application is unaware of its public-facing URL when running behind a reverse proxy like a Load Balancer with IAP. It generates internal URLs based on its service name (e.g., `http://n8n:5678`), which are not accessible from the user's browser.

**Solution**: Set the application-specific environment variable that tells it its public URL. For n8n, this is `N8N_EDITOR_BASE_URL`. This ensures that all URLs generated by the application use the correct public domain.
```hcl
# terraform/cloud_run.tf
resource "google_cloud_run_v2_service" "n8n_service" {
  template {
    containers {
      env {
        name  = "N8N_EDITOR_BASE_URL"
        value = "https://${var.domain_name}"
      }
      # ... other env vars
    }
  }
}
```
