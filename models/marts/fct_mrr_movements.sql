-- ============================================================================
-- MRR MOVEMENTS: Tracks how MRR changes month-over-month per customer
-- Categories: new, expansion, contraction, reactivation, retained
-- ============================================================================

with mrr_by_customer as (
    select
        a.month
        , a.customer_id
        , sc.use_case
        , c.country
        , sum(a.mrr_usd) as mrr_usd
    from {{ ref('int_invoice_monthly_amortized') }} as a
    inner join {{ ref('stg_subscriptions') }} as su
        on a.subscription_id = su.subscription_id
    inner join {{ ref('stg_schools') }} as sc
        on su.school_id = sc.school_id
    inner join {{ ref('stg_customers') }} as c
        on a.customer_id = c.customer_id
    group by a.month, a.customer_id, sc.use_case, c.country
)

, mrr_with_previous as (
    select
        *
        , lag(mrr_usd) over (
            partition by customer_id, use_case, country
            order by month
        ) as previous_mrr
        , lag(month) over (
            partition by customer_id, use_case, country
            order by month
        ) as previous_month
    from mrr_by_customer
)

, classified as (
    select
        month
        , customer_id
        , use_case
        , country
        , mrr_usd
        , previous_mrr
        , case
            when previous_mrr is null then 'new'
            when previous_month < month - interval '1 month' then 'reactivation'
            when mrr_usd > previous_mrr then 'expansion'
            when mrr_usd < previous_mrr then 'contraction'
            else 'retained'
        end as mrr_movement
        , mrr_usd - coalesce(previous_mrr, 0) as mrr_change
    from mrr_with_previous
)

select
    month
    , use_case
    , country
    , mrr_movement
    , count(distinct customer_id) as customer_count
    , round(sum(mrr_change), 2) as mrr_change_usd
    , round(sum(mrr_usd), 2) as mrr_usd
from classified
group by month, use_case, country, mrr_movement
order by month, use_case, country, mrr_movement