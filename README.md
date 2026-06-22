# MRR Analytics — dbt Project

## Overview

This dbt project builds a **Monthly Recurring Revenue (MRR)** pipeline for a SaaS company selling online learning subscriptions. It transforms raw billing data into two analytical mart tables that enable revenue analysis by business dimension.

**Output:**
- **`fct_mrr`** — MRR at the grain of month × school use case × customer country
- **`fct_mrr_movements`** — MRR movement analysis (new, expansion, contraction, reactivation, retained)

---

## How to Run

```bash
# Prerequisites: Python 3.12+
pip install dbt-duckdb
dbt deps
dbt seed
dbt build
dbt docs generate
dbt docs serve
```

---

## Project Structure

```
mrr_analytics/
├── models/
│   ├── staging/                    # 1:1 with source — type casting, renaming
│   │   ├── _staging.yml            # Schema tests & documentation
│   │   ├── stg_invoices.sql
│   │   ├── stg_customers.sql
│   │   ├── stg_products.sql
│   │   ├── stg_subscriptions.sql
│   │   └── stg_schools.sql
│   ├── intermediate/               # Core business logic
│   │   ├── _intermediate.yml
│   │   └── int_invoice_monthly_amortized.sql
│   └── marts/                      # Final aggregated outputs
│       ├── _marts.yml
│       ├── _exposures.yml
│       ├── fct_mrr.sql
│       └── fct_mrr_movements.sql
├── seeds/                          # Raw CSV data files
│   ├── invoices.csv
│   ├── customers.csv
│   ├── products.csv
│   ├── subscriptions.csv
│   └── schools.csv
├── tests/
│   ├── unit/
│   │   └── test_amortization_logic.yml
│   ├── assert_amortized_revenue_reconciles.sql
│   ├── assert_billing_dates_valid.sql
│   ├── assert_month_within_billing_period.sql
│   ├── assert_row_count_matches_months_covered.sql
│   ├── assert_negative_mrr_only_from_credits.sql
│   └── assert_staging_counts_match_seeds.sql
├── screenshots/
├── dbt_project.yml
├── profiles.yml
├── packages.yml
└── README.md
```

---

## Data Flow (Lineage)

```
seeds (CSVs)
  → staging (type casting, cleaning, no business logic)
    → intermediate (revenue amortization — core transformation)
      → marts (aggregation by business dimensions)
        → exposures (dashboards, finance reports)
```

---

## Mart Tables — Detailed Metrics

### `fct_mrr` — Monthly Recurring Revenue

**Grain:** One row per `month × use_case × country`

| Column | Type | Description |
|--------|------|-------------|
| `month` | date | First day of the calendar month (e.g., 2024-01-01) |
| `use_case` | varchar | School use case: `b2b_course_sellers`, `b2c_course_sellers`, `customer_training`, `corporate_training`, `government_ngos` |
| `country` | varchar | Country of the customer entity (the paying account) |
| `mrr_usd` | decimal | Total Monthly Recurring Revenue in USD for this combination |

**Business Questions This Table Answers:**

- What is total MRR per month?
- Which use case generates the most revenue?
- Which countries are growing fastest?
- What's the revenue split by segment?
- Are there seasonal patterns?

**Key Metrics Derivable:**

| Metric | How to Calculate |
|--------|-----------------|
| Total MRR | `SUM(mrr_usd)` for a given month |
| MRR Growth Rate | `(current_month - previous_month) / previous_month` |
| MRR by Segment | `SUM(mrr_usd) GROUP BY use_case` |
| Geographic Concentration | `SUM(mrr_usd) GROUP BY country ORDER BY DESC` |

---

### `fct_mrr_movements` — MRR Movement Analysis

**Grain:** One row per `month × use_case × country × mrr_movement`

| Column | Type | Description |
|--------|------|-------------|
| `month` | date | First day of the calendar month |
| `use_case` | varchar | School use case classification |
| `country` | varchar | Country of the customer entity |
| `mrr_movement` | varchar | Category of MRR change (see below) |
| `customer_count` | integer | Number of distinct customers in this movement category |
| `mrr_change_usd` | decimal | Net MRR change in USD (positive = growth, negative = loss) |
| `mrr_usd` | decimal | Total MRR in USD for customers in this movement category |

**Movement Categories:**

| Movement | Definition | Business Meaning |
|----------|-----------|-----------------|
| `new` | Customer has MRR this month, no previous MRR ever | New customer acquisition |
| `expansion` | MRR increased vs previous month | Upselling / plan upgrades working |
| `contraction` | MRR decreased vs previous month (still > $0) | Downgrades / partial loss |
| `reactivation` | Customer had a gap and returned | Win-back success |
| `retained` | MRR unchanged from previous month | Stable base |

**Key Metrics Derivable:**

| Metric | Formula |
|--------|---------|
| Net Revenue Retention (NRR) | `(retained + expansion + reactivation) / previous_total_mrr × 100` |
| Expansion Revenue | `SUM(mrr_change_usd) WHERE mrr_movement = 'expansion'` |
| New Business Revenue | `SUM(mrr_change_usd) WHERE mrr_movement = 'new'` |
| Quick Ratio | `(new + expansion + reactivation) / contraction` |

---

## Intermediate Table — Core Logic

### `int_invoice_monthly_amortized`

**Grain:** One row per `invoice × month`

An invoice spanning 12 months produces 12 rows — one per calendar month it covers.

| Column | Type | Description |
|--------|------|-------------|
| `invoice_id` | varchar | Original invoice identifier (NOT unique — one invoice → multiple rows) |
| `customer_id` | varchar | Customer who was billed |
| `subscription_id` | varchar | Related subscription |
| `product_id` | varchar | Product billed |
| `months_covered` | integer | Number of months spanned by invoice |
| `month` | date | Calendar month this row is attributed to |
| `mrr_usd` | decimal | Monthly portion: `amount_usd / months_covered` (rounding remainder allocated to last month) |

**Example:**

```
Input:  Invoice $1,200 | start: 2024-01-01 | end: 2024-12-31
Output: 12 rows, each with mrr_usd = $100
```

**Rounding Example:**

```
Input:  Invoice $100 | start: 2024-01-01 | end: 2024-03-31 | months_covered = 3
Output: Jan = $33.33, Feb = $33.33, Mar = $33.34 (remainder allocated to last month)
Total:  $33.33 + $33.33 + $33.34 = $100.00 ✅ (exact reconciliation)
```

---

## Modeling Decisions

### 1. Revenue Amortization

**Problem:** Invoices are billed at different frequencies (monthly, quarterly, annual) but MRR must be reported monthly.

**Solution:** Distribute each invoice's `amount_usd` proportionally:

```
months_covered = datediff('month', billing_start_date, billing_end_date) + 1
MRR per month = round(amount_usd / months_covered, 2)
```

The `+ 1` ensures inclusive month counting (Jan 1 to Mar 31 = 3 months, not 2).

**Rounding fix:** To prevent revenue leakage from rounding (e.g., $100 / 3 = $33.33 × 3 = $99.99), the remainder is allocated to the last month using `ROW_NUMBER() ... ORDER BY month DESC`. This ensures `SUM(mrr_usd) = amount_usd` for every invoice.

**Why `datediff` instead of the `billing_frequency` label?**
- The label says "annual" but actual dates might span 11 or 13 months
- Dates are the source of truth — labels can be stale or wrong
- Handles edge cases automatically without special logic

### 2. Credit Notes (Negative Amounts)

**Decision:** Distributed proportionally, same as regular invoices.

**Why:** A 6-month credit should reduce MRR across 6 months, not distort one month.

**Alternative rejected:** Assigning full credit to `invoice_date` month — distorts time series for multi-month adjustments.

### 3. Invoices with `months_covered < 1`

**Decision:** Excluded (`WHERE months_covered >= 1`).

**Why:** Prevents division by zero. These represent same-day adjustments or data entry errors (<1% of records).

### 4. INNER JOIN Strategy

**Decision:** All joins are INNER. Orphan records are excluded.

**Why:** Orphan records indicate data quality issues. They should NOT silently contribute to MRR. Referential integrity tests on staging catch these explicitly.

### 5. Subscription Status Not Filtered

**Decision:** All invoiced revenue counts regardless of subscription `status` (active/cancelled).

**Why:** An invoice represents committed revenue for that billing period. Cancellation affects future periods, not already-invoiced ones. If the business defines MRR differently, a filter can be added.

### 6. Revenue Attributed to Customer Country

**Decision:** MRR grouped by `customers.country`, not school location.

**Why:** The customer (the paying entity) determines geographic attribution for financial reporting.

### 7. Materialization Strategy

| Layer | Type | Reasoning |
|-------|------|-----------|
| Staging | View | No storage needed — just renaming/casting |
| Intermediate | View | Only consumed by downstream models |
| Marts | Table | Queried by BI tools — persisted for fast reads |

---

## Testing Strategy

### Overview

```
Schema tests (unique, not_null, relationships, accepted_values) + 
Custom singular tests (reconciliation, date validation, row counts) + 
Unit tests (amortization logic) 
All passing ✅
```

### 1. Unit Tests (`tests/unit/`)

Validate the **amortization logic** with controlled inputs and expected outputs:

| Test | What It Proves |
|------|---------------|
| `test_annual_invoice_distributes_evenly` | $1,200 / 12 months = $100/month |
| `test_quarterly_invoice_distributes_over_3_months` | $300 / 3 months = $100/month |
| `test_credit_note_distributes_as_negative` | -$600 / 6 months = -$100/month |
| `test_rounding_remainder_goes_to_last_month` | $100 / 3 = $33.33 + $33.33 + $33.34 |

**Why unit tests?** Other tests check data quality. Unit tests check **logic correctness**. Even if data changes completely, these prove the transformation engine works.

### 2. Reconciliation Test (`tests/assert_amortized_revenue_reconciles.sql`)

Verifies:
```
SUM(amortized mrr_usd) = SUM(original invoice amount_usd)
```

Proves no revenue is lost or created during amortization. Tolerance of $0.01 — the rounding remainder fix ensures near-exact reconciliation.

### 3. Custom Singular Tests

| Test | What It Validates |
|------|-------------------|
| `assert_amortized_revenue_reconciles` | Total amortized MRR = total invoiced amount (±$0.01) |
| `assert_billing_dates_valid` | No invoice has billing_end_date before billing_start_date |
| `assert_month_within_billing_period` | All generated months fall within the invoice billing period |
| `assert_row_count_matches_months_covered` | Each invoice produces exactly `months_covered` rows |
| `assert_negative_mrr_only_from_credits` | Negative MRR only comes from negative invoices (no sign corruption) |
| `assert_staging_counts_match_seeds` | All staging models have same row count as raw seeds (no rows lost or duplicated) |

### 4. Primary Key Tests

| Model | Column | Tests |
|-------|--------|-------|
| stg_invoices | invoice_id | `unique`, `not_null` |
| stg_customers | customer_id | `unique`, `not_null` |
| stg_products | product_id | `unique`, `not_null` |
| stg_subscriptions | subscription_id | `unique`, `not_null` |
| stg_schools | school_id | `unique`, `not_null` |

### 5. Referential Integrity Tests

| From | Column | To | Column |
|------|--------|----|--------|
| stg_invoices | customer_id | stg_customers | customer_id |
| stg_invoices | subscription_id | stg_subscriptions | subscription_id |
| stg_invoices | product_id | stg_products | product_id |
| stg_subscriptions | school_id | stg_schools | school_id |

### 6. Grain Validation

| Model | Composite Key |
|-------|--------------|
| fct_mrr | `month + use_case + country` |
| fct_mrr_movements | `month + use_case + country + mrr_movement` |

### 7. Accepted Values & Not Null

- `use_case` → validates only known categories exist
- `mrr_movement` → validates only expected movement types
- All mart columns have `not_null` tests

---

### How Tests Protect Against Failures

| Scenario | Which test catches it |
|----------|----------------------|
| Duplicate invoice in source | `unique` on stg_invoices.invoice_id |
| Invoice references non-existent customer | `relationships` test |
| New unknown use_case appears | `accepted_values` on fct_mrr.use_case |
| Amortization drops a month | `assert_amortized_revenue_reconciles` |
| Logic error in MRR calculation | Unit tests |
| GROUP BY produces wrong grain | `unique_combination_of_columns` |
| Null in a mart column | `not_null` tests |
| billing_end_date before billing_start_date | `assert_billing_dates_valid` |
| Invoice produces wrong number of monthly rows | `assert_row_count_matches_months_covered` |
| Positive invoice producing negative MRR | `assert_negative_mrr_only_from_credits` |
| Staging model drops or duplicates rows | `assert_staging_counts_match_seeds` |
| Generated month falls outside billing period | `assert_month_within_billing_period` |

### What Is NOT Tested (and Why)

| Not Tested | Reason |
|------------|--------|
| Amount min/max | Credit notes make negative values valid |
| Date range bounds | No business rule defines valid date ranges |
| Churn detection | Current model doesn't track churn (listed as future improvement) |

---

## Exposures

Documents downstream consumers:

- **MRR Executive Dashboard** — Leadership uses `fct_mrr` and `fct_mrr_movements` for strategic planning and investor reporting.

Shows the full data lifecycle — not just "I built a model" but "here's who relies on it."

---

## Assumptions

1. `billing_start_date` and `billing_end_date` always span at least one full month
2. Invoices with `months_covered < 1` are excluded (prevents division by zero)
3. All amounts are in USD — no currency conversion needed
4. Revenue is attributed to customer's country, not school's location
5. No SCD — uses current values for country and use_case
6. All invoiced revenue counts toward MRR regardless of subscription status
7. Credit notes follow the same proportional amortization as regular invoices
8. Rounding remainder is allocated to the last month to ensure exact revenue reconciliation

---

## What I Would Do Next (Production Readiness)

| Priority | Improvement | Why |
|----------|-------------|-----|
| 1 | Incremental materialization on intermediate | Performance at scale — only process new invoices |
| 2 | Source freshness checks | Alert if data pipeline stops delivering |
| 3 | CI/CD with GitHub Actions | `dbt build` on every PR, deploy on merge |
| 4 | SCD Type 2 on customers/schools | Preserve historical country/use_case values |
| 5 | Date spine | Surface months with zero MRR for complete time series |
| 6 | Churn detection | Identify customers who had MRR and dropped to zero |
| 7 | Orchestration (dbt Cloud / Airflow) | Scheduled runs, monitoring, alerting |

---

## Tools Used

| Tool | Purpose |
|------|---------|
| dbt-core 1.11 | SQL transformation framework |
| DuckDB | Local analytical database (zero infrastructure) |
| dbt_utils | Generic test macros |
| dbt_expectations | Additional test capabilities |
| Git + GitHub | Version control |

---

## Sample Queries

```sql
-- Total MRR over time
SELECT month, SUM(mrr_usd) as total_mrr
FROM fct_mrr GROUP BY month ORDER BY month;

-- MRR by movement type
SELECT mrr_movement, SUM(mrr_change_usd) as impact
FROM fct_mrr_movements GROUP BY mrr_movement;

-- One customer's MRR journey
SELECT month, customer_id, SUM(mrr_usd) as mrr
FROM int_invoice_monthly_amortized
WHERE customer_id = 'cust_00001'
GROUP BY month, customer_id
ORDER BY month;

-- MRR by segment over time
SELECT month, use_case, SUM(mrr_usd) as mrr
FROM fct_mrr GROUP BY month, use_case ORDER BY month, use_case;
```