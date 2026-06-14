with source as (
    select * from {{ ref('products') }}
)

select
    product_id
    , product_name
    , billing_frequency
from source