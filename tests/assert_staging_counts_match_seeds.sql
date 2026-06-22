-- Fails if any staging model has a different row count than its raw seed.

select table_name, seed_count, staging_count
from (
    select 'customers' as table_name,
        (select count(*) from {{ ref('customers') }}) as seed_count,
        (select count(*) from {{ ref('stg_customers') }}) as staging_count

    union all

    select 'invoices',
        (select count(*) from {{ ref('invoices') }}),
        (select count(*) from {{ ref('stg_invoices') }})

    union all

    select 'products',
        (select count(*) from {{ ref('products') }}),
        (select count(*) from {{ ref('stg_products') }})

    union all

    select 'subscriptions',
        (select count(*) from {{ ref('subscriptions') }}),
        (select count(*) from {{ ref('stg_subscriptions') }})

    union all

    select 'schools',
        (select count(*) from {{ ref('schools') }}),
        (select count(*) from {{ ref('stg_schools') }})
)
where seed_count != staging_count