variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "bucket_name" {
  description = "Globally unique GCS bucket name"
  type        = string
}

variable "gcp_region" {
  description = "GCS bucket region"
  type        = string
  default     = "EU"
}

variable "force_destroy_bucket" {
  description = "Allow terraform destroy to delete the bucket if it holds files"
  type        = bool
  default     = true
}

variable "snowflake_organization_name" {
  description = "snowflake organization name"
  type        = string
}

variable "snowflake_account_name" {
  description = "snowflake account name"
  type        = string
}

variable "snowflake_user" {
  description = "snowflake username"
  type        = string
}

variable "snowflake_private_key_path" {
  description = "Path to the PKCS8 private key from gen_keys.py"
  type        = string
}