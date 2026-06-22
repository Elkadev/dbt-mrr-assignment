-- Fails if any amortized month falls outside the invoice's billing period.

select
    invoice_id
    , month
    , billing_start_date
    , billing_end_date
from {{ ref('int_invoice_monthly_amortized') }}
where month < date_trunc('month', billing_start_date)
   or month > date_trunc('month', billing_end_date)