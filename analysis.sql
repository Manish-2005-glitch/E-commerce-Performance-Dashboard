CREATE DATABASE IF NOT EXISTS marketing_analysis;
USE marketing_analysis;

DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS order_payments;
DROP TABLE IF EXISTS order_reviews;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS sellers;
DROP TABLE IF EXISTS geolocation;

CREATE TABLE customers (
    customer_id VARCHAR(100) PRIMARY KEY,
    customer_unique_id VARCHAR(100),
    customer_zip_code_prefix VARCHAR(10),
    customer_city VARCHAR(100),
    customer_state VARCHAR(2)
);

CREATE TABLE orders (
    order_id VARCHAR(100) PRIMARY KEY,
    customer_id VARCHAR(100),
    order_status VARCHAR(50),
    order_purchase_timestamp DATETIME,
    order_approved_at DATETIME,
    order_delivered_carrier_date DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
    order_id VARCHAR(100),
    order_item_id INT,
    product_id VARCHAR(100),
    seller_id VARCHAR(100),
    shipping_limit_date DATETIME,
    price DECIMAL(10,2),
    freight_value DECIMAL(10,2),
    PRIMARY KEY (order_id, order_item_id)
    -- Foreign keys for product_id and seller_id will be added after those tables are created
);

-- =================================================================
-- These tables correspond to the CSVs you uploaded
-- =================================================================

CREATE TABLE products (
    product_id VARCHAR(100) PRIMARY KEY,
    product_category_name VARCHAR(100),
    product_name_lenght INT,
    product_description_lenght INT,
    product_photos_qty INT,
    product_weight_g INT,
    product_length_cm INT,
    product_height_cm INT,
    product_width_cm INT
);

CREATE TABLE sellers (
    seller_id VARCHAR(100) PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(10),
    seller_city VARCHAR(100),
    seller_state VARCHAR(2)
);

CREATE TABLE order_payments (
    order_id VARCHAR(100),
    payment_sequential INT,
    payment_type VARCHAR(50),
    payment_installments INT,
    payment_value DECIMAL(10,2),
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE TABLE order_reviews (
    review_id VARCHAR(100),
    order_id VARCHAR(100),
    review_score INT,
    review_comment_title VARCHAR(255),
    review_comment_message TEXT,
    review_creation_date DATETIME,
    review_answer_timestamp DATETIME,
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE TABLE geolocation (
    geolocation_zip_code_prefix VARCHAR(10),
    geolocation_lat DECIMAL(10, 8),
    geolocation_lng DECIMAL(11, 8),
    geolocation_city VARCHAR(100),
    geolocation_state VARCHAR(2)
);
ALTER TABLE order_items
ADD FOREIGN KEY (product_id) REFERENCES products(product_id),
ADD FOREIGN KEY (seller_id) REFERENCES sellers(seller_id);

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

DROP VIEW IF EXISTS customer_value_analysis;
CREATE VIEW customer_value_analysis AS
SELECT 
    c.customer_id,
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS order_count,
    COALESCE(ROUND(SUM(oi.price + oi.freight_value), 2), 0) AS total_spent,
    MAX(o.order_purchase_timestamp) AS last_purchase_date,
    -- Note: '2018-09-01' is a hardcoded date for analysis. 
    -- In a real project, you might replace this with (SELECT MAX(order_purchase_timestamp) FROM orders).
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

-- ---

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

-- ---

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

DROP VIEW IF EXISTS powerbi_export;
CREATE VIEW powerbi_export AS
SELECT
    c.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    c.customer_zip_code_prefix,
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS delivery_time_days,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    oi.price,
    oi.freight_value,
    (oi.price + oi.freight_value) AS order_item_total,
    p.product_category_name,
    pay.payment_type,
    pay.payment_installments,
    pay.payment_value,
    r.review_score,
    s.seller_city,
    s.seller_state AS seller_state,
    cva.value_segment,
    cva.activity_status,
    cva.days_since_last_purchase
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
LEFT JOIN order_items oi ON o.order_id = oi.order_id
LEFT JOIN products p ON oi.product_id = p.product_id
LEFT JOIN sellers s ON oi.seller_id = s.seller_id
LEFT JOIN order_payments pay ON o.order_id = pay.order_id
LEFT JOIN order_reviews r ON o.order_id = r.order_id
LEFT JOIN customer_value_analysis cva ON c.customer_id = cva.customer_id
WHERE o.order_status = 'delivered'
LIMIT 100000;
select * from powerbi_export;



