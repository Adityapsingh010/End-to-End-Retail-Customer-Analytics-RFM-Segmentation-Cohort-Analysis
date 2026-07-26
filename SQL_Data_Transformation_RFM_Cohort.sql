
SELECT TOP 5 * FROM retail_cleaned;

--RFM

Create or Alter view vw_RFM_Segments as
WITH RFM_Base AS (
    SELECT 
        CustomerID,
        DATEDIFF(DAY, MAX(InvoiceDate), (SELECT MAX(InvoiceDate) FROM retail_cleaned)) AS Recency,
        COUNT(DISTINCT InvoiceNo) AS Frequency,
        SUM(TotalPrice) AS Monetary
    FROM retail_cleaned
    GROUP BY CustomerID
),
RFM_Scores AS (
    SELECT 
        CustomerID,
        Recency,
        Frequency,
        Monetary,
        NTILE(4) OVER (ORDER BY Recency DESC) AS R_Score,
        NTILE(4) OVER (ORDER BY Frequency ASC) AS F_Score,
        NTILE(4) OVER (ORDER BY Monetary ASC) AS M_Score
    FROM RFM_Base
),
RFM_Final AS (
    SELECT 
        *,
        (R_Score + F_Score + M_Score) AS Total_RFM_Score
    FROM RFM_Scores
)
SELECT 
    CustomerID,
    Recency,
    Frequency,
    Monetary,
    R_Score,
    F_Score,
    M_Score,
    Total_RFM_Score,
    CASE 
        WHEN Total_RFM_Score >= 11 THEN 'Champions'
        WHEN Total_RFM_Score >= 9 THEN 'Loyal Customers'
        WHEN Total_RFM_Score >= 7 THEN 'Potential Loyalists'
        WHEN Total_RFM_Score >= 5 THEN 'At Risk'
        ELSE 'Lost'
    END AS Customer_Segment
FROM RFM_Final;


-- Cohort Analysis

Create view  vw_Cohort_Retentions as
with firstPurchase as (
select CustomerID,
       Datefromparts(Year(min(InvoiceDate)),Month(min(InvoiceDate)),1) as
       CohortMonth
from retail_cleaned
group by CustomerID
),
CohortBase as(
select 
r.CustomerID,
r.InvoiceNo,
f.cohortMonth,
Datefromparts(Year(r.InvoiceDate),Month(r.InvoiceDate),1) as InvoiceMonth,
((Year(r.InvoiceDate) -Year(f.cohortMonth))*12) + (Month(r.InvoiceDate)-Month(f.cohortMonth)) as CohortIndex 
from retail_cleaned r
join firstpurchase f on r.customerid = f.customerid
),
CohortSize as (
select CohortMonth,
Count(Distinct Customerid) as TotalCustomers
from CohortBase
where CohortIndex = 0
group by CohortMonth
)
select 
cb.CohortMonth,
cb.CohortIndex,
count(Distinct cb.CustomerID)as RetainedCustomers,
cs.TotalCustomers as BaseCohortSize,
Round(Cast(Count(Distinct cb.CustomerID)As float) / cs.TotalCustomers * 100,2)
as RetentionRate
from CohortBase cb
join CohortSize cs on cb.CohortMonth = cs.CohortMonth
group by 
cb.CohortMonth,
cb.CohortIndex,
cs.TotalCustomers


--view Country Performance 

Create view vw_Country_Performance as
select 
Country,
Count(Distinct CustomerID) as Total_Customers,
Count(Distinct InvoiceNo) as Total_Orders,
Round(Sum(TotalPrice),2) as Total_Revenue,
Round(sum(TotalPrice)/Nullif(Count(Distinct InvoiceNo),0),2) as Avg_Order_value
from retail_cleaned
group by Country

-- Monthly Sales Trend(Line Chart)

create view vw_sales_trend as
Select 
Year(InvoiceDate) as Sales_year,
Month(InvoiceDate) as Sales_Month,
Count(Distinct InvoiceNo) as Total_Orders,
Round(Sum(TotalPrice),2)as  Total_Revenue
from retail_cleaned
group by 
 year(InvoiceDate),
 Month(InvoiceDate)

 -- Top Products Analysis

 create view vw_Top_Products as
 select Top 50
 StockCode,
 Description,
 Sum(Quantity)as Total_Quantity_Sold,
 Round(Sum(TotalPrice),2) as Total_Revenue
 from retail_cleaned
 group by StockCode,
 Description
 order by Total_Revenue desc;

--Mom Growth

create view vw_Month_over_month as
with Monthly as (
select 
Year(InvoiceDate) as Yr,
Month(InvoiceDate) as Mo,
Round(Sum(TotalPrice),2) as Revenue
from retail_cleaned
Group by Year(InvoiceDate),Month(InvoiceDate)
)
select 
Yr,
Mo,
Lag(Revenue) over(order by Yr,Mo) as Prev_month_Revenue,
Round(
(Revenue-Lag(Revenue) over(order by Yr,Mo))
/nullif(lag(Revenue) over(order by Yr,Mo),0)*100,2) as Mom_growth_pct
from Monthly

--Customer Ranking by Revenue (Dense_Rank)

Create view vw_Customer_ranking as
select 
CustomerID,
Country,
Round(Sum(TotalPrice),2) as Total_Revenue,
Count(Distinct InvoiceNo) as Total_Orders,
DENSE_RANK() over(order by Sum(TotalPrice) Desc) as Revenue_rank,
DENSE_RANK() OVER (PARTITION BY Country ORDER BY SUM(TotalPrice) DESC) AS Country_Rank
from retail_cleaned
GROUP BY CustomerID, Country;


--Customer_Revenue_Ranking

SELECT 
    CustomerID,
    Country,
    ROUND(SUM(TotalPrice), 2) AS Total_Revenue,
    COUNT(DISTINCT InvoiceNo) AS Total_Orders,
    DENSE_RANK() OVER (ORDER BY SUM(TotalPrice) DESC) AS Revenue_Rank,
    DENSE_RANK() OVER (PARTITION BY Country ORDER BY SUM(TotalPrice) DESC) AS Country_Rank
FROM retail_cleaned
GROUP BY CustomerID, Country;


--New vs Returning customer

Create view vw_Customer_Ranking as
with 
Orders as (
select 
CustomerID,
InvoiceNO,
Datefromparts(Year(InvoiceDate),Month(InvoiceDate),1) as OrderMonth
from retail_cleaned
),
firstPurchase as(
select 
Customerid,
Min(OrderMonth) as FirstMonth
from Orders
group by CustomerId
),
Tagged as (
select 
o.OrderMonth,
o.Customerid,
case 
when o.Ordermonth = f.firstMonth then 'New'
else 'Returning'
end as CustomerType
from Orders o
join firstPurchase f on o.Customerid = f.Customerid
)
select 
OrderMonth,
Count(Distinct case when CustomerType = 'New' then CustomerID end) as New_Customers,
Count(Distinct case when CustomerType = 'Returning' then CustomerID end) as Returning_Customers
from Tagged
group by OrderMonth

--Average Days Between Purchase

create view vw_Purchase_Gap as
WITH OrderDates AS (
    SELECT 
        CustomerID,
        CAST(InvoiceDate AS DATE) AS OrderDate,
        LAG(CAST(InvoiceDate AS DATE)) OVER (PARTITION BY CustomerID ORDER BY InvoiceDate) AS PreviousOrderDate
    FROM retail_cleaned
)
SELECT 
    CustomerID,
    COUNT(*) AS Total_Purchases,
    AVG(DATEDIFF(DAY, PreviousOrderDate, OrderDate)) AS Avg_Days_Between_Orders,
    MIN(DATEDIFF(DAY, PreviousOrderDate, OrderDate)) AS Min_Gap,
    MAX(DATEDIFF(DAY, PreviousOrderDate, OrderDate)) AS Max_Gap
FROM OrderDates
WHERE PreviousOrderDate IS NOT NULL
GROUP BY CustomerID;



-- Repeat Purchase Rate 

Create view vw_Repeat_Rate as
with CustomerOrders as (
select 
CustomerID,
Count(Distinct InvoiceNo) as OrderCount
from retail_cleaned
group by CustomerID
)
select 
Count(*) as Total_Customers,
sum(Case when OrderCount = 1 then 1 else 0 end) as One_time_buyers,
sum(Case when OrderCount > 1 then 1 else 0 end) as Repeat_Buyers,
Round(
Cast(Sum(Case when OrderCount >1 then 1 else 0 end)as float) / Count(*)*100,2) as Repeat_Purchase_Rate_Pct
from CustomerOrders