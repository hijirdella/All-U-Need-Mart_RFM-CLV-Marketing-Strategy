CREATE TABLE transactions (
    transaction_id VARCHAR(50) PRIMARY KEY,
    customer_id VARCHAR(50),
    category VARCHAR(100),
    item VARCHAR(100),
    price_per_unit NUMERIC(10,2),
    quantity NUMERIC(10,2),
    total_spent NUMERIC(10,2),
    payment_method VARCHAR(50),
    location VARCHAR(50),
    date DATE,
    discount BOOLEAN
);

-- 1. Customer Retention vs. One-Time Buyers
-- Identifies how many customers make repeat purchases vs. those who buy only once. 
-- High one-time buyers may indicate low customer loyalty.
SELECT 
    COUNT(DISTINCT customer_id) AS total_customers,
    SUM(CASE WHEN customer_id IN (
        SELECT customer_id FROM transactions GROUP BY customer_id HAVING COUNT(transaction_id) = 1
    ) THEN 1 ELSE 0 END) AS one_time_buyers,
    SUM(CASE WHEN customer_id IN (
        SELECT customer_id FROM transactions GROUP BY customer_id HAVING COUNT(transaction_id) > 1
    ) THEN 1 ELSE 0 END) AS repeat_customers
FROM transactions;


--2. Customer Segmentation by Spending Behavior
---Groups customers based on their total spending to identify VIPs vs. budget-conscious buyers.
WITH customer_spending AS (
    SELECT 
        customer_id, 
        SUM(total_spent) AS total_spending
    FROM transactions
    GROUP BY customer_id
),
percentile_values AS (
    SELECT 
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_spending) AS high_spender_threshold,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY total_spending) AS medium_spender_threshold
    FROM customer_spending
)
SELECT cs.customer_id, cs.total_spending,
       CASE 
           WHEN cs.total_spending >= pv.high_spender_threshold THEN 'High Spender'
           WHEN cs.total_spending >= pv.medium_spender_threshold THEN 'Medium Spender'
           ELSE 'Low Spender'
       END AS customer_segment
FROM customer_spending cs
CROSS JOIN percentile_values pv
ORDER BY cs.total_spending DESC;

--3. Highest Revenue-Generating Items
--identify the top-selling individual items by revenue, 
--helping the business focus on the most profitable products.
SELECT item, SUM(total_spent) AS total_revenue, SUM(quantity) AS total_quantity_sold
FROM transactions
GROUP BY item
ORDER BY total_revenue DESC
LIMIT 5;

--4. Weekend vs. Weekday Sales Performance
--Evaluates if sales spike on weekends, helping in marketing and staffing decisions.
SELECT 
    EXTRACT(DOW FROM date) AS day_of_week,
    SUM(total_spent) AS total_revenue
FROM transactions
GROUP BY day_of_week
ORDER BY total_revenue DESC;

--5. Customer Purchase Recency & Loyalty Analysis
SELECT 
    customer_id,
    MAX(date) AS last_purchase_date,
    CURRENT_DATE - MAX(date) AS days_since_last_purchase,
    COUNT(transaction_id) AS total_purchases
FROM transactions
GROUP BY customer_id
ORDER BY days_since_last_purchase DESC;

--6. Customer Lifetime Value (CLV) Segmentation
--Identifies customers who have not purchased for a long period, increasing churn risk.
-- Identifies which customers contribute the most revenue over time.
-- Helps create VIP customer programs, retention campaigns, and predictive analytics.
WITH customer_revenue AS (
    SELECT 
        customer_id, 
        SUM(total_spent) AS lifetime_value,
        COUNT(transaction_id) AS total_transactions
    FROM transactions
    GROUP BY customer_id
)
SELECT 
    customer_id, 
    lifetime_value,
    total_transactions,
    CASE 
        WHEN lifetime_value >= (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY lifetime_value) FROM customer_revenue) 
        THEN 'High CLV'
        WHEN lifetime_value >= (SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY lifetime_value) FROM customer_revenue) 
        THEN 'Medium CLV'
        ELSE 'Low CLV'
    END AS clv_segment
FROM customer_revenue
ORDER BY lifetime_value DESC;


--7. Identifying Customers Who Were More Active Before but Have Slowed Down
--Customers who used to buy frequently but now purchase less often.
--Customers who still buy, but their purchasing rate has dropped.
WITH past_activity AS (
    SELECT 
        customer_id, 
        COUNT(transaction_id) AS past_purchases, 
        MAX(date) AS last_purchase
    FROM transactions
    WHERE date BETWEEN CURRENT_DATE - INTERVAL '1 year' AND CURRENT_DATE - INTERVAL '6 months'
    GROUP BY customer_id
),
recent_activity AS (
    SELECT 
        customer_id, 
        COUNT(transaction_id) AS recent_purchases, 
        MAX(date) AS last_purchase
    FROM transactions
    WHERE date >= CURRENT_DATE - INTERVAL '6 months'
    GROUP BY customer_id
)
SELECT p.customer_id, 
       p.past_purchases, 
       COALESCE(r.recent_purchases, 0) AS recent_purchases,  -- If no recent purchases, set to 0
       p.last_purchase AS last_active_date
FROM past_activity p
LEFT JOIN recent_activity r ON p.customer_id = r.customer_id
WHERE COALESCE(r.recent_purchases, 0) < p.past_purchases  -- Only customers with reduced activity
ORDER BY p.past_purchases DESC
LIMIT 10;

--8. Discount Dependency Analysis
--Analyzes whether customers only purchase when discounts are available, indicating price sensitivity.
SELECT 
    customer_id,
    COUNT(transaction_id) AS total_purchases,
    SUM(CASE WHEN discount = TRUE THEN 1 ELSE 0 END) AS discounted_purchases,
    ROUND((SUM(CASE WHEN discount = TRUE THEN 1 ELSE 0 END) * 100.0) / COUNT(transaction_id), 2) AS discount_dependency_percentage
FROM transactions
GROUP BY customer_id
ORDER BY discount_dependency_percentage DESC;

--9. Purchase Frequency Patterns (Time Between Purchases)
--Determines the average time between purchases for each customer.
--Helps predict when customers are likely to buy again.
WITH purchase_intervals AS (
    SELECT 
        customer_id, 
        date - LAG(date) OVER (PARTITION BY customer_id ORDER BY date) AS days_between_purchases
    FROM transactions
)
SELECT 
    customer_id, 
    ROUND(AVG(days_between_purchases), 2) AS avg_days_between_purchases,
    COUNT(*) AS purchase_count
FROM purchase_intervals
WHERE days_between_purchases IS NOT NULL
GROUP BY customer_id
ORDER BY avg_days_between_purchases ASC;


--10. High-Value Customers at Risk of Churning
--Identifies high-spending customers who have not purchased recently.
--Helps prioritize retention efforts for your most valuable customers.
--Include the top 25% of customers and allow customers inactive for 30+ days.
WITH customer_recency AS (
    SELECT customer_id, 
           SUM(total_spent) AS total_spent, 
           MAX(date) AS last_purchase_date, 
           CURRENT_DATE - MAX(date) AS days_since_last_purchase
    FROM transactions
    GROUP BY customer_id
),
percentile_threshold AS (
    SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_spent) AS high_spender_threshold
    FROM customer_recency
)
SELECT cr.customer_id, cr.total_spent, cr.last_purchase_date, cr.days_since_last_purchase
FROM customer_recency cr
CROSS JOIN percentile_threshold pt
WHERE cr.total_spent >= pt.high_spender_threshold  -- Include top 25% of spenders
AND cr.days_since_last_purchase > 30  -- Customers inactive for over 30 days
ORDER BY cr.days_since_last_purchase DESC;


