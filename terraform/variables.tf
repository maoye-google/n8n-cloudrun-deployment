  variable "project_id" {
  description = "The Google Cloud project ID."
  type        = string
  default     = "personal-n8n-playground"
}

variable "region" {
  description = "The Google Cloud region for resources."
  type        = string
  default     = "us-central1"
}

variable "cloud_sql_instance_name" {
  description = "The name of the Cloud SQL instance."
  type        = string
  default     = "n8n-db"
}

variable "domain_name" {
  description = "The verified domain name for the load balancer."
  type        = string
  default     = "n8n.maoye.demo.altostrat.com"
}

variable "n8n_service_name" {
  description = "The name of the Cloud Run service."
  type        = string
  default     = "n8n"
}

variable "repo_name" {
  description = "The name of the Artifact Registry repository."
  type        = string
  default     = "n8n-repo"
}

variable "db_user_secret_name" {
  description = "The name of the Secret Manager secret for the database user."
  type        = string
  default     = "n8n-db-user"
}

variable "db_password_secret_name" {
  description = "The name of the Secret Manager secret for the database password."
  type        = string
  default     = "n8n-db-password"
}

variable "db_name_secret_name" {
  description = "The name of the Secret Manager secret for the database name."
  type        = string
  default     = "n8n-db-name"
}

variable "iap_oauth_client_id_secret_name" {
  description = "The name of the Secret Manager secret for the IAP OAuth Client ID."
  type        = string
  default     = "n8n-iap-oauth-client-id"
}

variable "iap_oauth_client_secret_secret_name" {
  description = "The name of the Secret Manager secret for the IAP OAuth Client Secret."
  type        = string
  default     = "n8n-iap-oauth-client-secret"
}
