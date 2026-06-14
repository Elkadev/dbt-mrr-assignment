with source as (
    select * from {{ ref('subscriptions') }}
)

select
    subscription_id
    , subscription_type
    , school_id
    , billing_method
    , status
    , cast(start_date as date) as start_date
    , cast(billed_until_date as date) as billed_until_date
from source