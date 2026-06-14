with source as (
    select * from {{ ref('customers') }}
)

select
    customer_id
    , company_name
    , country
    , default_billing_method
from source