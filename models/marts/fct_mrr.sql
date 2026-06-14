with amortized_invoices as (
    select * from {{ ref('int_invoice_monthly_amortized') }}
)

, subscriptions as (
    select * from {{ ref('stg_subscriptions') }}
)

, schools as (
    select * from {{ ref('stg_schools') }}
)

, customers as (
    select * from {{ ref('stg_customers') }}
)

, enriched as (
    select
        a.month
        , sc.use_case
        , c.country
        , a.mrr_usd
    from amortized_invoices as a
    inner join subscriptions as su
        on a.subscription_id = su.subscription_id
    inner join schools as sc
        on su.school_id = sc.school_id
    inner join customers as c
        on a.customer_id = c.customer_id
)

select
    month
    , use_case
    , country
    , round(sum(mrr_usd), 2) as mrr_usd
from enriched
group by month, use_case, country
order by month, use_case, country