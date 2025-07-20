# Creates the External HTTPS Load Balancer and associated resources.

# Create or reference existing global static IP address
resource "google_compute_global_address" "default" {
  name = "${var.n8n_service_name}-lb-ip"
  
  lifecycle {
    # Prevent destruction if resource exists
    prevent_destroy = true
  }
}

# Create a serverless network endpoint group (NEG) for the Cloud Run service
resource "google_compute_region_network_endpoint_group" "serverless_neg" {
  name                  = "${var.n8n_service_name}-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  cloud_run {
    service = google_cloud_run_v2_service.n8n_service.name
  }
}

# Create the backend service
resource "google_compute_backend_service" "default" {
  name                            = "${var.n8n_service_name}-backend"
  protocol                        = "HTTP"
  port_name                       = "http"
  load_balancing_scheme           = "EXTERNAL_MANAGED"
  enable_cdn                      = false
  iap {
    enabled                  = true
    oauth2_client_id         = data.google_secret_manager_secret_version.iap_oauth_client_id.secret_data
    oauth2_client_secret     = data.google_secret_manager_secret_version.iap_oauth_client_secret.secret_data
  }

  backend {
    group = google_compute_region_network_endpoint_group.serverless_neg.id
  }
}


# Create the URL map
resource "google_compute_url_map" "default" {
  name            = "${var.n8n_service_name}-url-map"
  default_service = google_compute_backend_service.default.id
}

# Create or reference existing SSL certificate
resource "google_compute_managed_ssl_certificate" "default" {
  name = "${var.n8n_service_name}-ssl-cert"
  managed {
    domains = [var.domain_name]
  }
  
  lifecycle {
    # Prevent destruction if resource exists
    prevent_destroy = true
  }
}

# Create the target HTTPS proxy
resource "google_compute_target_https_proxy" "default" {
  name             = "${var.n8n_service_name}-https-proxy"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}

# Create the global forwarding rule
resource "google_compute_global_forwarding_rule" "default" {
  name                  = "${var.n8n_service_name}-forwarding-rule"
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.default.id
  ip_address            = google_compute_global_address.default.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
