USE ROLE ACCOUNTADMIN;

CREATE NOTIFICATION INTEGRATION IF NOT EXISTS  HEALTHCARE_EMAIL_INT
    TYPE ='EMAIL'
    ENABLED = TRUE
    ALLOWED_RECIPIENTS = ('imanysevda@gmail.com')
    COMMENT = 'Email integration for healthcare alerts';


GRANT USAGE ON INTEGRATION HEALTHCARE_EMAIL_INT TO ROLE HEALTHCARE_ROLE;

SHOW INTEGRATIONS;

-- TEST
CALL SYSTEM$SEND_EMAIL(
        'HEALTHCARE_EMAIL_INT', 
        'imanysevda@gmail.com',
        'Test email from Snowflake', 
        'This is a test email sent from Snowflake using the HEALTHCARE_EMAIL_INT integration.');