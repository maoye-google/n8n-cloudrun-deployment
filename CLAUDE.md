# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an n8n deployment project for Google Cloud Platform (GCP). It deploys n8n (a workflow automation tool) using Cloud Run with a PostgreSQL database, behind Identity-Aware Proxy (IAP) for secure access.

## Infrastructure Commands

### Deploy Infrastructure
```bash
# Build and deploy using Google Cloud Build
gcloud builds submit --config cloudbuild.yaml

# Manual Terraform deployment
cd terraform
terraform init
terraform plan
terraform apply
```

### Terraform Operations
```bash
cd terraform
terraform init                    # Initialize Terraform
terraform plan                    # Preview changes
terraform apply                   # Apply changes
terraform destroy                 # Destroy infrastructure
terraform output                  # Show outputs
```

### Docker Operations
```bash
# Build the n8n container locally
docker build -t n8n-custom .

# Run container locally for testing
docker run -p 5678:5678 n8n-custom
```

## Architecture

### Infrastructure Components

The deployment consists of:

1. **Cloud Run Service** (`terraform/cloud_run.tf`): Runs the n8n application container
   - Based on official n8n Docker image with custom permissions
   - Configured with PostgreSQL database connection
   - Environment variables sourced from Secret Manager
   - VPC connector for private database access

2. **Load Balancer** (`terraform/load_balancer.tf`): HTTPS load balancer with SSL certificate
   - Global static IP address
   - Serverless Network Endpoint Group (NEG)
   - Google-managed SSL certificate
   - IAP integration for authentication

3. **Identity-Aware Proxy** (`terraform/iap.tf`): Security layer
   - OAuth 2.0 client configuration
   - Domain-based access control
   - Backend service IAM policies

4. **Database** (`terraform/cloud_sql.tf`): Uses existing Cloud SQL PostgreSQL instance
   - Private IP configuration
   - Credentials stored in Secret Manager

5. **Artifact Registry** (`terraform/artifact_registry.tf`): Container image storage

### Configuration Variables

Key variables in `terraform/variables.tf`:
- `project_id`: GCP project (default: "personal-n8n-playground")
- `region`: Deployment region (default: "us-central1")
- `domain_name`: Custom domain (default: "n8n.maoye.demo.altostrat.com")
- `cloud_sql_instance_name`: Database instance name
- Secret Manager secret names for database credentials and IAP OAuth

### Security

- Database credentials stored in Secret Manager
- IAP OAuth client secrets in Secret Manager
- Domain-restricted access via IAP
- Private VPC connectivity between Cloud Run and database
- Non-root container execution

## Environment Setup

To initialize Claude Code environment:
```bash
./credentials/init_claude.sh
```

This script:
- Sets Google Cloud credentials for service account
- Configures Vertex AI integration
- Installs and starts Claude Code CLI

## File Structure

```
.
├── Dockerfile                 # n8n container configuration
├── cloudbuild.yaml           # Cloud Build pipeline
├── terraform/               # Infrastructure as Code
│   ├── variables.tf         # Configuration variables
│   ├── cloud_run.tf        # Cloud Run service
│   ├── load_balancer.tf    # HTTPS load balancer
│   ├── iap.tf              # Identity-Aware Proxy
│   ├── cloud_sql.tf        # Database configuration
│   └── *.tf                # Other infrastructure components
└── credentials/             # Authentication files
    ├── claude-code-sa-key.json  # Service account key
    └── init_claude.sh           # Environment setup script
```

## Common Operations

### Update n8n Version
1. Modify the base image in `Dockerfile`
2. Rebuild and deploy: `gcloud builds submit --config cloudbuild.yaml`

### Change Domain
1. Update `domain_name` variable in `terraform/variables.tf`
2. Apply Terraform changes: `terraform apply`
3. Update DNS records to point to the load balancer IP

### Access Logs
```bash
# View Cloud Run logs
gcloud logs read --project=personal-n8n-playground --resource=gce_instance
```

### Database Access
Database connection details are stored in Secret Manager and automatically injected into the Cloud Run service via environment variables.

## Terraform + Cloud Build Best Practices

### Critical Lessons Learned

Based on our deployment experience, here are essential practices for Terraform with Cloud Build:

#### 1. Resource Conflict Management
**Always import existing resources** to avoid "already exists" errors:
```yaml
# Import existing resources before Terraform apply
- name: 'hashicorp/terraform:1.2.5'
  id: 'terraform-import-resource'
  entrypoint: 'sh'
  args:
    - '-c'
    - 'cd terraform && terraform import RESOURCE_TYPE.NAME RESOURCE_PATH || echo "Import skipped"'
```

#### 2. Service Account Permissions
Cloud Build requires extensive permissions. Grant these roles to Compute Engine default SA:
- `roles/serviceusage.serviceUsageAdmin`
- `roles/artifactregistry.admin` 
- `roles/cloudsql.admin`
- `roles/compute.admin`
- `roles/iap.admin`
- `roles/vpcaccess.admin`
- `roles/run.admin`
- `roles/iam.serviceAccountUser`

#### 3. API Enablement
Enable ALL required APIs upfront in Cloud Build:
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
```

#### 4. Named Steps for Debugging
Always use descriptive step IDs:
```yaml
- name: 'hashicorp/terraform:1.2.5'
  id: 'terraform-apply-infrastructure'  # Not just 'terraform-apply'
```

#### 5. Conditional Secret Creation
Create secrets only if they don't exist:
```yaml
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

#### 6. Cloud Run Specific Gotchas
- **PORT environment variable**: Cloud Run v2 sets this automatically - don't override
- **Database timeouts**: Increase `DB_POSTGRESDB_CONNECTION_TIMEOUT` for Cloud SQL connections
- **Private IP**: Requires VPC connector and proper servicenetworking setup
- **IAP project reference**: Use `data.google_project.project.number` not project ID

#### 7. VPC and Networking
For private database connections:
1. Create VPC peering: `gcloud services vpc-peerings connect`
2. Enable Service Networking API
3. Configure VPC Access Connector with proper throughput limits
4. Use private IP addresses in database configuration

#### 8. Error Handling Pattern
Use graceful failure handling in Cloud Build:
```yaml
args:
  - '-c' 
  - 'operation_that_might_fail || echo "Operation skipped, continuing..."'
```

### Deployment Troubleshooting

**Common Issues and Solutions:**

1. **Container startup failures**: Check Cloud Run logs with specific revision name
2. **Database connection timeouts**: Verify VPC connector, private IP setup, and timeout values
3. **Permission errors**: Ensure Compute Engine SA has all required roles
4. **Resource conflicts**: Add import statements for existing infrastructure
5. **API errors**: Enable all required APIs before Terraform operations

### Production Deployment Checklist

- [ ] All required APIs enabled
- [ ] Service account permissions granted
- [ ] Existing resources imported in Cloud Build pipeline
- [ ] Secrets created and properly referenced
- [ ] VPC networking configured for private database access
- [ ] SSL certificates and domain DNS configured
- [ ] IAP OAuth credentials set up
- [ ] Cloud Run health checks and timeouts configured

#### 9. IAP OAuth Client Management
**Problem**: Terraform creates new OAuth clients on every deployment instead of reusing existing ones.

**Solution**: Import existing OAuth client using dynamic client ID from Secret Manager:
```yaml
# Get existing client ID from Secret Manager
- name: 'gcr.io/cloud-builders/gcloud'
  id: 'get-iap-client-id'
  entrypoint: 'bash'
  args:
    - '-c'
    - |
      CLIENT_ID=$$(gcloud secrets versions access latest --secret="oauth-client-id-secret" 2>/dev/null || echo "")
      echo "$$CLIENT_ID" > /workspace/iap_client_id.txt

# Import existing IAP OAuth client if it exists  
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

**Key Learning**: 
- IAP OAuth client import requires project **number**, not project ID
- Store client ID in Secret Manager for dynamic import logic
- Use two-step approach: retrieve client ID then import with Terraform

### 12. Terraform Sensitive Value Extraction Anti-Pattern

**Problem**: Secret Manager contains corrupted OAuth client secrets with literal text `"secret = (sensitive value)"` instead of actual secret values, causing IAP Error code 11.

**Root Cause**: Terraform intentionally hides sensitive values in `terraform state show` output for security. Parsing this output extracts the placeholder text, not the actual secret.

**Evidence of Corruption**: When secrets contain ANSI color codes and text like:
```bash
# Corrupted secret in Secret Manager (from hexdump):
00000000  20 20 20 20 1b 5b 31 6d  1b 5b 30 6d 73 65 63 72  |    .[1m.[0msecr|
00000010  65 74 1b 5b 30 6d 1b 5b  30 6d 20 20 20 20 20 20  |et.[0m.[0m      |
00000020  20 3d 20 28 73 65 6e 73  69 74 69 76 65 20 76 61  | = (sensitive va|
```

**Anti-Pattern (WRONG)**:
```yaml
# DON'T DO THIS - extracts placeholder text, not actual secret
CLIENT_SECRET=$(terraform state show google_iap_client.project_client | grep "secret" | cut -d'"' -f2)
```

**Correct Solution**:
```yaml
# Use IAP API to get actual secret value
ACCESS_TOKEN=$(gcloud auth print-access-token)
CLIENT_SECRET=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://iap.googleapis.com/v1/projects/PROJECT_NUMBER/brands/PROJECT_NUMBER/identityAwareProxyClients/$CLIENT_ID" \
  | grep -o '"secret":"[^"]*"' | cut -d'"' -f4)
```

**Critical Prevention Measures**:
1. **Never parse `terraform state show` for sensitive values**
2. **Always validate extracted secrets** before storing:
   ```bash
   # Validate OAuth client secret format
   if [[ "$CLIENT_SECRET" =~ ^GOCSPX-[A-Za-z0-9_-]{28}$ ]]; then
     echo "Valid OAuth client secret format"
   else
     echo "ERROR: Invalid secret format: $CLIENT_SECRET"
     exit 1
   fi
   ```
3. **Use dedicated APIs** when available instead of parsing command output
4. **Check Secret Manager content** with `hexdump -C` if IAP Error code 11 occurs
5. **Terraform's security features** are designed to prevent secret exposure - work with them

**Debugging Corrupted Secrets**:
```bash
# Check if Secret Manager contains corrupted data
gcloud secrets versions access latest --secret='oauth-client-secret' | hexdump -C | head -3

# Valid OAuth client secret should start with "GOCSPX-"
gcloud secrets versions access latest --secret='oauth-client-secret'
# Output should be: GOCSPX-xxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### 10. Cloud Build `bash` Step Variable Handling
**Problem**: `gcloud builds submit` fails with `invalid value for 'build.substitutions'` or `key ... is not matched in the template`.

**Root Cause**: Cloud Build uses `# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an n8n deployment project for Google Cloud Platform (GCP). It deploys n8n (a workflow automation tool) using Cloud Run with a PostgreSQL database, behind Identity-Aware Proxy (IAP) for secure access.

## Infrastructure Commands

### Deploy Infrastructure
```bash
# Build and deploy using Google Cloud Build
gcloud builds submit --config cloudbuild.yaml

# Manual Terraform deployment
cd terraform
terraform init
terraform plan
terraform apply
```

### Terraform Operations
```bash
cd terraform
terraform init                    # Initialize Terraform
terraform plan                    # Preview changes
terraform apply                   # Apply changes
terraform destroy                 # Destroy infrastructure
terraform output                  # Show outputs
```

### Docker Operations
```bash
# Build the n8n container locally
docker build -t n8n-custom .

# Run container locally for testing
docker run -p 5678:5678 n8n-custom
```

## Architecture

### Infrastructure Components

The deployment consists of:

1. **Cloud Run Service** (`terraform/cloud_run.tf`): Runs the n8n application container
   - Based on official n8n Docker image with custom permissions
   - Configured with PostgreSQL database connection
   - Environment variables sourced from Secret Manager
   - VPC connector for private database access

2. **Load Balancer** (`terraform/load_balancer.tf`): HTTPS load balancer with SSL certificate
   - Global static IP address
   - Serverless Network Endpoint Group (NEG)
   - Google-managed SSL certificate
   - IAP integration for authentication

3. **Identity-Aware Proxy** (`terraform/iap.tf`): Security layer
   - OAuth 2.0 client configuration
   - Domain-based access control
   - Backend service IAM policies

4. **Database** (`terraform/cloud_sql.tf`): Uses existing Cloud SQL PostgreSQL instance
   - Private IP configuration
   - Credentials stored in Secret Manager

5. **Artifact Registry** (`terraform/artifact_registry.tf`): Container image storage

### Configuration Variables

Key variables in `terraform/variables.tf`:
- `project_id`: GCP project (default: "personal-n8n-playground")
- `region`: Deployment region (default: "us-central1")
- `domain_name`: Custom domain (default: "n8n.maoye.demo.altostrat.com")
- `cloud_sql_instance_name`: Database instance name
- Secret Manager secret names for database credentials and IAP OAuth

### Security

- Database credentials stored in Secret Manager
- IAP OAuth client secrets in Secret Manager
- Domain-restricted access via IAP
- Private VPC connectivity between Cloud Run and database
- Non-root container execution

## Environment Setup

To initialize Claude Code environment:
```bash
./credentials/init_claude.sh
```

This script:
- Sets Google Cloud credentials for service account
- Configures Vertex AI integration
- Installs and starts Claude Code CLI

## File Structure

```
.
├── Dockerfile                 # n8n container configuration
├── cloudbuild.yaml           # Cloud Build pipeline
├── terraform/               # Infrastructure as Code
│   ├── variables.tf         # Configuration variables
│   ├── cloud_run.tf        # Cloud Run service
│   ├── load_balancer.tf    # HTTPS load balancer
│   ├── iap.tf              # Identity-Aware Proxy
│   ├── cloud_sql.tf        # Database configuration
│   └── *.tf                # Other infrastructure components
└── credentials/             # Authentication files
    ├── claude-code-sa-key.json  # Service account key
    └── init_claude.sh           # Environment setup script
```

## Common Operations

### Update n8n Version
1. Modify the base image in `Dockerfile`
2. Rebuild and deploy: `gcloud builds submit --config cloudbuild.yaml`

### Change Domain
1. Update `domain_name` variable in `terraform/variables.tf`
2. Apply Terraform changes: `terraform apply`
3. Update DNS records to point to the load balancer IP

### Access Logs
```bash
# View Cloud Run logs
gcloud logs read --project=personal-n8n-playground --resource=gce_instance
```

### Database Access
Database connection details are stored in Secret Manager and automatically injected into the Cloud Run service via environment variables.

## Terraform + Cloud Build Best Practices

### Critical Lessons Learned

Based on our deployment experience, here are essential practices for Terraform with Cloud Build:

#### 1. Resource Conflict Management
**Always import existing resources** to avoid "already exists" errors:
```yaml
# Import existing resources before Terraform apply
- name: 'hashicorp/terraform:1.2.5'
  id: 'terraform-import-resource'
  entrypoint: 'sh'
  args:
    - '-c'
    - 'cd terraform && terraform import RESOURCE_TYPE.NAME RESOURCE_PATH || echo "Import skipped"'
```

#### 2. Service Account Permissions
Cloud Build requires extensive permissions. Grant these roles to Compute Engine default SA:
- `roles/serviceusage.serviceUsageAdmin`
- `roles/artifactregistry.admin` 
- `roles/cloudsql.admin`
- `roles/compute.admin`
- `roles/iap.admin`
- `roles/vpcaccess.admin`
- `roles/run.admin`
- `roles/iam.serviceAccountUser`

#### 3. API Enablement
Enable ALL required APIs upfront in Cloud Build:
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
```

#### 4. Named Steps for Debugging
Always use descriptive step IDs:
```yaml
- name: 'hashicorp/terraform:1.2.5'
  id: 'terraform-apply-infrastructure'  # Not just 'terraform-apply'
```

#### 5. Conditional Secret Creation
Create secrets only if they don't exist:
```yaml
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

#### 6. Cloud Run Specific Gotchas
- **PORT environment variable**: Cloud Run v2 sets this automatically - don't override
- **Database timeouts**: Increase `DB_POSTGRESDB_CONNECTION_TIMEOUT` for Cloud SQL connections
- **Private IP**: Requires VPC connector and proper servicenetworking setup
- **IAP project reference**: Use `data.google_project.project.number` not project ID

#### 7. VPC and Networking
For private database connections:
1. Create VPC peering: `gcloud services vpc-peerings connect`
2. Enable Service Networking API
3. Configure VPC Access Connector with proper throughput limits
4. Use private IP addresses in database configuration

#### 8. Error Handling Pattern
Use graceful failure handling in Cloud Build:
```yaml
args:
  - '-c' 
  - 'operation_that_might_fail || echo "Operation skipped, continuing..."'
```

### Deployment Troubleshooting

**Common Issues and Solutions:**

1. **Container startup failures**: Check Cloud Run logs with specific revision name
2. **Database connection timeouts**: Verify VPC connector, private IP setup, and timeout values
3. **Permission errors**: Ensure Compute Engine SA has all required roles
4. **Resource conflicts**: Add import statements for existing infrastructure
5. **API errors**: Enable all required APIs before Terraform operations

### Production Deployment Checklist

- [ ] All required APIs enabled
- [ ] Service account permissions granted
- [ ] Existing resources imported in Cloud Build pipeline
- [ ] Secrets created and properly referenced
- [ ] VPC networking configured for private database access
- [ ] SSL certificates and domain DNS configured
- [ ] IAP OAuth credentials set up
- [ ] Cloud Run health checks and timeouts configured

#### 9. IAP OAuth Client Management
**Problem**: Terraform creates new OAuth clients on every deployment instead of reusing existing ones.

**Solution**: Import existing OAuth client using dynamic client ID from Secret Manager:
```yaml
# Get existing client ID from Secret Manager
- name: 'gcr.io/cloud-builders/gcloud'
  id: 'get-iap-client-id'
  entrypoint: 'bash'
  args:
    - '-c'
    - |
      CLIENT_ID=$$(gcloud secrets versions access latest --secret="oauth-client-id-secret" 2>/dev/null || echo "")
      echo "$$CLIENT_ID" > /workspace/iap_client_id.txt

# Import existing IAP OAuth client if it exists  
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

**Key Learning**: 
- IAP OAuth client import requires project **number**, not project ID
- Store client ID in Secret Manager for dynamic import logic
 for its own substitution variables (e.g., `$PROJECT_ID`, `${_FOO}`), which conflicts with standard `bash` syntax for shell variables (`$VAR`) and command substitution (`$(command)`). The Cloud Build pre-processor attempts to substitute `bash` variables, causing an error when they are not found in the build's substitutions list.

**Solution**: When using `bash` in a Cloud Build step, you must escape the dollar signs for any variables or command substitutions that are intended for the shell to interpret at runtime.
- **Shell Variables**: Use `$VAR` instead of `$VAR`.
- **Command Substitution**: Use `$(command)` instead of `$(command)`.
- **Cloud Build Substitutions**: Leave these as-is (e.g., `$PROJECT_ID`, `${_FOO}`).

### 11. Application URL Configuration behind IAP
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
