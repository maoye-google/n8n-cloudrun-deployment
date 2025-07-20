# Deploys the n8n application to Cloud Run.

resource "google_cloud_run_v2_service" "n8n_service" {
  name     = var.n8n_service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${data.google_artifact_registry_repository.repo.repository_id}/${var.n8n_service_name}:latest"
      
      ports {
        container_port = 5678
      }
      
      env {
        name  = "DB_TYPE"
        value = "postgresdb"
      }
      env {
        name  = "DB_POSTGRESDB_HOST"
        value = data.google_sql_database_instance.instance.private_ip_address
      }
      env {
        name = "DB_POSTGRESDB_USER"
        value_source {
          secret_key_ref {
            secret  = var.db_user_secret_name
            version = "latest"
          }
        }
      }
      env {
        name = "DB_POSTGRESDB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = var.db_password_secret_name
            version = "latest"
          }
        }
      }
      env {
        name = "DB_POSTGRESDB_DATABASE"
        value_source {
          secret_key_ref {
            secret  = var.db_name_secret_name
            version = "latest"
          }
        }
      }
      env {
        name  = "N8N_HOST"
        value = var.domain_name
      }
      env {
        name  = "WEBHOOK_URL"
        value = "https://${var.domain_name}/"
      }
      env {
        name  = "DB_POSTGRESDB_CONNECTION_TIMEOUT"
        value = "60000"
      }
      env {
        name  = "N8N_PROTOCOL"
        value = "https"
      }
      env {
        name  = "N8N_PORT"
        value = "5678"
      }
      env {
        name  = "N8N_LISTEN_ADDRESS"
        value = "0.0.0.0"
      }
    }

    scaling {
      min_instance_count = 1
      max_instance_count = 2
    }

    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "ALL_TRAFFIC"
    }
  }

  traffic {
    percent         = 100
    type            = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  depends_on = [
    google_project_service.cloudrun_api,
    google_project_service.sqladmin_api,
    google_vpc_access_connector.connector
  ]
}

# Serverless VPC Access Connector
resource "google_vpc_access_connector" "connector" {
  name          = "${var.n8n_service_name}-vpc-connector"
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = "default"
  min_throughput = 200  # Required parameter: min throughput in Mbps (200-1000, multiples of 100)
  max_throughput = 300  # Optional: max throughput in Mbps (min_throughput to 1000, multiples of 100)
}

# Allow IAP service account to invoke the Cloud Run service
resource "google_cloud_run_service_iam_member" "iap_invoker" {
  location = google_cloud_run_v2_service.n8n_service.location
  service  = google_cloud_run_v2_service.n8n_service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-iap.iam.gserviceaccount.com"
}
