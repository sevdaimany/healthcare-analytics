{{
    config(materialized = "incremental", unique_key = 'admission_id',
           incremental_strategy="merge", on_schema_change = 'sync_all_columns')
}}

{% if is_incremental() %}
WITH affected_patients AS (
    SELECT patient_id
    FROM {{ source('bronze', 'patient_admissions') }}
    WHERE upload_dttm > (SELECT MAX(upload_dttm) FROM {{ this }})
),
source AS (
{% else %}
WITH source AS (
{% endif %}
    SELECT 
        admission_id, patient_id, doctor_id, hospital_id,
        admit_date::varchar as admit_date,
        department, admission_type, diagnosis_code, length_of_stay,
        readmission_flag, file_name, upload_dttm, load_dttm,
        'GATEKEEPER' as source_system
    FROM {{ source('bronze', 'patient_admissions') }}
    {% if is_incremental() %}
    WHERE patient_id in (SELECT patient_id FROM affected_patients)
    {% endif %}
),

deduplicated AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY admission_id ORDER BY upload_dttm DESC) AS _row_num
    FROM source
),

-- Standardize + decode + basic typing
cleaned AS (

    SELECT
        admission_id,
        patient_id,
        upper(trim(doctor_id)) AS doctor_id,
        upper(trim(hospital_id)) AS hospital_id,
        coalesce(
            try_to_date(admit_date, 'YYYY-MM-DD'),
            try_to_date(admit_date, 'DD/MM/YYYY')
        ) as admit_date,
        length_of_stay,

        case upper(trim(admission_type))
            when 'EMG' then 'Emergency'
            when 'URG' then 'Urgent'
            when 'ELC' then 'Elective'
            else 'Unknown'
        end as admission_type,

        upper(trim(department))     as department,
        upper(trim(diagnosis_code)) as diagnosis_code,
        cast(readmission_flag as boolean) as source_readmission_flag,

        -- lineage carried forward
        file_name, upload_dttm, load_dttm, source_system

    from deduplicated
    where _row_num = 1          -- keep only the latest row per admission

),

-- cross-row window logic: per-patient admission history
sequenced AS (
    SELECT 
        *,
        -- discharge date
        dateadd(day, length_of_stay, admit_date) AS discharge_date,

        -- Which visit number is this for the patient?
        ROW_NUMBER() OVER (PARTITION BY patient_id ORDER BY admit_date, admission_id) AS patient_visit_seq,

        -- total visits this patient ever has
        count(*) OVER (PARTITION BY patient_id) AS patient_total_visits,

        -- the patient's previous discharge date
        LAG(dateadd(day, length_of_stay, admit_date)) 
            OVER (PARTITION BY patient_id ORDER BY admit_date, admission_id) AS prev_discharge_date
        
        FROM cleaned
),

-- Real 30-day readmission + data quality flags
final AS (
    SELECT
        admission_id,
        patient_id,
        doctor_id,
        hospital_id,
        admit_date,
        discharge_date,
        length_of_stay,
        admission_type,
        department,
        diagnosis_code,
        source_readmission_flag,
        patient_visit_seq,
        patient_total_visits,

        -- compute 30-day readmission: was there a prior discharge
        -- within 30 days of this admission?
        CASE 
            WHEN prev_discharge_date is not Null
                AND datediff(day, prev_discharge_date, admit_date) <= 30
             AND datediff(day, prev_discharge_date, admit_date) >= 0
            THEN true ELSE false
        END AS is_30day_readmission,

        -- days since the patient's last discharge (null for the first visit)
        datediff(day, prev_discharge_date, admit_date) AS days_since_last_visit,
        
        -- Data Quality
        CASE
            WHEN datediff(day, prev_discharge_date, admit_date) < 0 THEN 'OVERLAPPING_ADMISSION'
            WHEN length_of_stay < 0           THEN 'INVALID_NEGATIVE_LOS'
            WHEN length_of_stay > 365         THEN 'INVALID_EXCESSIVE_LOS'
            WHEN admit_date > current_date()  THEN 'INVALID_FUTURE_DATE'
            WHEN doctor_id is null            THEN 'MISSING_DOCTOR'
            WHEN hospital_id is null          THEN 'MISSING_HOSPITAL'
            ELSE 'VALID'
        END AS dq_status,

        -- single boolean gate downstream models can filter on
        CASE
            WHEN length_of_stay BETWEEN 0 AND 365
             AND admit_date <= current_date()
             AND doctor_id is not null
             AND hospital_id is not null
            THEN true ELSE false
        END as is_valid,

        -- lineage
        file_name, upload_dttm, load_dttm, source_system

    FROM sequenced

)

SELECT * FROM final
