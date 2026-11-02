-- Query pack: run after schema, seed, views, and PL/SQL setup.
SET LINESIZE 220
SET PAGESIZE 100

PROMPT 1. Dashboard KPIs
SELECT COUNT(*) AS product_count,
       SUM(quantity_in_stock) AS units_in_stock,
       SUM(quantity_in_stock*unit_cost) AS inventory_cost_value,
       SUM(CASE WHEN risk_level='CRITICAL' THEN 1 ELSE 0 END) AS critical_products,
       SUM(CASE WHEN risk_level='HIGH' THEN 1 ELSE 0 END) AS high_risk_products
FROM v_product_intelligence;

PROMPT 2. Ranked stockout risk list
SELECT sku,product_name,quantity_in_stock,units_30d,avg_daily_units,lead_time_days,days_of_cover,estimated_stockout_date,risk_level,suggested_reorder_qty
FROM v_product_intelligence
ORDER BY CASE risk_level WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'WATCH' THEN 3 ELSE 4 END, days_of_cover NULLS LAST;

PROMPT 3. Demand momentum
SELECT sku,product_name,units_30d,units_prev30d,demand_change_pct,demand_signal
FROM v_product_intelligence ORDER BY demand_change_pct DESC;

PROMPT 4. Category performance and gross margin
SELECT category_name,product_count,units_sold_30d,revenue_30d,gross_margin_30d
FROM v_category_performance ORDER BY revenue_30d DESC;

PROMPT 5. Revenue by day
SELECT sales_day,order_count,units_sold,gross_revenue FROM v_sales_daily ORDER BY sales_day DESC;

PROMPT 6. Products below the reorder threshold
SELECT sku,product_name,quantity_in_stock,reorder_level,supplier_name,lead_time_days
FROM v_product_intelligence WHERE quantity_in_stock<=reorder_level ORDER BY quantity_in_stock;

PROMPT 7. Inventory value by category
SELECT c.category_name,ROUND(SUM(p.quantity_in_stock*p.unit_cost),2) AS stock_cost_value
FROM categories c JOIN products p ON p.category_id=c.category_id GROUP BY c.category_name ORDER BY stock_cost_value DESC;

PROMPT 8. Highest revenue products in last 30 days
SELECT p.sku,p.product_name,SUM(si.quantity) AS units_sold,ROUND(SUM(si.quantity*si.unit_price),2) AS revenue
FROM products p JOIN sale_items si ON si.product_id=p.product_id JOIN sales s ON s.sale_id=si.sale_id
WHERE s.sale_date>=TRUNC(SYSDATE)-29 GROUP BY p.sku,p.product_name ORDER BY revenue DESC;

PROMPT 9. Purchase order queue
SELECT po.purchase_reference,s.supplier_name,po.order_date,po.status,COUNT(pi.purchase_item_id) AS line_count
FROM purchase_orders po JOIN suppliers s ON s.supplier_id=po.supplier_id LEFT JOIN purchase_items pi ON pi.purchase_id=po.purchase_id
GROUP BY po.purchase_reference,s.supplier_name,po.order_date,po.status ORDER BY po.order_date DESC;

PROMPT 10. Latest inventory audit events
SELECT a.audit_id,p.sku,p.product_name,a.old_quantity,a.new_quantity,a.quantity_delta,a.changed_at,a.change_note
FROM inventory_audit a JOIN products p ON p.product_id=a.product_id ORDER BY a.changed_at DESC;

PROMPT 11. Customer lifetime sales
SELECT c.customer_name,COUNT(DISTINCT s.sale_id) AS order_count,ROUND(NVL(SUM(s.total_amount),0),2) AS lifetime_revenue
FROM customers c LEFT JOIN sales s ON s.customer_id=c.customer_id GROUP BY c.customer_name ORDER BY lifetime_revenue DESC;

PROMPT 12. Slow-moving inventory with stock on hand
SELECT sku,product_name,quantity_in_stock,units_30d,ROUND(quantity_in_stock*unit_cost,2) AS tied_up_cost
FROM v_product_intelligence WHERE units_30d<=1 AND quantity_in_stock>0 ORDER BY tied_up_cost DESC;

PROMPT 13. Supplier lead-time exposure
SELECT supplier_name,lead_time_days,COUNT(*) AS products_supplied,
       SUM(CASE WHEN risk_level IN ('CRITICAL','HIGH') THEN 1 ELSE 0 END) AS risky_products
FROM v_product_intelligence GROUP BY supplier_name,lead_time_days ORDER BY risky_products DESC;

PROMPT 14. Correlated subquery: products priced above category average
SELECT p.product_name,p.unit_price,c.category_name FROM products p JOIN categories c ON c.category_id=p.category_id
WHERE p.unit_price>(SELECT AVG(p2.unit_price) FROM products p2 WHERE p2.category_id=p.category_id);

PROMPT 15. Subquery: products with sales in the last 30 days
SELECT product_name,sku FROM products p WHERE EXISTS (
  SELECT 1 FROM sale_items si JOIN sales s ON s.sale_id=si.sale_id
  WHERE si.product_id=p.product_id AND s.sale_date>=TRUNC(SYSDATE)-29
);
