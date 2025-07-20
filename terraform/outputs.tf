output "n8n_url" {
  description = "The URL of the n8n application."
  value       = "https://${var.domain_name}"
}

output "load_balancer_ip" {
  description = "The IP address of the external load balancer."
  value       = google_compute_global_address.default.address
}

output "iap_oauth_client_id" {
  description = "The OAuth client ID for IAP"
  value       = google_iap_client.project_client.client_id
}

output "iap_oauth_client_secret" {
  description = "The OAuth client secret for IAP"
  value       = google_iap_client.project_client.secret
  sensitive   = true
}
