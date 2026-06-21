with invoices as (
    select * from {{ ref('stg_invoices') }}
)

, products as (
    select * from {{ ref('stg_products') }}
)

, invoices_enriched as (
    select
        i.invoice_id
        , i.customer_id
        , i.subscription_id
        , i.product_id
        , i.invoice_date
        , i.billing_start_date
        , i.billing_end_date
        , i.amount_usd
        , p.billing_frequency
        , datediff('month', i.billing_start_date, i.billing_end_date) + 1 as months_covered
    from invoices as i
    inner join products as p
        on i.product_id = p.product_id
)

, amortized as (
    select
        invoice_id
        , customer_id
        , subscription_id
        , product_id
        , invoice_date
        , billing_start_date
        , billing_end_date
        , amount_usd
        , billing_frequency
        , months_covered
        , unnest(
            generate_series(
                cast(date_trunc('month', billing_start_date) as date)
                , cast(date_trunc('month', billing_end_date) as date)
                , interval '1 month'
            )
        )::date as month
        , round(amount_usd / months_covered, 2) as mrr_usd_base
    from invoices_enriched
    where months_covered >= 1
)

, with_remainder as (
    select
        *
        , row_number() over (partition by invoice_id order by month desc) as rn
        , amount_usd - (round(amount_usd / months_covered, 2) * months_covered) as remainder
    from amortized
)

select
    invoice_id
    , customer_id
    , subscription_id
    , product_id
    , invoice_date
    , billing_start_date
    , billing_end_date
    , amount_usd
    , billing_frequency
    , months_covered
    , month
    , case
        when rn = 1 then mrr_usd_base + remainder
        else mrr_usd_base
      end as mrr_usd
from with_remainder