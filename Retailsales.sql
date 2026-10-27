create database retailsales;
use retailsales; 

ALTER TABLE budgets
MODIFY COLUMN product_name VARCHAR(255) NOT NULL;

ALTER TABLE budgets
ADD PRIMARY KEY (product_name);

ALTER TABLE products
MODIFY COLUMN product_name VARCHAR(255);

ALTER TABLE budgets
ADD COLUMN budget_2017_amount DECIMAL(15,2);

UPDATE budgets
SET budget_2017_amount =
    CAST(REPLACE(`2017_budgets`, ',', '') AS DECIMAL(15,2));

select * from salesorder;
select * from regions;
select * from products;
select * from customers;
select * from budgets;

# 1. Data Quality checks

# Check for missing values
SELECT
    SUM(CASE WHEN OrderNumber IS NULL THEN 1 ELSE 0 END)
        AS MissingOrderNumber,

    SUM(CASE WHEN OrderDate IS NULL THEN 1 ELSE 0 END)
        AS MissingOrderDate,

    SUM(CASE WHEN `Customer Name Index` IS NULL THEN 1 ELSE 0 END)
        AS MissingCustomerID,

    SUM(CASE WHEN `Unit Price` IS NULL THEN 1 ELSE 0 END)
        AS MissingUnitPrice,

    SUM(CASE WHEN `Line Total` IS NULL THEN 1 ELSE 0 END)
        AS MissingLineTotal

FROM salesorder;

# Check for duplicate order numbers
SELECT
    OrderNumber,
    COUNT(*) AS RecordCount
FROM salesorder
GROUP BY OrderNumber
HAVING COUNT(*) > 1
ORDER BY RecordCount DESC;

# Check numerical values
SELECT
    MIN(`Order Quantity`) AS MinimumQuantity,
    MAX(`Order Quantity`) AS MaximumQuantity,

    MIN(`Unit Price`) AS MinimumUnitPrice,
    MAX(`Unit Price`) AS MaximumUnitPrice,

    MIN(`Line Total`) AS MinimumLineTotal,
    MAX(`Line Total`) AS MaximumLineTotal,

    MIN(`Total Unit Cost`) AS MinimumUnitCost,
    MAX(`Total Unit Cost`) AS MaximumUnitCost

FROM salesorder;

#2. Business analysis

# Sales performance by year
SELECT
    YEAR(OrderDate) AS SalesYear,
    COUNT(*) AS OrderLines,
    SUM(`Line_Total`) AS TotalSales
FROM salesorder
GROUP BY YEAR(OrderDate)
ORDER BY SalesYear;

# Year-over-year growth analysis
SELECT
    YEAR(STR_TO_DATE(OrderDate, '%d-%m-%Y')) AS SalesYear,
    COUNT(*) AS OrderLines,
    ROUND(SUM(Line_Total), 2) AS TotalSales
FROM salesorder
GROUP BY YEAR(STR_TO_DATE(OrderDate, '%d-%m-%Y'))
ORDER BY SalesYear;

WITH YearlySales AS (
    SELECT
        YEAR(STR_TO_DATE(OrderDate, '%d-%m-%Y')) AS SalesYear,
        COUNT(*) AS OrderLines,
        SUM(Line_Total) AS TotalSales
    FROM salesorder
    GROUP BY YEAR(STR_TO_DATE(OrderDate, '%d-%m-%Y'))
)
SELECT
    SalesYear,
    OrderLines,
    ROUND(TotalSales, 2) AS TotalSales,
    ROUND(
        (
            TotalSales - LAG(TotalSales) OVER (ORDER BY SalesYear)
        ) * 100.0
        / NULLIF(LAG(TotalSales) OVER (ORDER BY SalesYear), 0),
        2
    ) AS SalesGrowthPercentage
FROM YearlySales
ORDER BY SalesYear;

# Sales performance by channel
SELECT
    Channel,
    COUNT(*) AS OrderLines,
    SUM(Order_Quantity) AS TotalQuantity,
    ROUND(SUM(Line_Total), 2) AS TotalSales
FROM salesorder
GROUP BY Channel
ORDER BY TotalSales DESC;

# Top 10 products by sales
SELECT
    p.product_name AS ProductName,
    SUM(s.Order_Quantity) AS TotalQuantity,
    ROUND(SUM(s.Line_Total), 2) AS TotalSales
FROM salesorder AS s
JOIN products AS p
    ON s.Product_Description_Index = p.`index`
GROUP BY p.`index`, p.product_name
ORDER BY TotalSales DESC
LIMIT 10;

# Sales for each product
SELECT
    p.`index` AS ProductID,
    p.product_name AS ProductName,
    SUM(s.Order_Quantity) AS TotalQuantitySold,
    ROUND(SUM(s.Line_Total), 2) AS TotalSales,
    COUNT(*) AS OrderLines
FROM salesorder AS s
JOIN products AS p
    ON s.Product_Description_Index = p.`index`
GROUP BY
    p.`index`,
    p.product_name
ORDER BY TotalSales DESC;

# Each product's share of total sales
SELECT
    p.product_name AS ProductName,
    ROUND(SUM(s.Line_Total), 2) AS TotalSales,
    ROUND(
        SUM(s.Line_Total) * 100.0 /
        (SELECT SUM(Line_Total) FROM salesorder),
        2
    ) AS SalesSharePercentage
FROM salesorder AS s
JOIN products AS p
    ON s.Product_Description_Index = p.`index`
GROUP BY
    p.`index`,
    p.product_name
ORDER BY TotalSales DESC;

# Sales performance by country
SELECT
    r.country AS Country,
    COUNT(*) AS OrderLines,
    ROUND(SUM(s.Line_Total), 2) AS TotalSales
FROM salesorder AS s
JOIN regions AS r
    ON s.Delivery_Region_Index = r.`index`
GROUP BY r.country
ORDER BY TotalSales DESC;

# Customer performance
SELECT
    c.customer_names AS CustomerName,
    COUNT(*) AS OrderLines,
    SUM(s.Order_Quantity) AS TotalQuantity,
    ROUND(SUM(s.Line_Total), 2) AS TotalSales
FROM salesorder AS s
JOIN customers AS c
    ON s.Customer_Name_Index = c.customer_index
GROUP BY c.customer_index, c.customer_names
ORDER BY TotalSales DESC
LIMIT 10;

# Sales versus recorded cost
SELECT
    ROUND(SUM(Line_Total), 2) AS TotalSales,
    ROUND(SUM(Total_Unit_Cost), 2) AS TotalRecordedCost,
    ROUND(
        SUM(Line_Total) - SUM(Total_Unit_Cost),
        2
    ) AS SalesCostDifference
FROM salesorder;

# Compare 2017 actual sales against the budget
WITH ActualSales AS (
    SELECT
        p.`index` AS product_id,
        p.product_name,
        SUM(s.Line_Total) AS actual_sales_2017
    FROM salesorder AS s
    JOIN products AS p
        ON s.Product_Description_Index = p.`index`
    WHERE YEAR(
        STR_TO_DATE(s.OrderDate, '%d-%m-%Y')
    ) = 2017
    GROUP BY
        p.`index`,
        p.product_name
)

SELECT
    b.product_name AS ProductName,
    b.budget_2017_amount AS Budget2017,
    ROUND(COALESCE(a.actual_sales_2017, 0), 2) AS ActualSales2017,

    ROUND(
        COALESCE(a.actual_sales_2017, 0) - b.budget_2017_amount,
        2
    ) AS BudgetVariance,

    ROUND(
        COALESCE(a.actual_sales_2017, 0) * 100.0
        / NULLIF(b.budget_2017_amount, 0),
        2
    ) AS BudgetAchievementPercentage,

    CASE
        WHEN b.budget_2017_amount = 0 THEN 'Zero Budget'
        WHEN a.actual_sales_2017 IS NULL THEN 'No Recorded Sales'
        WHEN a.actual_sales_2017 > b.budget_2017_amount
            THEN 'Above Budget'
        WHEN a.actual_sales_2017 = b.budget_2017_amount
            THEN 'On Budget'
        ELSE 'Below Budget'
    END AS PerformanceStatus

FROM budgets AS b
LEFT JOIN ActualSales AS a
    ON TRIM(b.product_name) = TRIM(a.product_name)
ORDER BY BudgetAchievementPercentage DESC;

# Identify the Top 10 Customers by Sales
SELECT
    c.customer_index AS CustomerID,
    c.customer_names AS CustomerName,
    COUNT(*) AS OrderLines,
    SUM(s.Order_Quantity) AS TotalQuantity,
    ROUND(SUM(s.Line_Total), 2) AS TotalSales
FROM salesorder AS s
JOIN customers AS c
    ON s.Customer_Name_Index = c.customer_index
GROUP BY
    c.customer_index,
    c.customer_names
ORDER BY TotalSales DESC
LIMIT 10;

# Sales and Cost Analysis
SELECT
    ROUND(SUM(Line_Total), 2) AS TotalSales,
    ROUND(SUM(Total_Unit_Cost), 2) AS TotalRecordedCost,
    ROUND(
        SUM(Line_Total) - SUM(Total_Unit_Cost),
        2
    ) AS SalesCostDifference
FROM salesorder;

SELECT
    YEAR(STR_TO_DATE(OrderDate, '%d-%m-%Y')) AS SalesYear,
    ROUND(SUM(Line_Total), 2) AS TotalSales,
    ROUND(SUM(Total_Unit_Cost), 2) AS TotalRecordedCost,
    ROUND(
        SUM(Line_Total) - SUM(Total_Unit_Cost),
        2
    ) AS SalesCostDifference
FROM salesorder
GROUP BY YEAR(STR_TO_DATE(OrderDate, '%d-%m-%Y'))
ORDER BY SalesYear;

# Monthly Sales Trend Analysis
SELECT
    YEAR(STR_TO_DATE(OrderDate, '%d-%m-%Y')) AS SalesYear,
    MONTH(STR_TO_DATE(OrderDate, '%d-%m-%Y')) AS SalesMonth,
    MONTHNAME(STR_TO_DATE(OrderDate, '%d-%m-%Y')) AS MonthName,
    COUNT(*) AS OrderLines,
    SUM(Order_Quantity) AS TotalQuantity,
    ROUND(SUM(Line_Total), 2) AS TotalSales
FROM salesorder
GROUP BY
    YEAR(STR_TO_DATE(OrderDate, '%d-%m-%Y')),
    MONTH(STR_TO_DATE(OrderDate, '%d-%m-%Y')),
    MONTHNAME(STR_TO_DATE(OrderDate, '%d-%m-%Y'))
ORDER BY
    SalesYear,
    SalesMonth;
    
    SELECT
    YEAR(STR_TO_DATE(OrderDate, '%d-%m-%Y')) AS SalesYear,
    MONTHNAME(STR_TO_DATE(OrderDate, '%d-%m-%Y')) AS MonthName,
    ROUND(SUM(Line_Total), 2) AS TotalSales
FROM salesorder
GROUP BY
    YEAR(STR_TO_DATE(OrderDate, '%d-%m-%Y')),
    MONTH(STR_TO_DATE(OrderDate, '%d-%m-%Y')),
    MONTHNAME(STR_TO_DATE(OrderDate, '%d-%m-%Y'))
ORDER BY TotalSales DESC
LIMIT 5;

WITH MonthlySales AS (
    SELECT
        YEAR(STR_TO_DATE(OrderDate, '%d-%m-%Y')) AS SalesYear,
        MONTH(STR_TO_DATE(OrderDate, '%d-%m-%Y')) AS SalesMonth,
        SUM(Line_Total) AS TotalSales
    FROM salesorder
    GROUP BY
        YEAR(STR_TO_DATE(OrderDate, '%d-%m-%Y')),
        MONTH(STR_TO_DATE(OrderDate, '%d-%m-%Y'))
),
SalesWithPreviousMonth AS (
    SELECT
        SalesYear,
        SalesMonth,
        TotalSales,
        LAG(TotalSales) OVER (
            ORDER BY SalesYear, SalesMonth
        ) AS PreviousPeriodSales
    FROM MonthlySales
)
SELECT
    SalesYear,
    SalesMonth,
    ROUND(TotalSales, 2) AS TotalSales,
    ROUND(PreviousPeriodSales, 2) AS PreviousPeriodSales,
    ROUND(
        (TotalSales - PreviousPeriodSales) * 100.0
        / NULLIF(PreviousPeriodSales, 0),
        2
    ) AS GrowthPercentage
FROM SalesWithPreviousMonth
ORDER BY SalesYear, SalesMonth;

# Regional Sales Performance Analysis
SELECT
    r.country AS Country,
    COUNT(*) AS OrderLines,
    SUM(s.Order_Quantity) AS TotalQuantity,
    ROUND(SUM(s.Line_Total), 2) AS TotalSales
FROM salesorder AS s
JOIN regions AS r
    ON s.Delivery_Region_Index = r.`index`
GROUP BY r.country
ORDER BY TotalSales DESC;

SELECT
    r.country AS Country,
    r.city AS City,
    COUNT(*) AS OrderLines,
    ROUND(SUM(s.Line_Total), 2) AS TotalSales
FROM salesorder AS s
JOIN regions AS r
    ON s.Delivery_Region_Index = r.`index`
GROUP BY
    r.country,
    r.city
ORDER BY TotalSales DESC
LIMIT 10;

SELECT
    r.country AS Country,
    ROUND(SUM(s.Line_Total), 2) AS TotalSales,
    ROUND(
        SUM(s.Line_Total) * 100.0 /
        (SELECT SUM(Line_Total) FROM salesorder),
        2
    ) AS SalesContributionPercentage
FROM salesorder AS s
JOIN regions AS r
    ON s.Delivery_Region_Index = r.`index`
GROUP BY r.country
ORDER BY TotalSales DESC;

SELECT
    YEAR(STR_TO_DATE(s.OrderDate, '%d-%m-%Y')) AS SalesYear,
    r.country AS Country,
    ROUND(SUM(s.Line_Total), 2) AS TotalSales
FROM salesorder AS s
JOIN regions AS r
    ON s.Delivery_Region_Index = r.`index`
GROUP BY
    YEAR(STR_TO_DATE(s.OrderDate, '%d-%m-%Y')),
    r.country
ORDER BY SalesYear, TotalSales DESC;














































