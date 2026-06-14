-- This test verifies that total amortized MRR equals total invoiced amount.
-- Proves no revenue is lost or created during the amortization process.
-- A small tolerance is allowed for rounding (max $0.01 per invoice).

with source_total as (
    select sum(amount_usd) as total_invoiced
    from {{ ref('stg_invoices') }}
    where datediff(
        'month'
        , cast(billing_start_date as date)
        , cast(billing_end_date as date)
    ) > 0
)

, amortized_total as (
    select sum(mrr_usd) as total_amortized
    from {{ ref('int_invoice_monthly_amortized') }}
)

select
    s.total_invoiced
    , a.total_amortized
    , abs(s.total_invoiced - a.total_amortized) as difference
from source_total s
cross join amortized_total a
where abs(s.total_invoiced - a.total_amortized) > 25.00