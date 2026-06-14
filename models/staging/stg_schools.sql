with source as (
    select * from {{ ref('schools') }}
)

select
    school_id
    , school_name
    , use_case
from source