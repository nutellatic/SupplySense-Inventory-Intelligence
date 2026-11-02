-- Run one demo at a time. These commands change your sample database.
SET SERVEROUTPUT ON

PROMPT DEMO A: PL/SQL cursor risk report
BEGIN print_inventory_risk_report; END;
/

PROMPT DEMO B: successful sale (commit only after checking returned ID)
VARIABLE new_sale_id NUMBER
DECLARE v_customer_id NUMBER; v_product_id NUMBER;
BEGIN
  SELECT customer_id INTO v_customer_id FROM customers WHERE email='aarav.retail@example.com';
  SELECT product_id INTO v_product_id FROM products WHERE sku='CB-500';
  process_sale(v_customer_id,v_product_id,1,:new_sale_id);
END;
/
PRINT new_sale_id
SELECT sku,quantity_in_stock FROM products WHERE sku='CB-500';
SELECT * FROM inventory_audit WHERE product_id=(SELECT product_id FROM products WHERE sku='CB-500') ORDER BY changed_at DESC;
COMMIT;

PROMPT DEMO C: receive pending purchase order PO-DEMO-01
DECLARE v_purchase_id NUMBER;
BEGIN
  SELECT purchase_id INTO v_purchase_id FROM purchase_orders WHERE purchase_reference='PO-DEMO-01';
  receive_purchase_order(v_purchase_id);
END;
/
SELECT purchase_reference,status FROM purchase_orders WHERE purchase_reference='PO-DEMO-01';
SELECT sku,quantity_in_stock FROM products WHERE sku='MS-200';
COMMIT;

PROMPT DEMO D: controlled stock adjustment and audit trigger
DECLARE v_product_id NUMBER;
BEGIN
  SELECT product_id INTO v_product_id FROM products WHERE sku='UC-900';
  adjust_stock(v_product_id,14);
END;
/
SELECT sku,quantity_in_stock FROM products WHERE sku='UC-900';
SELECT p.sku,a.old_quantity,a.new_quantity,a.quantity_delta,a.change_note,a.changed_at
FROM inventory_audit a JOIN products p ON p.product_id=a.product_id WHERE p.sku='UC-900' ORDER BY a.changed_at DESC;
ROLLBACK;

PROMPT DEMO E: failed sale should raise ORA-20004 and leave stock unchanged
-- Use a deliberately impossible quantity. Expect ORA-20004, then verify stock is unchanged.
DECLARE v_sale_id NUMBER; v_before NUMBER; v_after NUMBER; v_customer_id NUMBER; v_product_id NUMBER;
BEGIN
  SELECT quantity_in_stock INTO v_before FROM products WHERE sku='MS-200';
  SELECT customer_id INTO v_customer_id FROM customers WHERE email='aarav.retail@example.com';
  SELECT product_id INTO v_product_id FROM products WHERE sku='MS-200';
  BEGIN
    process_sale(v_customer_id,v_product_id,999999,v_sale_id);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected failure: '||SQLERRM); END;
  SELECT quantity_in_stock INTO v_after FROM products WHERE sku='MS-200';
  DBMS_OUTPUT.PUT_LINE('Stock before='||v_before||', stock after='||v_after);
  IF v_before<>v_after THEN RAISE_APPLICATION_ERROR(-20999,'Failed-sale test changed stock unexpectedly.'); END IF;
END;
/
ROLLBACK;
