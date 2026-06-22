-- This test verifies that total amortized MRR equals total invoiced amount.
-- Proves no revenue is lost or created during the amortization process.

with source_total as (
    select sum(amount_usd) as total_invoiced
    from {{ ref('stg_invoices') }}
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
where abs(s.total_invoiced - a.total_amortized) > 0.01