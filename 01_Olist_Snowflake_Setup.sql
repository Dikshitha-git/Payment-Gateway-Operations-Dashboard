-- 1. Create compute warehouse (virtual server)
CREATE WAREHOUSE IF NOT EXISTS OLIST_WH
    WITH WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

-- 2. Create database and medallion schemas
CREATE DATABASE IF NOT EXISTS OLIST_PAYMENTS_DB;

USE DATABASE OLIST_PAYMENTS_DB;

CREATE SCHEMA IF NOT EXISTS BRONZE;
CREATE SCHEMA IF NOT EXISTS SILVER;
CREATE SCHEMA IF NOT EXISTS GOLD;

-- 3. Set context
USE WAREHOUSE OLIST_WH;
USE SCHEMA BRONZE;

USE SCHEMA OLIST_PAYMENTS_DB.BRONZE;

-- 1. Table for raw JSON logs using Snowflake's native VARIANT type
CREATE OR REPLACE TABLE raw_gateway_logs (
    raw_payload VARIANT
);OLIST_PAYMENTS_DB.BRONZE.RAW_GATEWAY_LOGS
-- 2. Internal stage to hold raw JSON fileOLIST_PAYMENTS_DB.INFORMATION_SCHEMA.TABLES
CREATE OR REPLACE STAGE json_stage;

CREATE SCHEMA IF NOT EXISTS OLIST_PAYMENTS_DB.BRONZE;
USE SCHEMA OLIST_PAYMENTS_DB.BRONZE;

-- Create internal stage explicitly in BRONZE
CREATE OR REPLACE STAGE OLIST_PAYMENTS_DB.BRONZE.JSON_STAGE;

-- Create table to hold raw JSON VARIANT data
CREATE OR REPLACE TABLE OLIST_PAYMENTS_DB.BRONZE.RAW_GATEWAY_LOGS (
    raw_payload VARIANT
);

USE SCHEMA OLIST_PAYMENTS_DB.BRONZE;
COPY INTO OLIST_PAYMENTS_DB.BRONZE.RAW_GATEWAY_LOGS
FROM @OLIST_PAYMENTS_DB.BRONZE.JSON_STAGE
FILE_FORMAT = (TYPE = 'JSON');
-- Verify row count
SELECT COUNT(*) AS total_records FROM OLIST_PAYMENTS_DB.BRONZE.RAW_GATEWAY_LOGS;

-- 1. Explicitly create Silver and Gold schemas
CREATE SCHEMA IF NOT EXISTS OLIST_PAYMENTS_DB.SILVER;
CREATE SCHEMA IF NOT EXISTS OLIST_PAYMENTS_DB.GOLD;

-- 1. Create Silver Gateway Logs Table
CREATE OR REPLACE TABLE OLIST_PAYMENTS_DB.SILVER.SILVER_GATEWAY_LOGS AS
SELECT 
    raw_payload:transaction_id::STRING AS transaction_id,
    raw_payload:order_id::STRING AS order_id,
    raw_payload:gateway_provider::STRING AS gateway_provider,
    raw_payload:payment_method::STRING AS payment_method,
    raw_payload:amount::NUMBER(10,2) AS amount,
    raw_payload:installments::INT AS installments,
    raw_payload:response.status_code::INT AS status_code,
    raw_payload:response.latency_ms::INT AS latency_ms,
    raw_payload:response.decline_reason::STRING AS decline_reason,
    raw_payload:response.is_flagged_fraud::BOOLEAN AS is_flagged_fraud,
    raw_payload:created_at::TIMESTAMP_NTZ AS created_at
FROM OLIST_PAYMENTS_DB.BRONZE.RAW_GATEWAY_LOGS;

-- 2. Verify Parsed Table
SELECT * FROM OLIST_PAYMENTS_DB.SILVER.SILVER_GATEWAY_LOGS LIMIT 10;


-- 3. Build Gold Star Schema Dimensions & Fact Table
USE SCHEMA OLIST_PAYMENTS_DB.GOLD;

CREATE OR REPLACE TABLE DIM_GATEWAY AS
SELECT 
    DENSE_RANK() OVER (ORDER BY gateway_provider) AS gateway_key,
    gateway_provider,
    CASE 
        WHEN gateway_provider = 'Stripe' THEN 350
        WHEN gateway_provider = 'PayPal' THEN 400
        ELSE 450
    END AS target_sla_latency_ms
FROM (SELECT DISTINCT gateway_provider FROM OLIST_PAYMENTS_DB.SILVER.SILVER_GATEWAY_LOGS);

CREATE OR REPLACE TABLE DIM_PAYMENT_METHOD AS
SELECT 
    DENSE_RANK() OVER (ORDER BY payment_method) AS payment_method_key,
    payment_method,
    CASE 
        WHEN payment_method = 'credit_card' THEN TRUE 
        ELSE FALSE 
    END AS supports_installments
FROM (SELECT DISTINCT payment_method FROM OLIST_PAYMENTS_DB.SILVER.SILVER_GATEWAY_LOGS);

CREATE OR REPLACE TABLE FACT_PAYMENT_LOGS AS
SELECT 
    l.transaction_id,
    l.order_id,
    g.gateway_key,
    m.payment_method_key,
    TO_NUMBER(TO_CHAR(l.created_at, 'YYYYMMDD')) AS date_key,
    l.amount,
    l.installments,
    l.status_code,
    l.latency_ms,
    l.decline_reason,
    l.is_flagged_fraud,
    IFF(l.status_code = 200, 1, 0) AS is_successful
FROM OLIST_PAYMENTS_DB.SILVER.SILVER_GATEWAY_LOGS l
JOIN DIM_GATEWAY g ON l.gateway_provider = g.gateway_provider
JOIN DIM_PAYMENT_METHOD m ON l.payment_method = m.payment_method;

-- 4. Final verification
SELECT COUNT(*) AS fact_rows FROM FACT_PAYMENT_LOGS;

SELECT 
    g.gateway_provider,
    g.target_sla_latency_ms,
    COUNT(f.transaction_id) AS total_transactions,
    ROUND(AVG(f.latency_ms), 2) AS avg_latency_ms,
    ROUND(SUM(f.is_successful) * 100.0 / COUNT(f.transaction_id), 2) AS success_rate_pct,
    SUM(CASE WHEN f.latency_ms > g.target_sla_latency_ms THEN 1 ELSE 0 END) AS sla_breaches
FROM OLIST_PAYMENTS_DB.GOLD.FACT_PAYMENT_LOGS f
JOIN OLIST_PAYMENTS_DB.GOLD.DIM_GATEWAY g 
    ON f.gateway_key = g.gateway_key
GROUP BY g.gateway_provider, g.target_sla_latency_ms
ORDER BY total_transactions DESC;





























