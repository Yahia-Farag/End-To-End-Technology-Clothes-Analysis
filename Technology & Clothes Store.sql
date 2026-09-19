/*
  =============================================================================
  Project Name: Technology & Clothes Store Sales & Financial Performance Analysis
  Database: RetailChain
  Description: Comprehensive SQL scripts covering Data Cleaning, EDA, 
               KPI Calculations, Views, and Performance Metrics for 2022-2024.
  =============================================================================
*/

USE RetailChain;
GO

-----------------------------------------------------------------------------
-- 1. DATA EXPLORATION & ROW COUNTS
-----------------------------------------------------------------------------
SELECT COUNT(*) AS CountCustomer FROM customers;
SELECT COUNT(*) AS CountDate FROM date;
SELECT COUNT(*) AS CountEmployees FROM employees;
SELECT COUNT(*) AS CountFac22_23 FROM fact_orders_2022_2023;
SELECT COUNT(*) AS CountFac24 FROM fact_orders_2024;
SELECT COUNT(*) AS CountFacRtns FROM fact_returns;
SELECT COUNT(*) AS CountOrdtls FROM orderdetails;
SELECT COUNT(*) AS CountProduct FROM products;
SELECT COUNT(*) AS CountStore FROM stores;
GO

-----------------------------------------------------------------------------
-- 2. DATA CLEANING: HANDLING DUPLICATES IN CUSTOMERS TABLE
-----------------------------------------------------------------------------
-- Detect duplicates
SELECT customer_id, COUNT(*) AS CountRows
FROM customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- Count rows to be deleted
WITH RankedCustomer AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY customer_id) AS RowNum
    FROM customers
)
SELECT COUNT(*) AS CountToDelete
FROM RankedCustomer
WHERE RowNum > 1;

-- Delete duplicate rows
WITH RankedCustomer AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY customer_id) AS RowNum
    FROM customers
)
DELETE FROM RankedCustomer
WHERE RowNum > 1;

-- Verify deletion
SELECT COUNT(*) AS CountRows FROM customers;
GO

-----------------------------------------------------------------------------
-- 3. DATA INTEGRITY & NULL CHECKS
-----------------------------------------------------------------------------
SELECT COUNT(*) AS Total_Rows,
       COUNT(payment_method) AS Non_null_Values,
       COUNT(*) - COUNT(payment_method) AS Missing_Rows
FROM fact_orders_2024;
GO

-----------------------------------------------------------------------------
-- 4. JOINS & EXPLORATORY DATA ANALYSIS (EDA)
-----------------------------------------------------------------------------
-- Get store name for each order
SELECT st.store_name, order_id, total_revenue
FROM fact_orders_2024 fc24 
INNER JOIN stores st ON fc24.store_id = st.store_id;

-- Orders without a registered employee
SELECT emp.employee_id, emp.first_name, fc24.order_id, fc24.store_id
FROM employees emp 
RIGHT JOIN fact_orders_2024 fc24 ON emp.employee_id = fc24.employee_id
WHERE emp.employee_id IS NULL
ORDER BY fc24.store_id;

-- Status count for orders without employees
SELECT fc24.order_status, COUNT(*) AS CountRows
FROM employees emp 
RIGHT JOIN fact_orders_2024 fc24 ON emp.employee_id = fc24.employee_id
WHERE emp.employee_id IS NULL
GROUP BY fc24.order_status;

-- Add employee registration status column and update it
ALTER TABLE fact_orders_2024 ADD Employee_Registration_Status NVARCHAR(20);

UPDATE fact_orders_2024
SET Employee_Registration_Status = 
	CASE
		WHEN employee_id IS NULL THEN 'Unregistered'
		WHEN employee_id IS NOT NULL THEN 'Registered'
	END;

SELECT COUNT(*) AS CountRows, Employee_Registration_Status
FROM fact_orders_2024
GROUP BY Employee_Registration_Status;

-- Total revenue per customer and city
SELECT c.full_name, c.city, SUM(fc24.total_revenue) AS TotalRevenue
FROM customers c 
LEFT JOIN fact_orders_2024 fc24 ON c.customer_id = fc24.customer_id
GROUP BY c.full_name, c.city, c.customer_id;

-- Timeline range
SELECT MIN(order_date) AS FirstOrder, MAX(order_date) AS LastOrder
FROM fact_orders_2024;
GO

-----------------------------------------------------------------------------
-- 5. CUSTOMER BEHAVIOR & RETURNING ANALYSIS
-----------------------------------------------------------------------------
-- Cities with highest inactive/zero-purchase customers
WITH CustomerRevenue AS (
    SELECT c.customer_id, c.city, SUM(total_revenue) AS TotalRevenue
    FROM customers c 
    LEFT JOIN fact_orders_2024 fc24 ON c.customer_id = fc24.customer_id
    GROUP BY c.customer_id, c.city
)
SELECT city, COUNT(*) AS CountRows
FROM CustomerRevenue
WHERE TotalRevenue IS NULL
GROUP BY city
ORDER BY CountRows DESC;

-- Registration year of customers who didn't purchase in 2024
WITH CustomerRevenue AS (
    SELECT c.customer_id, c.registration_date, SUM(total_revenue) AS TotalRevenue
    FROM customers c 
    LEFT JOIN fact_orders_2024 fc24 ON c.customer_id = fc24.customer_id
    GROUP BY c.customer_id, c.registration_date
)
SELECT YEAR(registration_date) AS RegYear, COUNT(*) AS CountRows
FROM CustomerRevenue
WHERE TotalRevenue IS NULL
GROUP BY YEAR(registration_date)
ORDER BY RegYear DESC;
GO

-----------------------------------------------------------------------------
-- 6. RETURNS & STORE PERFORMANCE METRICS
-----------------------------------------------------------------------------
SELECT TOP 5 * FROM fact_returns;

-- Return percentage per store combining years
WITH AllOrders AS (
    SELECT order_id, store_id FROM fact_orders_2022_2023
    UNION ALL
    SELECT order_id, store_id FROM fact_orders_2024
)
SELECT 
    o.store_id,
    COUNT(DISTINCT o.order_id) AS TotalOrders,
    COUNT(r.return_id) AS TotalReturns,
    ROUND(COUNT(r.return_id) * 100.0 / COUNT(DISTINCT o.order_id), 2) AS ReturnPercentage
FROM AllOrders o
LEFT JOIN fact_returns r ON o.order_id = r.order_id
GROUP BY o.store_id
ORDER BY ReturnPercentage DESC;
GO

-----------------------------------------------------------------------------
-- 7. PAYMENT METHODS & TEMPORAL ANALYSIS (RAMADAN & MONTHS)
-----------------------------------------------------------------------------
-- Most used payment method per store
WITH Payments_Count AS (
    SELECT store_id, payment_method, COUNT(*) AS Usage_Count,
           ROW_NUMBER() OVER (PARTITION BY store_id ORDER BY COUNT(*) DESC) AS rn
    FROM fact_orders_2024
    GROUP BY store_id, payment_method
)
SELECT store_id, payment_method, Usage_Count 
FROM Payments_Count
WHERE rn = 1;

-- Sales performance during Ramadan
SELECT store_id, COUNT(order_id) AS Total_Orders, SUM(total_revenue) AS Total_Revenue
FROM fact_orders_2024 fc24 
INNER JOIN date d ON fc24.date_id = d.date_id
WHERE is_ramadan = 1 
GROUP BY store_id
ORDER BY Total_Revenue DESC;

-- Sales performance outside Ramadan
SELECT store_id, COUNT(order_id) AS Total_Orders, SUM(total_revenue) AS Total_Revenue
FROM fact_orders_2024 fc24 
INNER JOIN date d ON fc24.date_id = d.date_id
WHERE is_ramadan = 0 
GROUP BY store_id
ORDER BY Total_Revenue DESC;

-- Revenue by category during Ramadan
SELECT 
    p.category,
    SUM(ods.selling_price * ods.quantity) AS total_category_revenue,
    COUNT(DISTINCT fc24.order_id) AS total_orders
FROM fact_orders_2024 fc24
INNER JOIN date d ON fc24.date_id = d.date_id
INNER JOIN orderdetails ods ON fc24.order_id = ods.order_id
INNER JOIN products p ON ods.product_id = p.product_id
WHERE d.is_ramadan = 1
GROUP BY p.category
ORDER BY total_category_revenue DESC;

-- Return rate percentage per product category
SELECT 
    p.category,
    COUNT(DISTINCT fc24.order_id) AS total_orders,
    COUNT(DISTINCT fcrt.order_id) AS returned_orders,
    ROUND(CAST(COUNT(DISTINCT fcrt.order_id) AS FLOAT) / COUNT(DISTINCT fc24.order_id) * 100, 2) AS return_rate_percentage
FROM fact_orders_2024 fc24
INNER JOIN orderdetails ods ON fc24.order_id = ods.order_id
INNER JOIN products p ON ods.product_id = p.product_id
LEFT JOIN fact_returns fcrt ON fc24.order_id = fcrt.order_id
GROUP BY p.category;
GO

-----------------------------------------------------------------------------
-- 8. PROFITABILITY CALCULATIONS & VIEWS
-----------------------------------------------------------------------------
-- Add Net Profit column to 2022-2023 data
ALTER TABLE fact_orders_2022_2023 ADD Net_Profit DECIMAL(10,2);
UPDATE fact_orders_2022_2023 SET Net_Profit = total_revenue - total_cost;

-- Add Net Profit column to 2024 data
ALTER TABLE fact_orders_2024 ADD Net_Profit DECIMAL(10,2);
UPDATE fact_orders_2024 SET Net_Profit = total_revenue - total_cost;

-- Create unified view for all years
CREATE VIEW All_Years_Orders AS 
SELECT order_id, order_date, date_id, customer_id, store_id, employee_id, payment_method, order_status, total_revenue, total_cost, Net_Profit, YEAR(order_date) AS Order_Year
FROM fact_orders_2022_2023
UNION ALL
SELECT order_id, order_date, date_id, customer_id, store_id, employee_id, payment_method, order_status, total_revenue, total_cost, Net_Profit, YEAR(order_date) AS Order_Year
FROM fact_orders_2024;
GO