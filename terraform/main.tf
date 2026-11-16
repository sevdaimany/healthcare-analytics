locals {
  prefixes = ["incoming", "processed", "quarantine"]
  allowed_locations = [
    for p in local.prefixes :
    "gcs://${google_storage_bucket.healthcare.name}/${p}/"
  ]
}

# APIs the project needs
resource "google_project_service" "apis" {
  for_each = toset(["storage.googleapis.com",
  "iam.googleapis.com"])
  project            = var.gcp_project_id
  service            = each.value
  disable_on_destroy = false # leave the APIs on if you destroy this stack
}

# 1. The bucket. The three prefixes appear when the first file is uploaded.
resource "google_storage_bucket" "healthcare" {
  name                        = var.bucket_name
  location                    = var.gcp_region
  uniform_bucket_level_access = true       # IAM only, no per-file ACLs
  public_access_prevention    = "enforced" # can never be made public
  force_destroy               = var.force_destroy_bucket
  depends_on                  = [google_project_service.apis]
}


#  ------ SNOWFLAKE
# make snowflake generate its service account
resource "snowflake_storage_integration_gcs" "healthcare" {
  name                      = "HEALTHCARE_GCS_INT"
  enabled                   = true
  storage_allowed_locations = local.allowed_locations # only these three, never whole bucket
  comment                   = "Healthcare pipeline: GCS access for the gatekeeper"
  lifecycle {
    create_before_destroy = true # the provider's own examples use this
  }
}

# the permissions the gatekeeper needs
resource "google_project_iam_custom_role" "snowflake_gcs" {
  project     = var.gcp_project_id
  role_id     = "snowflakeHealthcareGcs"
  title       = "Snowflake healthcare GCS access"
  description = "Read, list, write and delete objects for the Snowflake storage integration"
  permissions = [
    "storage.buckets.get",             # Snowflake checks the bucket is reachable
    "storage.objects.list",            # LIST @stage
    "storage.objects.get",             # read files to load them
    "storage.objects.create",          # copy into processed/ and quarantine/
    "storage.objects.delete",          # remove the original from incoming/
    "storage.multipartUploads.create", # Snowflake's documented set for larger transfers
    "storage.multipartUploads.abort",
    "storage.multipartUploads.list",
    "storage.multipartUploads.listParts",
  ]
  depends_on = [google_project_service.apis]
}


# the handshake: give snowflake's service account that role on this bucket only
resource "google_storage_bucket_iam_member" "snowflake" {
  bucket = google_storage_bucket.healthcare.name
  role   = google_project_iam_custom_role.snowflake_gcs.name
  member = "serviceAccount:${snowflake_storage_integration_gcs.healthcare.describe_output[0].service_account}"
}
