# Payment-Gateway-Operations-Dashboard
End-to-end payment gateway data mart built with Snowflake, Microsoft Fabric, PySpark &amp; Power BI. Ingests 100K+ JSON logs into a Medallion Star Schema with executive SLA analytics.
# Payment Gateway Infrastructure SLA & Authorization Intelligence Data Mart

An end-to-end modern data stack project ingesting raw, semi-structured payment gateway logs into **Snowflake** via a **Medallion Architecture (Bronze → Silver → Gold)**, modeling data into a **Kimball Star Schema**, and delivering executive operational insights via **Power BI**.

---

##  Architecture Overview

```
[ Raw API / JSON Payment Logs ]
               │
               ▼
   ┌───────────────────────┐
   │    SNOWFLAKE STAGE    │  (Internal Stage: JSON_STAGE)
   └───────────┬───────────┘
               │
               ▼
   ┌───────────────────────┐
   │     BRONZE SCHEMA     │  (RAW_GATEWAY_LOGS using VARIANT)
   └───────────┬───────────┘
               │
               ▼  SQL Parsing & Flattening
   ┌───────────────────────┐
   │     SILVER SCHEMA     │  (SILVER_GATEWAY_LOGS Relational Layer)
   └───────────┬───────────┘
               │
               ▼  Dimensional Modeling & Aggregations
   ┌───────────────────────┐
   │      GOLD SCHEMA      │  (FACT_PAYMENT_LOGS, DIM_GATEWAY, DIM_PAYMENT_METHOD)
   └───────────┬───────────┘
               │
               ▼  Import / DirectQuery Connection
   ┌───────────────────────┐
   │   POWER BI DASHBOARD  │  (Executive Visualizations & Custom DAX Logic)
   └───────────────────────┘
```

---

## Key Features & Business Value

- **Semi-Structured Ingestion:** Processed **100,000+ payment log records** stored in Snowflake native `VARIANT` JSON columns.
- **Medallion Data Architecture:** Segregated data into three logical schemas (**Bronze** raw ingestion, **Silver** cleansed/flattened relational data, and **Gold** analytical data mart).
- **Kimball Star Schema Design:** Standardized dimension lookups (`DIM_GATEWAY`, `DIM_PAYMENT_METHOD`) and fact records (`FACT_PAYMENT_LOGS`) yielding sub-second query performance (**~300ms**).
- **Custom DAX KPI Engine:** Dynamic measures calculating **Authorization Success Rate %**, **SLA Breach Counts**, and **Average Response Latency (ms)** across Stripe, PayPal, and Adyen.
- **Root-Cause Failure Analysis:** Visual breakdown of transaction decline reasons (`expired_card`, `suspected_fraud`, `insufficient_funds`, `card_declined`, `gateway_timeout`).

---

## Data Pipeline Details

### 1. Bronze Layer (Raw Ingestion)
- Loaded unstructured JSON payloads into `OLIST_PAYMENTS_DB.BRONZE.RAW_GATEWAY_LOGS` using Snowflake internal stages.

### 2. Silver Layer (Cleansing & Structuring)
- Parsed JSON attributes dynamically:
  ```sql
  CREATE OR REPLACE TABLE OLIST_PAYMENTS_DB.SILVER.SILVER_GATEWAY_LOGS AS
  SELECT 
      raw_payload:order_id::STRING AS order_id,
      raw_payload:gateway_provider::STRING AS gateway_provider,
      raw_payload:payment_method::STRING AS payment_method,
      raw_payload:amount::NUMBER(10,2) AS amount,
      raw_payload:status_code::INT AS status_code,
      raw_payload:is_successful::INT AS is_successful,
      raw_payload:latency_ms::INT AS latency_ms,
      raw_payload:decline_reason::STRING AS decline_reason,
      raw_payload:timestamp::TIMESTAMP AS created_at
  FROM OLIST_PAYMENTS_DB.BRONZE.RAW_GATEWAY_LOGS;
  ```

### 3. Gold Layer (Dimensional Modeling)
- Generated integer surrogate keys via `DENSE_RANK()` for efficient join indexing across `FACT_PAYMENT_LOGS`, `DIM_GATEWAY`, and `DIM_PAYMENT_METHOD`.

---

## Power BI Dashboard & DAX Metrics

### Key Measures
- **Authorization Success Rate %:**
  ```dax
  Authorization_Success_Rate = 
  DIVIDE(
      SUM(FACT_PAYMENT_LOGS[IS_SUCCESSFUL]),
      COUNT(FACT_PAYMENT_LOGS[ORDER_ID]),
      0
  )
  ```
- **SLA Breach Count:**
  ```dax
  SLA Breach Count = 
  CALCULATE(
      COUNT(FACT_PAYMENT_LOGS[ORDER_ID]),
      FILTER(
          FACT_PAYMENT_LOGS,
          FACT_PAYMENT_LOGS[LATENCY_MS] > RELATED(DIM_GATEWAY[TARGET_SLA_LATENCY_MS])
      )
  )
  ```

---

## Tech Stack
- **Database & Data Warehouse:** Snowflake (`ACCOUNTADMIN`, `OLIST_WH`)
- **Languages:** SQL, PySpark, Python, DAX
- **Business Intelligence:** Power BI Desktop
- **Data Modeling:** Kimball Methodology (Star Schema), Medallion Architecture

---

## Author
**Dikshitha Arshanapalli**  
Data Analytics & Engineering | Dublin, Ireland

