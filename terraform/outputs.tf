output "bucket_name" {
  value = google_storage_bucket.healthcare.name
}
output "snowflake_service_account" {
  description = "Should match STORAGE_GCP_SERVICE_ACCOUNT in DESC INTEGRATION"
  value       = snowflake_storage_integration_gcs.healthcare.describe_output[0].service_account
}
output "stage_urls" {
  value = { for p in local.prefixes : p => "gcs://${google_storage_bucket.healthcare.name}/${p}/" }
}