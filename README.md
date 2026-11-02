# SupplySense v2 — Inventory Intelligence & Decision Engine

**Database-first DBMS project** using Oracle SQL, PL/SQL, and a small Flask interface. The Oracle database is the system of record: views calculate analytics, stored procedures enforce business operations, constraints protect data, and a trigger records stock changes.

## What makes it distinctive

1. **Stockout Risk Intelligence** — calculates 30-day demand, the previous 30-day comparison, average daily units, days of stock cover, estimated stockout date, supplier lead-time exposure, risk tier, and suggested replenishment quantity.
2. **Demand & Sales Intelligence** — demand momentum, daily revenue, category performance, units sold, revenue, and estimated gross margin.
3. **Inventory Audit Engine** — an Oracle trigger writes before/after stock, delta, timestamp, and the business reason (sale, purchase receipt, manual adjustment, or baseline initialization) for each stock change. Sales, purchase receipts, and controlled adjustments all update stock through PL/SQL procedures.
4. **Transactional integrity** — foreign keys, unique keys, check constraints, row locks, savepoints, commits/rollbacks, and a pending-order validation trigger.
5. **Interactive local dashboard** — view risk-ranked products, demand signals, category performance, audit history, process a sale, receive a purchase order, or adjust stock.

### Honest scope statement

The recommendations are **explainable SQL analytics and rules**, not a trained AI/ML model. The reorder formula estimates demand during supplier lead time plus a 14-day buffer, subtracts current stock, and never returns a negative quantity. A genuine predictive model would require more complete dated sales history, validation, and model evaluation; it should not be claimed unless added and tested.

## Requirements

- Windows 10/11 x64 edition supported by the Oracle Database Free installer, administrator permission, and adequate disk space.
- Oracle Database Free 23ai/26ai (PDB service commonly `FREEPDB1`) or another Oracle 12c+ database.
- SQL Developer or SQLcl/SQL*Plus for running scripts.
- Python 3.10+ for the optional web interface.

## Installation and setup

### 1. Install Oracle Database Free

Use Oracle's official page: https://www.oracle.com/database/free/get-started/

Download the Windows x64 installer, extract the ZIP, run `setup.exe` as administrator, and set a password you can remember. Keep it private. The installer may ask for a database password; use the same password when creating the project user if you choose to reuse it, or set a separate one.

### 2. Create a dedicated project schema

Connect in SQL Developer as `SYSTEM` to service `FREEPDB1` (or your installation's PDB service). Run:

```sql
CREATE USER SUPPLYSENSE IDENTIFIED BY "Choose_A_Strong_Password_123";
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE PROCEDURE, CREATE TRIGGER, CREATE SEQUENCE TO SUPPLYSENSE;
ALTER USER SUPPLYSENSE QUOTA UNLIMITED ON USERS;
```

Replace the example password. If your database uses a tablespace other than `USERS`, adjust the quota statement. Then create a new SQL Developer connection:

- Username: `SUPPLYSENSE`
- Password: the password you set
- Host: `localhost`
- Port: `1521`
- Service name: `FREEPDB1` (not SID `FREE`, unless your installation is configured differently)

Test the connection.

### 3. Run SQL scripts in this exact order

Run each file while connected as `SUPPLYSENSE`. In SQL Developer, open a script and use **Run Script (F5)**, not just Run Statement (Ctrl+Enter), because scripts use SQL*Plus commands such as `PROMPT` and `SET SERVEROUTPUT`.

1. `sql/01_schema.sql` — tables, keys, checks, and indexes.
2. `sql/03_intelligence_views.sql` — analytical views.
3. `sql/04_plsql.sql` — triggers, functions, procedures, explicit cursor.
4. `sql/02_seed_data.sql` — demo records; this creates 10 suppliers, 10 categories, 10 products, 10 customers, 10 purchase orders and purchase lines, 15 sales and sale lines, plus initial audit events.
5. `sql/05_analytics_queries.sql` — analytical queries and report outputs.
6. `sql/06_transaction_demos.sql` — optional demos that change data. Read each prompt before running; successful sale and receipt demos commit changes.

Verify compilation after step 4:

```sql
SELECT object_name, object_type, status
FROM user_objects
WHERE object_type IN ('VIEW','FUNCTION','PROCEDURE','TRIGGER')
ORDER BY object_type, object_name;

SELECT sku, product_name, quantity_in_stock, units_30d, days_of_cover, risk_level, suggested_reorder_qty
FROM v_product_intelligence
ORDER BY CASE risk_level WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'WATCH' THEN 3 ELSE 4 END;
```

All expected view/function/procedure/trigger objects should be `VALID`. If something is `INVALID`, inspect:

```sql
SELECT name, type, line, position, text
FROM user_errors
ORDER BY name, sequence;
```

## Run the optional dashboard

From a terminal in the `app` folder:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
$env:DB_USER="SUPPLYSENSE"
$env:DB_PASSWORD="your_database_password"
$env:DB_DSN="localhost:1521/FREEPDB1"
$env:FLASK_SECRET_KEY="replace-with-a-local-random-string"
python app.py
```

Open http://127.0.0.1:5000. If PowerShell blocks activation, use `py -m pip install -r requirements.txt` and set the environment variables in the same terminal, or use Command Prompt equivalents (`.venv\\Scripts\\activate.bat`, `set DB_USER=SUPPLYSENSE`, etc.).

The Python `oracledb` driver uses thin mode by default; Oracle Instant Client is not normally required for this local setup.

## Functional test checklist

- [ ] Dashboard displays product counts, units, inventory cost, and risk tiers.
- [ ] `v_product_intelligence` returns a row for each product and shows nonzero demand for products sold in the sample period.
- [ ] `recommend_reorder_qty(product_id)` returns a nonnegative quantity.
- [ ] Process a sale of one unit of a product with stock; stock falls by one and a new audit row appears.
- [ ] Try to sell an impossible quantity; the procedure raises an error and the stock remains unchanged.
- [ ] Receive `PO-DEMO-01`; its status becomes `RECEIVED`, stock for its line increases, and audit rows appear.
- [ ] Attempt to add a line to a received order; trigger `TRG_PURCHASE_ITEM_PENDING` rejects it.
- [ ] Run `print_inventory_risk_report`; output is displayed in the DBMS Output panel.
- [ ] Adjust stock from the dashboard; new quantity and audit event appear.
- [ ] Category performance and daily sales queries return rows.

## Database design map

- `SUPPLIERS` 1—many `PRODUCTS` and `PURCHASE_ORDERS`
- `CATEGORIES` 1—many `PRODUCTS`
- `CUSTOMERS` 1—many `SALES`
- `SALES` 1—many `SALE_ITEMS`; `PRODUCTS` 1—many `SALE_ITEMS`
- `PURCHASE_ORDERS` 1—many `PURCHASE_ITEMS`; `PRODUCTS` 1—many `PURCHASE_ITEMS`
- `PRODUCTS` 1—many `INVENTORY_AUDIT`

The sale and purchase line tables resolve the many-to-many relationships. Product stock is a current balance; the audit table records changes to that balance. Seeded historical sales are analytics examples and are not replayed against the current stock snapshot.

## Viva-ready technical explanation

- **Why Oracle?** It provides relational constraints, transactions, row-level locking, PL/SQL procedures/functions, triggers, views, and SQL analytics in one DBMS.
- **Why views?** Risk and demand metrics are derived consistently from current stock, supplier lead times, and sales history; the app doesn't duplicate the calculations in Python.
- **Why `FOR UPDATE`?** Concurrent sale attempts lock the product row so two transactions cannot both validate the same stale stock quantity.
- **Why a savepoint?** If the procedure fails after starting work, it can undo its partial work while leaving the caller in control of commit/rollback.
- **Why a trigger?** The application does not have to remember to write audit rows; database stock updates automatically create audit records.
- **What is the limitation?** The demand window is short and the recommendation is a rule-based heuristic. It is useful for a DBMS demonstration but should not be represented as validated AI forecasting.

## Current verification status

The project bundle is prepared for Oracle and includes a manual test plan. This environment does not have your Oracle database installed, so database compilation and live transaction results must be verified on your machine using the checklist above. Do not report the project as deployed or tested until those checks pass.
