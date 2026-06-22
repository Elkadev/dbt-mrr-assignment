-- Fails if an invoice has more or fewer rows than expected.

select
    invoice_id
    , months_covered
    , count(*) as actual_rows
from {{ ref('int_invoice_monthly_amortized') }}
group by invoice_id, months_covered
having count(*) != months_covered