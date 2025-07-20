# Configures Identity-Aware Proxy (IAP).

data "google_project" "project" {}

# Create or reference existing IAP brand
resource "google_iap_brand" "project_brand" {
  support_email     = "admin@maoye.altostrat.com"
  application_title = "Self-managed n8n Playground"
  project           = data.google_project.project.number
}

resource "google_iap_client" "project_client" {
  display_name = "n8n IAP Client"
  brand        = google_iap_brand.project_brand.name
}

# Set IAP policy on the backend service
resource "google_iap_web_backend_service_iam_member" "iap_access" {
  project              = var.project_id
  web_backend_service  = google_compute_backend_service.default.name
  role                 = "roles/iap.httpsResourceAccessor"
  member               = "domain:maoye.altostrat.com" # Example: "user:you@example.com", "group:my-group@example.com"
}
