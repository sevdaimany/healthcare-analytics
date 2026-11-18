{{
    config(materialized="incremental", unique_key="claim_id",
    incremental_strategy='merge', on_schema_change="sync_all_columns")
}}

WITH source AS (
    SELECT claim_id, admission_id, insurance_id, claim_amount,
        approved_amount, claim_status, claim_date::varchar as claim_date,
        settle_date::varchar as settle_date,
        file_name, upload_dttm, load_dttm, 'GATEKEEPER' as source_system
    FROM {{source('bronze', 'insurance_claims')}}

    {% if is_incremental() %}
    WHERE load_dttm > (select MAX(load_dttm) from {{ this }})
    {% endif %}
),

deduplicated AS (
    SELECT *, row_number() over (partition by claim_id order by load_dttm desc) as _row_num
    FROM source
),

cleaned AS (
    SELECT 
        claim_id,
        admission_id,
        upper(trim(insurance_id)) as insurance_id,
        claim_amount, 
        approved_amount,
        CASE upper(trim(claim_status))
            WHEN 'A' then 'Approved'
            WHEN 'R' then 'Rejecred'
            WHEN 'P' then 'Pending'
            ELSE 'Unknown'
        END as claim_status,

        -- parse text dates (handles YYYY-MM-DD and DD/MM/YYYY)
        coalesce(
            try_to_date(claim_date, 'YYYY-MM-DD'),
            try_to_date(claim_date, 'DD/MM/YYYY')
        ) as claim_date,
        coalesce(
            try_to_date(settle_date, 'YYYY-MM-DD'),
            try_to_date(settle_date, 'DD/MM/YYYY')
        ) as settle_date,

        source_system,
        file_name, upload_dttm, load_dttm

    FROM deduplicated
    WHERE _row_num = 1
),

final AS (
    SELECT
        claim_id,
        admission_id,
        insurance_id,
        claim_amount,
        approved_amount,
        claim_status,
        claim_date,
        settle_date,

        -- settlement time in days (NULL for pending = not yet settled)
        CASE 
            WHEN settle_date iS Not NULL
            THEN DATEDIFF(DAY, claim_date, settle_date)
        END AS days_to_settle,

        -- approval ratio (NULL-safe): How much of the claim was approved
        CASE 
            WHEN claim_status = 'Approved' and claim_amount > 0
            THEN ROUND(approved_amount / claim_amount, 4)
        END AS approval_ratio,

        -- Amount the insurer did Not cover 
        CASE 
            WHEN approved_amount IS NOT NULL
            THEN claim_amount - approved_amount
        END AS unapproved_amount,

        -- Fast boolen flags for gold rollups
        CASE
            WHEN claim_status = 'Approved' 
            THEN true ELSE false
        End AS is_approved,

        CASE 
            WHEN claim_status = 'Pending'
            THEN true ELSE false
        END AS is_pending,

    -- ── DATA QUALITY ──
        case
            when approved_amount > claim_amount        then 'APPROVED_EXCEEDS_CLAIM'
            when claim_amount <= 0                     then 'INVALID_CLAIM_AMOUNT'
            when settle_date < claim_date              then 'SETTLE_BEFORE_CLAIM'
            when claim_status = 'Approved'
                 and approved_amount is null           then 'APPROVED_BUT_NO_AMOUNT'
            when claim_status = 'Unknown'              then 'INVALID_STATUS'
            else 'VALID'
        end as dq_status,

        source_system,
        file_name, upload_dttm, load_dttm
    from cleaned
)

select * from final