USE ROLE ACCOUNTADMIN;

CREATE STORAGE INTEGRATION IF NOT EXISTS HEALTHCARE_S3_INT
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = S3
    ENABLED = TRUE
    STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::849363694209:role/snowflake-healthcare-role'
    STORAGE_ALLOWED_LOCATIONS = (
        's3://s3-healthcare-bucket-eu/incoming/',
        's3://s3-healthcare-bucket-eu/processed/',
        's3://s3-healthcare-bucket-eu/quarantine/'
        );
GRANT USAGE ON INTEGRATION HEALTHCARE_S3_INT TO ROLE HEALTHCARE_ROLE;

DESC INTEGRATION HEALTHCARE_S3_INT;
