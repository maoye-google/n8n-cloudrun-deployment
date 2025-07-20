# Configures Identity-Aware Proxy (IAP).

data "google_project" "project" {}

# Create or reference existing IAP brand
resource "google_iap_brand" "project_brand" {
  support_email     = "admin@maoye.altostrat.com"
  application_title = "Self-managed n8n Playground"
  project           = data.google_project.project.number
  
  lifecycle {
    # Ignore changes if the brand already exists
    ignore_changes = [support_email, application_title]
  }
}

resource "google_iap_client" "project_client" {
  display_name = "n8n IAP Client"
  brand        = google_iap_brand.project_brand.name
  
  # Use local-exec to update Secret Manager when client is created/updated
  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      echo "Updating Secret Manager with new IAP client credentials..."
      echo -n "${self.client_id}" | gcloud secrets versions add n8n-iap-oauth-client-id --data-file=- || echo "Failed to update client ID"
      echo -n "${self.secret}" | gcloud secrets versions add n8n-iap-oauth-client-secret --data-file=- || echo "Failed to update client secret"
      echo "Secret Manager updated with new IAP client credentials"
    EOT
  }
}

# Set IAP policy on the backend service
resource "google_iap_web_backend_service_iam_member" "iap_access" {
  project              = var.project_id
  web_backend_service  = google_compute_backend_service.default.name
  role                 = "roles/iap.httpsResourceAccessor"
  member               = "domain:maoye.altostrat.com" # Example: "user:you@example.com", "group:my-group@example.com"
}
