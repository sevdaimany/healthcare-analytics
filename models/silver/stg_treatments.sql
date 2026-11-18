{{
    config(materialized='incremental', unique_key='treatment_id',
           incremental_strategy='merge', on_schema_change='sync_all_columns')
}}

{% if is_incremental() %}
WITH affected_keys as (
    SELECT 
        procedure_code,
        admission_id
    FROM 
        {{ source('bronze', 'treatment_records') }}
    WHERE load_dttm > (SELECT max(load_dttm) from {{ this }})
),

source as (
{% else %}
WITH source AS (
{% endif %}
    SELECT 
        treatment_id, admission_id, doctor_id, procedure_code,
        treatment_date::VARCHAR AS treatment_date, cost, outcome, 
        file_name, upload_dttm, load_dttm,
        'GATEKEEPER' as source_system
    FROM {{ source('bronze', 'treatment_records') }}
    {% if is_incremental() %}
    WHERE procedure_code in (SELECT procedure_code FROM affected_keys)
       OR admission_id in (SELECT admission_id FROM affected_keys)
    {% endif %}
),

-- 1. Dedup lastest version per treatment_id
deduplicated AS (
    SELECT *,
        ROW_NUMBER() OVER(PARTITION BY treatment_id ORDER BY load_dttm DESC) as _row_num
    FROM source
),

cleaned AS (
    SELECT 
        treatment_id,
        admission_id,
        upper(trim(doctor_id)) AS doctor_id,
        upper(trim(procedure_code)) AS procedure_code,

        coalesce(
            try_to_date(treatment_date, 'YYYY-MM-DD'),
            try_to_date(treatment_date, 'DD/MM/YYYY')
        ) as treatment_date,

        cost,

        CASE upper(trim(outcome))
            WHEN 'S' THEN 'Sucess'
            WHEN 'P' THEN 'Partial'
            WHEN 'F' THEN 'Failed'
            ELSE 'Unknown'
        END AS outcome,

        source_system,
        file_name, upload_dttm, load_dttm
    FROM deduplicated
    WHERE _row_num = 1
),

-- Statistical Context
stats AS (
    SELECT
        *,
        AVG(cost) OVER (PARTITION BY procedure_code) AS avg_cost_for_procedure,
        STDDEV(cost) OVER (PARTITION BY procedure_code) AS stddev_cost_for_procedure,

        -- 99th percentile cost per procedure
        percentile_cont(0.99) WITHIN GROUP (ORDER BY cost) 
            OVER (PARTITION BY procedure_code) AS p99_cost_for_procedure,
        
        ROW_NUMBER() OVER (
            PARTITION BY admission_id ORDER BY treatment_date, treatment_id
        ) AS treatment_seq_in_admission,

        count(*) OVER (PARTITION BY admission_id) AS treatments_in_admission
    FROM cleaned
),

final AS (
    SELECT
        treatment_id,
        admission_id,
        doctor_id,
        procedure_code,
        treatment_date,
        cost,
        outcome,
        treatment_seq_in_admission,
        treatments_in_admission,
        round(avg_cost_for_procedure, 2) AS avg_cost_for_procedure,

        -- COST Z-SCORE: how many std_devs from the procedure's mean?
        CASE
            WHEN stddev_cost_for_procedure IS NULL
                OR stddev_cost_for_procedure = 0 THEN 0
            ELSE round((cost - avg_cost_for_procedure) / stddev_cost_for_procedure, 2)
        END AS cost_zscore,

        -- Flag statistical outliers
        CASE
            WHEN  cost > p99_cost_for_procedure THEN True
            ELSE False
        END As is_cost_outlier,

        -- Boolean success flag for easy downstream rollups
        CASE
            WHEN OUTCOME = 'Success' THEN True
            ELSE False
        END  AS is_success,

        -- data quality
        CASE
            WHEN cost < 0                 THEN 'INVALID_NEGATIVE_COST'
            WHEN treatment_date IS NULL   THEN 'MISSING_DATE'
            WHEN outcome = 'Unknown'      THEN 'INVALID_OUTCOME'
            ELSE 'VALID'
        END as dq_status,

        source_system,
        file_name, upload_dttm, load_dttm
    FROM stats
)

SELECT * FROM final