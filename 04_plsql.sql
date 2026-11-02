SET SERVEROUTPUT ON

-- Package-level transaction context lets the trigger record the business reason for a stock movement.
CREATE OR REPLACE PACKAGE inventory_context_pkg AS
  PROCEDURE set_change_note(p_note IN VARCHAR2);
  FUNCTION get_change_note RETURN VARCHAR2;
END inventory_context_pkg;
/
CREATE OR REPLACE PACKAGE BODY inventory_context_pkg AS
  g_change_note VARCHAR2(250) := 'Stock quantity changed';
  PROCEDURE set_change_note(p_note IN VARCHAR2) IS
  BEGIN
    g_change_note := SUBSTR(NVL(p_note,'Stock quantity changed'),1,250);
  END;
  FUNCTION get_change_note RETURN VARCHAR2 IS
  BEGIN
    RETURN g_change_note;
  END;
END inventory_context_pkg;
/

-- Trigger 1: every inventory quantity change is written to an audit trail with its business reason.
CREATE OR REPLACE TRIGGER trg_inventory_audit
AFTER UPDATE OF quantity_in_stock ON products
FOR EACH ROW
WHEN (OLD.quantity_in_stock <> NEW.quantity_in_stock)
BEGIN
  INSERT INTO inventory_audit(product_id,old_quantity,new_quantity,quantity_delta,change_note)
  VALUES (:NEW.product_id,:OLD.quantity_in_stock,:NEW.quantity_in_stock,
          :NEW.quantity_in_stock-:OLD.quantity_in_stock,inventory_context_pkg.get_change_note());
END;
/

-- Trigger 2: purchase lines may only be changed while their parent order is pending.
CREATE OR REPLACE TRIGGER trg_purchase_item_pending
BEFORE INSERT OR UPDATE OF purchase_id,product_id,quantity,unit_cost ON purchase_items
FOR EACH ROW
DECLARE v_status purchase_orders.status%TYPE;
BEGIN
  SELECT status INTO v_status FROM purchase_orders WHERE purchase_id=:NEW.purchase_id;
  IF v_status <> 'PENDING' THEN
    RAISE_APPLICATION_ERROR(-20020,'Purchase items can only be changed while the purchase order is PENDING.');
  END IF;
END;
/

-- Function 1: stock lookup for application and SQL callers.
CREATE OR REPLACE FUNCTION get_stock(p_product_id IN products.product_id%TYPE)
RETURN NUMBER IS v_stock products.quantity_in_stock%TYPE;
BEGIN
  SELECT quantity_in_stock INTO v_stock FROM products WHERE product_id=p_product_id;
  RETURN v_stock;
EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20001,'Product ID not found.');
END;
/

-- Function 2: analytics-driven replenishment suggestion; a rule, not a trained ML model.
CREATE OR REPLACE FUNCTION recommend_reorder_qty(p_product_id IN products.product_id%TYPE)
RETURN NUMBER IS v_qty NUMBER;
BEGIN
  SELECT suggested_reorder_qty INTO v_qty FROM v_product_intelligence WHERE product_id=p_product_id;
  RETURN v_qty;
EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20002,'Product ID not found.');
END;
/

-- Procedure 1: sell one product with row locking and a savepoint. Caller commits on success.
CREATE OR REPLACE PROCEDURE process_sale(
  p_customer_id IN sales.customer_id%TYPE,
  p_product_id IN products.product_id%TYPE,
  p_quantity IN NUMBER,
  p_sale_id OUT sales.sale_id%TYPE
) IS
  v_stock products.quantity_in_stock%TYPE;
  v_price products.unit_price%TYPE;
  v_reference VARCHAR2(30);
BEGIN
  SAVEPOINT process_sale_start;
  IF p_quantity IS NULL OR p_quantity<=0 THEN RAISE_APPLICATION_ERROR(-20003,'Sale quantity must be greater than zero.'); END IF;
  SELECT quantity_in_stock,unit_price INTO v_stock,v_price FROM products WHERE product_id=p_product_id FOR UPDATE;
  IF v_stock<p_quantity THEN RAISE_APPLICATION_ERROR(-20004,'Insufficient stock. Sale was not completed.'); END IF;
  v_reference := 'APP-'||TO_CHAR(SYSTIMESTAMP,'YYMMDDHH24MISSFF3');
  INSERT INTO sales(sale_reference,customer_id,total_amount) VALUES(v_reference,p_customer_id,v_price*p_quantity)
  RETURNING sale_id INTO p_sale_id;
  INSERT INTO sale_items(sale_id,product_id,quantity,unit_price) VALUES(p_sale_id,p_product_id,p_quantity,v_price);
  inventory_context_pkg.set_change_note('Sale '||v_reference);
  UPDATE products SET quantity_in_stock=quantity_in_stock-p_quantity WHERE product_id=p_product_id;
  inventory_context_pkg.set_change_note('Stock quantity changed');
EXCEPTION WHEN OTHERS THEN
  inventory_context_pkg.set_change_note('Stock quantity changed');
  ROLLBACK TO process_sale_start;
  RAISE;
END;
/

-- Procedure 2: receive all lines on a pending PO atomically.
CREATE OR REPLACE PROCEDURE receive_purchase_order(p_purchase_id IN purchase_orders.purchase_id%TYPE)
IS
  v_status purchase_orders.status%TYPE;
  v_reference purchase_orders.purchase_reference%TYPE;
  v_count NUMBER;
BEGIN
  SAVEPOINT receive_po_start;
  SELECT status,purchase_reference INTO v_status,v_reference FROM purchase_orders WHERE purchase_id=p_purchase_id FOR UPDATE;
  IF v_status<>'PENDING' THEN RAISE_APPLICATION_ERROR(-20005,'Only PENDING purchase orders can be received.'); END IF;
  SELECT COUNT(*) INTO v_count FROM purchase_items WHERE purchase_id=p_purchase_id;
  IF v_count=0 THEN RAISE_APPLICATION_ERROR(-20006,'Purchase order has no line items.'); END IF;
  FOR item IN (SELECT product_id,quantity FROM purchase_items WHERE purchase_id=p_purchase_id) LOOP
    inventory_context_pkg.set_change_note('Purchase receipt '||v_reference);
    UPDATE products SET quantity_in_stock=quantity_in_stock+item.quantity WHERE product_id=item.product_id;
    inventory_context_pkg.set_change_note('Stock quantity changed');
  END LOOP;
  UPDATE purchase_orders SET status='RECEIVED' WHERE purchase_id=p_purchase_id;
EXCEPTION WHEN OTHERS THEN
  inventory_context_pkg.set_change_note('Stock quantity changed');
  ROLLBACK TO receive_po_start;
  RAISE;
END;
/

-- Procedure 3: controlled manual stock adjustment; audit trigger records the change.
CREATE OR REPLACE PROCEDURE adjust_stock(
  p_product_id IN products.product_id%TYPE,
  p_new_quantity IN NUMBER
) IS
BEGIN
  IF p_new_quantity IS NULL OR p_new_quantity<0 OR p_new_quantity<>TRUNC(p_new_quantity) THEN
    RAISE_APPLICATION_ERROR(-20030,'New stock must be a non-negative whole number.');
  END IF;
  inventory_context_pkg.set_change_note('Manual stock adjustment');
  UPDATE products SET quantity_in_stock=p_new_quantity WHERE product_id=p_product_id;
  inventory_context_pkg.set_change_note('Stock quantity changed');
  IF SQL%ROWCOUNT=0 THEN RAISE_APPLICATION_ERROR(-20031,'Product ID not found.'); END IF;
EXCEPTION WHEN OTHERS THEN
  inventory_context_pkg.set_change_note('Stock quantity changed');
  RAISE;
END;
/

-- Explicit cursor requirement: prints the highest-priority inventory risks.
CREATE OR REPLACE PROCEDURE print_inventory_risk_report IS
  CURSOR c_risk IS
    SELECT sku,product_name,quantity_in_stock,reorder_level,risk_level,days_of_cover,suggested_reorder_qty
    FROM v_product_intelligence
    WHERE risk_level IN ('CRITICAL','HIGH')
    ORDER BY CASE risk_level WHEN 'CRITICAL' THEN 1 ELSE 2 END, days_of_cover NULLS LAST;
  v_count NUMBER:=0;
BEGIN
  DBMS_OUTPUT.PUT_LINE('SUPPLYSENSE INVENTORY RISK REPORT');
  FOR r IN c_risk LOOP
    v_count:=v_count+1;
    DBMS_OUTPUT.PUT_LINE(r.sku||' | '||r.product_name||' | stock='||r.quantity_in_stock||' | risk='||r.risk_level||' | cover='||NVL(TO_CHAR(r.days_of_cover),'N/A')||' days | suggested order='||r.suggested_reorder_qty);
  END LOOP;
  IF v_count=0 THEN DBMS_OUTPUT.PUT_LINE('No critical/high-risk products at this time.'); END IF;
END;
/

PROMPT SupplySense PL/SQL objects created.
