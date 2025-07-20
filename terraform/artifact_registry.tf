# References the existing Artifact Registry repository for n8n Docker images.

data "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = var.repo_name
}
