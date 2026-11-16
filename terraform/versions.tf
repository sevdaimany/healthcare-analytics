terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = ">= 2.20, < 3.0" # stay on major version 2; the provider renames things between majors
    }
  }
}