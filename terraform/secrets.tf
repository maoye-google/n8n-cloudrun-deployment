# Fetches the latest version of secrets from Google Secret Manager.

data "google_secret_manager_secret_version" "db_user" {
  secret = var.db_user_secret_name
}

data "google_secret_manager_secret_version" "db_password" {
  secret = var.db_password_secret_name
}

data "google_secret_manager_secret_version" "db_name" {
  secret = var.db_name_secret_name
}

data "google_secret_manager_secret_version" "iap_oauth_client_id" {
  secret = var.iap_oauth_client_id_secret_name
}

data "google_secret_manager_secret_version" "iap_oauth_client_secret" {
  secret = var.iap_oauth_client_secret_secret_name
}
