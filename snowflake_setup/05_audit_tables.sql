USE ROLE HEALTHCARE_ROLE;
USE DATABASE HEALTHCARE_DB;
USE SCHEMA AUDIT;

-- FILE PROCESSING_LOG  (one row per file processed by the gatekeeper)
CREATE OR REPLACE TABLE HEALTHCARE_DB.AUDIT.FILE_PROCESSING_LOG (
    run_id VARCHAR(20), 
    file_name VARCHAR(500), -- the name of the file
    feed_type VARCHAR(50), -- admissions / treatments / claims
    status VARCHAR(20), -- PASSED or QUARANTINED
    rows_loaded NUMBER(12,0),  -- number of rows loaded into the raw table
    checks_passed NUMBER(5,0),  -- number of checks that passed
    checks_failed NUMBER(5,0), -- number of checks that failed
    failed_checks VARCHAR(5000), -- list of failed checks
    action VARCHAR(1000), -- the action taken
    processed_at TIMESTAMP_NTZ
);

-- DQ_METRICS_LOG  (one row per check per file)
CREATE OR REPLACE TABLE HEALTHCARE_DB.AUDIT.DQ_METRICS_LOG (
    run_id            VARCHAR(20),
    file_name         VARCHAR(500),
    check_name        VARCHAR(200), -- the name of the check
    check_tier        VARCHAR(20),  --GATE / THRESHOLD / ADVISORY
    check_result      VARCHAR(10),  -- PASS / FAIL
    details           VARCHAR(2000), -- numbers / message
    checked_at        TIMESTAMP_NTZ
);

-- PIPELINE_ERROR_LOG  (one row per failed task in airflow)
CREATE OR REPLACE TABLE HEALTHCARE_DB.AUDIT.PIPELINE_ERROR_LOG (
    dag_id           VARCHAR(200), -- the dag_id
    task_id          VARCHAR(200), -- the task_id
    status            VARCHAR(50),  -- the state of the task
    triggered_by     VARCHAR(100), -- the trigger
    attempt          VARCHAR(20), -- the attempt number
    error_summary    VARCHAR(5000), -- the error summary
    action          VARCHAR(2000), -- the action taken
    failed_at        TIMESTAMP_NTZ -- when the task failed
);

-- EMAIL_RECIPIENT_LOG  (one row per email recipient for alerts)
CREATE OR REPLACE TABLE HEALTHCARE_DB.AUDIT.EMAIL_RECIPIENT_LOG (
  recipient_email   VARCHAR(200),
  alert_type        VARCHAR(50),     -- e.g. DQ_FAILURE
  is_active         BOOLEAN,
  added_at          TIMESTAMP_NTZ
);

INSERT INTO HEALTHCARE_DB.AUDIT.EMAIL_RECIPIENT_LOG (recipient_email, alert_type, is_active, added_at)
SELECT 'imanysevda@gmail.com', 'DQ_FAILURE', TRUE, CURRENT_TIMESTAMP()
WHERE NOT EXISTS (
    SELECT 1 FROM HEALTHCARE_DB.AUDIT.EMAIL_RECIPIENT_LOG);


SHOW TABLES IN SCHEMA HEALTHCARE_DB.AUDIT;