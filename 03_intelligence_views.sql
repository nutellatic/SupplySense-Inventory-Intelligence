-- Analytics are calculated from transactional tables; no external/black-box service is required.
CREATE OR REPLACE VIEW v_product_intelligence AS
WITH demand AS (
  SELECT p.product_id,
         NVL(SUM(CASE WHEN s.sale_date >= TRUNC(SYSDATE)-29 THEN si.quantity ELSE 0 END),0) AS units_30d,
         NVL(SUM(CASE WHEN s.sale_date >= TRUNC(SYSDATE)-59 AND s.sale_date < TRUNC(SYSDATE)-29 THEN si.quantity ELSE 0 END),0) AS units_prev30d,
         NVL(SUM(CASE WHEN s.sale_date >= TRUNC(SYSDATE)-29 THEN si.quantity*si.unit_price ELSE 0 END),0) AS revenue_30d
  FROM products p
  LEFT JOIN sale_items si ON si.product_id=p.product_id
  LEFT JOIN sales s ON s.sale_id=si.sale_id
  GROUP BY p.product_id
), metrics AS (
  SELECT p.product_id,p.product_name,p.sku,p.quantity_in_stock,p.reorder_level,p.unit_price,p.unit_cost,
         sup.supplier_name,sup.lead_time_days,d.units_30d,d.units_prev30d,d.revenue_30d,
         ROUND(d.units_30d/30,3) AS avg_daily_units,
         ROUND(d.revenue_30d,2) AS revenue_30d_value,
         CASE WHEN d.units_30d=0 THEN NULL ELSE ROUND(p.quantity_in_stock/(d.units_30d/30),1) END AS days_of_cover,
         CASE WHEN d.units_30d=0 THEN NULL ELSE TRUNC(SYSDATE + p.quantity_in_stock/(d.units_30d/30)) END AS estimated_stockout_date,
         CASE WHEN d.units_prev30d=0 AND d.units_30d>0 THEN 100
              WHEN d.units_prev30d=0 THEN 0
              ELSE ROUND((d.units_30d-d.units_prev30d)*100/d.units_prev30d,1) END AS demand_change_pct,
         
GREATEST(
    CEIL(
        (d.units_30d / 30) * (sup.lead_time_days + 14)
        + p.reorder_level
        - p.quantity_in_stock
    ),
    0
) AS suggested_reorder_qty

  FROM products p
  JOIN suppliers sup ON sup.supplier_id=p.supplier_id
  JOIN demand d ON d.product_id=p.product_id
)
SELECT m.*,
       CASE WHEN quantity_in_stock=0 THEN 'CRITICAL'
            WHEN quantity_in_stock<=reorder_level THEN 'CRITICAL'
            WHEN avg_daily_units>0 AND days_of_cover<=lead_time_days THEN 'CRITICAL'
            WHEN avg_daily_units>0 AND days_of_cover<=lead_time_days+7 THEN 'HIGH'
            WHEN demand_change_pct>=30 THEN 'WATCH'
            ELSE 'HEALTHY' END AS risk_level,
       CASE WHEN units_30d=0 THEN 'No recent sales'
            WHEN demand_change_pct>=30 THEN 'Demand accelerating'
            WHEN demand_change_pct<=-30 THEN 'Demand slowing'
            ELSE 'Demand broadly stable' END AS demand_signal
FROM metrics m;

CREATE OR REPLACE VIEW v_sales_daily AS
SELECT TRUNC(s.sale_date) AS sales_day,
       COUNT(DISTINCT s.sale_id) AS order_count,
       SUM(si.quantity) AS units_sold,
       ROUND(SUM(si.quantity*si.unit_price),2) AS gross_revenue
FROM sales s JOIN sale_items si ON si.sale_id=s.sale_id
GROUP BY TRUNC(s.sale_date);

CREATE OR REPLACE VIEW v_category_performance AS
SELECT c.category_id,c.category_name,
       COUNT(DISTINCT p.product_id) AS product_count,
       NVL(SUM(CASE WHEN s.sale_date>=TRUNC(SYSDATE)-29 THEN si.quantity ELSE 0 END),0) AS units_sold_30d,
       ROUND(NVL(SUM(CASE WHEN s.sale_date>=TRUNC(SYSDATE)-29 THEN si.quantity*si.unit_price ELSE 0 END),0),2) AS revenue_30d,
       ROUND(NVL(SUM(CASE WHEN s.sale_date>=TRUNC(SYSDATE)-29 THEN si.quantity*(si.unit_price-p.unit_cost) ELSE 0 END),0),2) AS gross_margin_30d
FROM categories c
LEFT JOIN products p ON p.category_id=c.category_id
LEFT JOIN sale_items si ON si.product_id=p.product_id
LEFT JOIN sales s ON s.sale_id=si.sale_id
GROUP BY c.category_id,c.category_name;

PROMPT SupplySense intelligence views created.
