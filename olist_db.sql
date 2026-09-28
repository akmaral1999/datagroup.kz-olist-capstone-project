-- 1. Справочник клиентов
CREATE TABLE olist_customers (
    customer_id VARCHAR(32) PRIMARY KEY,
    customer_unique_id VARCHAR(32) NOT NULL,
    customer_zip_code_prefix VARCHAR(10),
    customer_city VARCHAR(100),
    customer_state VARCHAR(5)
);

-- 2. Справочник продавцов
CREATE TABLE olist_sellers (
    seller_id VARCHAR(32) PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(10),
    seller_city VARCHAR(100),
    seller_state VARCHAR(5)
);

-- 3. Справочник переводов категорий товаров
CREATE TABLE product_category_name_translation (
    product_category_name VARCHAR(100) PRIMARY KEY,
    product_category_name_english VARCHAR(100)
);

-- 4. Справочник товаров
CREATE TABLE olist_products (
    product_id VARCHAR(32) PRIMARY KEY,
    product_category_name VARCHAR(100),
    product_name_lenght INT,
    product_description_lenght INT,
    product_photos_qty INT,
    product_weight_g NUMERIC(10,2),
    product_length_cm NUMERIC(10,2),
    product_height_cm NUMERIC(10,2),
    product_width_cm NUMERIC(10,2)
);

-- 5. Основная таблица заказов
CREATE TABLE olist_orders (
    order_id VARCHAR(32) PRIMARY KEY,
    customer_id VARCHAR(32) REFERENCES olist_customers(customer_id),
    order_status VARCHAR(20),
    order_purchase_timestamp TIMESTAMP,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);

-- 6. Товарные позиции заказов (составной первичный ключ)
CREATE TABLE olist_order_items (
    order_id VARCHAR(32) REFERENCES olist_orders(order_id),
    order_item_id INT,
    product_id VARCHAR(32) REFERENCES olist_products(product_id),
    seller_id VARCHAR(32) REFERENCES olist_sellers(seller_id),
    shipping_limit_date TIMESTAMP,
    price NUMERIC(10,2),
    freight_value NUMERIC(10,2),
    PRIMARY KEY (order_id, order_item_id)
);

-- 7. Платежи по заказам
CREATE TABLE olist_order_payments (
    order_id VARCHAR(32) REFERENCES olist_orders(order_id),
    payment_sequential INT,
    payment_type VARCHAR(20),
    payment_installments INT,
    payment_value NUMERIC(10,2)
);

-- 8. Отзывы и оценки клиентов
CREATE TABLE olist_order_reviews (
    review_id VARCHAR(64),
    order_id VARCHAR(32) REFERENCES olist_orders(order_id),
    review_score INT,
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date TIMESTAMP,
    review_answer_timestamp TIMESTAMP
);

-- 9. Геолокация
CREATE TABLE olist_geolocation (
    geolocation_zip_code_prefix VARCHAR(10),
    geolocation_lat NUMERIC(10,8),
    geolocation_lng NUMERIC(10,8),
    geolocation_city VARCHAR(100),
    geolocation_state VARCHAR(5)
);
---------------------------------------------------------------------
-- 1. Увеличим длину поля, чтобы избежать ошибок с типом данных
ALTER TABLE olist_customers 
ALTER COLUMN customer_zip_code_prefix TYPE VARCHAR(20);
-- 2. Обновить вид колонок.
ALTER TABLE olist_geolocation 
ALTER COLUMN geolocation_lat TYPE DOUBLE PRECISION;

ALTER TABLE olist_geolocation 
ALTER COLUMN geolocation_lng TYPE DOUBLE PRECISION; 
------------------------------------------------------------
-- Создаем новую таблицу из 9 данных 
CREATE TABLE olist_analytical_dataset AS
WITH order_items_agg AS (
    SELECT 
        oi.order_id,
        COUNT(oi.order_item_id) AS total_items,
        SUM(oi.price) AS total_products_price,
        SUM(oi.freight_value) AS total_freight_value,
        AVG(oi.price) AS avg_item_price,
        AVG(p.product_weight_g) AS avg_product_weight_g,
        AVG(p.product_photos_qty) AS avg_product_photos_qty,
        MAX(s.seller_state) AS seller_state,
        MAX(p.product_category_name) AS main_product_category
    FROM olist_order_items oi
    LEFT JOIN olist_products p ON oi.product_id = p.product_id
    LEFT JOIN olist_sellers s ON oi.seller_id = s.seller_id
    GROUP BY oi.order_id
),
order_payments_agg AS (
    SELECT 
        payment.order_id,
        MAX(payment.payment_type) AS primary_payment_type,
        MAX(payment.payment_installments) AS max_installments,
        SUM(payment.payment_value) AS total_payment_value
    FROM olist_order_payments payment
    GROUP BY payment.order_id
),
order_reviews_agg AS (
    SELECT 
        r.order_id,
        MIN(r.review_score) AS review_score,
        CASE WHEN MIN(r.review_score) <= 2 THEN 1 ELSE 0 END AS is_bad_review
    FROM olist_order_reviews r
    GROUP BY r.order_id
)
SELECT 
    o.order_id,
    o.customer_id,
    c.customer_state,
    c.customer_city,
    i.seller_state,
    CASE WHEN c.customer_state = i.seller_state THEN 1 ELSE 0 END AS is_same_state,
    
    -- Метрики сроков доставки (в днях)
    ROUND(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0, 2) AS actual_delivery_days,
    ROUND(EXTRACT(EPOCH FROM (o.order_estimated_delivery_date - o.order_purchase_timestamp)) / 86400.0, 2) AS estimated_delivery_days,
    ROUND(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_estimated_delivery_date)) / 86400.0, 2) AS delivery_delay_days,
    CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END AS is_delayed,
    
    -- Финансовые и товарные показатели
    i.total_items,
    i.total_products_price,
    i.total_freight_value,
    i.avg_item_price,
    i.avg_product_weight_g,
    i.avg_product_photos_qty,
    i.main_product_category,
    t.product_category_name_english AS main_product_category_en,
    
    -- Оплата
    p.primary_payment_type,
    p.max_installments,
    p.total_payment_value,
    
    -- Целевая переменная (Target)
    r.review_score,
    r.is_bad_review

FROM olist_orders o
INNER JOIN olist_customers c ON o.customer_id = c.customer_id
INNER JOIN order_items_agg i ON o.order_id = i.order_id
LEFT JOIN order_payments_agg p ON o.order_id = p.order_id
LEFT JOIN order_reviews_agg r ON o.order_id = r.order_id
LEFT JOIN product_category_name_translation t ON i.main_product_category = t.product_category_name
WHERE o.order_status = 'delivered' 
  AND r.review_score IS NOT NULL;