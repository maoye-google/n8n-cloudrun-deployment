# n8n on Google Cloud Platform

This project provides a production-ready deployment of [n8n](https://n8n.io/), a popular workflow automation tool, on the Google Cloud Platform (GCP). The infrastructure is defined using Terraform and deployed via Cloud Build, ensuring a repeatable and automated setup.

## Architecture

The architecture is designed for security, scalability, and maintainability:

-   **[Cloud Run](https://cloud.google.com/run)**: The n8n application is containerized and runs as a serverless service on Cloud Run, allowing it to scale based on demand.
-   **[Cloud SQL](https://cloud.google.com/sql)**: A PostgreSQL database is used for n8n's data persistence, configured with a private IP for enhanced security.
-   **[External HTTPS Load Balancer](https://cloud.google.com/load-balancing/docs/https)**: A global load balancer provides a secure (HTTPS) entry point for the n8n application, with a static IP address and a Google-managed SSL certificate.
-   **[Identity-Aware Proxy (IAP)](https://cloud.google.com/iap)**: IAP secures access to the n8n instance, ensuring that only authorized users within a specific domain can access the application.
-   **[Secret Manager](https://cloud.google.com/secret-manager)**: All sensitive information, such as database credentials and IAP OAuth secrets, is securely stored in Secret Manager.
-   **[Artifact Registry](https://cloud.google.com/artifact-registry)**: The custom n8n Docker image is stored and managed in Artifact Registry.
-   **[Cloud Build](https://cloud.google.com/build)**: A `cloudbuild.yaml` file defines the continuous integration and deployment (CI/CD) pipeline, which automates the entire deployment process.

## Deployment

The deployment is fully automated using Cloud Build. To deploy the n8n application, you need to have the `gcloud` CLI installed and configured.

### Prerequisites

1.  A GCP project with billing enabled.
2.  A registered domain name for which you can configure DNS records.
3.  The following APIs enabled in your GCP project:
    -   Cloud Resource Manager API
    -   Secret Manager API
    -   Compute Engine API
    -   Cloud Run Admin API
    -   Cloud SQL Admin API
    -   Identity-Aware Proxy API
    -   Artifact Registry API
    -   Cloud Build API
    -   VPC Access API
    -   Service Networking API

### Deployment Steps

1.  **Clone the repository:**
    ```sh
    git clone <repository-url>
    cd <repository-directory>
    ```

2.  **Configure the deployment:**
    -   Update the `substitutions` section in `cloudbuild.yaml` with your specific values for `_REGION`, `_CLOUD_SQL_INSTANCE_NAME`, `_DOMAIN_NAME`, etc.
    -   Update the `terraform/variables.tf` file with your project-specific details, such as `project_id` and `domain_name`.

3.  **Run the Cloud Build pipeline:**
    ```sh
    gcloud builds submit --config cloudbuild.yaml
    ```
    This command will trigger the Cloud Build pipeline, which will:
    -   Enable the necessary APIs.
    -   Create secrets in Secret Manager.
    -   Import existing infrastructure to prevent conflicts.
    -   Build and push the n8n Docker image to Artifact Registry.
    -   Apply the Terraform configuration to create or update the infrastructure.
    -   Update Secret Manager with the IAP OAuth client credentials.

## Terraform

The `terraform` directory contains all the Infrastructure as Code (IaC) definitions for this project. The resources are logically separated into different files (e.g., `cloud_run.tf`, `cloud_sql.tf`, `load_balancer.tf`).

### Manual Terraform Deployment

While the recommended deployment method is via Cloud Build, you can also deploy the infrastructure manually using Terraform:

1.  **Initialize Terraform:**
    ```sh
    cd terraform
    terraform init
    ```

2.  **Plan the deployment:**
    ```sh
    terraform plan
    ```

3.  **Apply the changes:**
    ```sh
    terraform apply
    ```

## Docker

The `Dockerfile` in the root of the project is used to build a custom n8n image. It starts from the official n8n image and sets the correct permissions for the `node` user, which is a requirement for running n8n in a read-only filesystem environment like Cloud Run.

## Security

-   **Private Networking**: The Cloud Run service communicates with the Cloud SQL database over a private IP address using a VPC connector.
-   **Authentication**: Access to the n8n application is protected by IAP, which enforces authentication and authorization.
-   **Secrets Management**: All sensitive data is stored securely in Secret Manager.

## AI Assistant Integration

This project includes configuration files (`GEMINI.md` and `CLAUDE.md`) to provide context to AI assistants like Google's Gemini and Anthropic's Claude, enabling them to understand the project's architecture and deployment process. The `credentials/init_claude.sh` script is an example of how to set up the environment for an AI assistant.
