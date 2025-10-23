CREATE DATABASE marketing_analysis;
USE marketing_analysis;

DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id VARCHAR(100),
    customer_unique_id VARCHAR(100),
    customer_zip_code_prefix VARCHAR(10),
    customer_city VARCHAR(100),
    customer_state VARCHAR(2)
);

CREATE TABLE orders (
    order_id VARCHAR(100),
    customer_id VARCHAR(100),
    order_status VARCHAR(50),
    order_purchase_timestamp DATETIME,
    order_approved_at DATETIME,
    order_delivered_carrier_date DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME
);

CREATE TABLE order_items (
    order_id VARCHAR(100),
    order_item_id INT,
    product_id VARCHAR(100),
    seller_id VARCHAR(100),
    shipping_limit_date DATETIME,
    price DECIMAL(10,2),
    freight_value DECIMAL(10,2)
);

SELECT COUNT(*) AS customers_count FROM customers;
SELECT COUNT(*) AS orders_count FROM orders;
SELECT COUNT(*) AS order_items_count FROM order_items;

SELECT * FROM customers LIMIT 5;
SELECT * FROM orders LIMIT 5;
SELECT * FROM order_items LIMIT 5;

DROP VIEW IF EXISTS business_metrics;
CREATE VIEW business_metrics AS
SELECT 
    (SELECT COUNT(*) FROM customers) AS total_customers,
    (SELECT COUNT(*) FROM orders WHERE order_status = 'delivered') AS total_orders,
    (SELECT ROUND(SUM(price + freight_value), 2) FROM order_items) AS total_revenue,
    (SELECT ROUND(SUM(price + freight_value) / COUNT(DISTINCT order_id), 2) 
     FROM order_items) AS avg_order_value,
    (SELECT ROUND(COUNT(DISTINCT customer_id) * 100.0 / (SELECT COUNT(*) FROM customers), 2)
     FROM orders WHERE order_status = 'delivered') AS conversion_rate;
     
select * from business_metrics;

DROP VIEW IF EXISTS customer_value_analysis;
CREATE VIEW customer_value_analysis AS
SELECT 
    c.customer_id,
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS order_count,
    COALESCE(ROUND(SUM(oi.price + oi.freight_value), 2), 0) AS total_spent,
    MAX(o.order_purchase_timestamp) AS last_purchase_date,
    COALESCE(DATEDIFF('2018-09-01', MAX(o.order_purchase_timestamp)), 365) AS days_since_last_purchase,
    CASE 
        WHEN COALESCE(SUM(oi.price + oi.freight_value), 0) >= 500 THEN 'High Value'
        WHEN COALESCE(SUM(oi.price + oi.freight_value), 0) >= 200 THEN 'Medium Value' 
        ELSE 'Low Value'
    END AS value_segment,
    CASE 
        WHEN COALESCE(DATEDIFF('2018-09-01', MAX(o.order_purchase_timestamp)), 365) <= 60 THEN 'Active'
        WHEN COALESCE(DATEDIFF('2018-09-01', MAX(o.order_purchase_timestamp)), 365) <= 120 THEN 'At Risk'
        ELSE 'Inactive'
    END AS activity_status
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.order_status = 'delivered'
LEFT JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY c.customer_id, c.customer_state;

select * from customer_value_analysis;

DROP VIEW IF EXISTS marketing_recommendations;
CREATE VIEW marketing_recommendations AS
SELECT 
    CONCAT(value_segment, ' - ', activity_status) AS customer_tier,
    COUNT(*) AS customer_count,
    ROUND(AVG(total_spent), 2) AS avg_customer_value,
    ROUND(SUM(total_spent), 2) AS total_segment_value,
    CASE 
        WHEN CONCAT(value_segment, ' - ', activity_status) = 'High Value - Active' THEN 40
        WHEN CONCAT(value_segment, ' - ', activity_status) = 'High Value - At Risk' THEN 30
        WHEN CONCAT(value_segment, ' - ', activity_status) = 'Medium Value - Active' THEN 20
        WHEN CONCAT(value_segment, ' - ', activity_status) = 'Medium Value - At Risk' THEN 8
        ELSE 2
    END AS recommended_budget_percent
FROM customer_value_analysis
GROUP BY value_segment, activity_status
ORDER BY recommended_budget_percent DESC;

select * from marketing_recommendations;

DROP VIEW IF EXISTS regional_analysis;
CREATE VIEW regional_analysis AS
SELECT 
    c.customer_state,
    COUNT(DISTINCT c.customer_id) AS total_customers,
    COALESCE(ROUND(SUM(oi.price + oi.freight_value), 2), 0) AS total_revenue,
    COALESCE(ROUND(AVG(oi.price + oi.freight_value), 2), 0) AS avg_order_value,
    COUNT(DISTINCT o.order_id) AS total_orders,
    CASE 
        WHEN COALESCE(SUM(oi.price + oi.freight_value), 0) > 50000 THEN 'Tier 1 - High Priority'
        WHEN COALESCE(SUM(oi.price + oi.freight_value), 0) > 20000 THEN 'Tier 2 - Medium Priority'
        ELSE 'Tier 3 - Low Priority'
    END AS marketing_priority
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.order_status = 'delivered'
LEFT JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY c.customer_state
ORDER BY total_revenue DESC;

select * from regional_analysis;

SELECT 
    'Total Customers' AS metric, 
    total_customers AS value 
FROM business_metrics
UNION ALL
SELECT 'Total Orders', total_orders FROM business_metrics
UNION ALL
SELECT 'Total Revenue', total_revenue FROM business_metrics
UNION ALL
SELECT 'Average Order Value', avg_order_value FROM business_metrics;

SELECT 
    customer_tier,
    customer_count,
    recommended_budget_percent AS budget_percentage,
    ROUND(total_segment_value * recommended_budget_percent / 100, 2) AS suggested_budget
FROM marketing_recommendations;

DROP VIEW IF EXISTS powerbi_export;
CREATE VIEW powerbi_export AS
SELECT 
    c.customer_id,
    c.customer_state,
    c.customer_city,
    cva.value_segment,
    cva.activity_status,
    cva.total_spent,
    cva.days_since_last_purchase,
    o.order_purchase_timestamp,
    oi.price,
    oi.freight_value,
    (oi.price + oi.freight_value) AS order_total
FROM customers c
LEFT JOIN customer_value_analysis cva ON c.customer_id = cva.customer_id
LEFT JOIN orders o ON c.customer_id = o.customer_id
LEFT JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
LIMIT 50000;

