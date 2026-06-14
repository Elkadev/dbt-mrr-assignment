with source as (
    select * from {{ ref('invoices') }}
)

select
    invoice_id
    , customer_id
    , subscription_id
    , product_id
    , cast(invoice_date as date) as invoice_date
    , cast(billing_start_date as date) as billing_start_date
    , cast(billing_end_date as date) as billing_end_date
    , cast(amount_usd as decimal(18, 2)) as amount_usd
from source