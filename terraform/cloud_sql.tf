# Fetches data about the existing Cloud SQL instance.

data "google_sql_database_instance" "instance" {
  name    = var.cloud_sql_instance_name
  project = var.project_id
}
