"""SupplySense v2 web interface. Oracle SQL/PLSQL remains the system of record."""
import os
from dotenv import load_dotenv
from decimal import Decimal

load_dotenv()
import oracledb
from flask import Flask, flash, redirect, render_template_string, request, url_for

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "change-this-local-demo-key")
DB_USER = os.getenv("DB_USER", "SUPPLYSENSE")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_DSN = os.getenv("DB_DSN", "localhost:1521/FREEPDB1")

PAGE = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SupplySense | Inventory Intelligence</title>
<style>
:root{--bg:#0b1220;--panel:#121d30;--panel2:#17243a;--line:#263650;--ink:#edf3ff;--muted:#9bacc6;--cyan:#65d7d0;--amber:#f7bd59;--red:#ff7777;--green:#8be0a5}
*{box-sizing:border-box}body{margin:0;background:radial-gradient(ellipse at top left,#142a42 0,#0b1220 45%);color:var(--ink);font:14px/1.5 Inter,Segoe UI,Arial,sans-serif}main{max-width:1440px;margin:auto;padding:28px 22px 50px}.top{display:flex;justify-content:space-between;align-items:center;gap:20px;margin-bottom:24px}.brand{display:flex;align-items:center;gap:14px}.mark{width:46px;height:46px;border-radius:14px;background:linear-gradient(135deg,#65d7d0,#4f8fff);display:grid;place-items:center;color:#071321;font-weight:900;font-size:22px}.eyebrow{text-transform:uppercase;letter-spacing:.18em;color:var(--cyan);font-size:10px;font-weight:800}.brand h1{font-size:26px;letter-spacing:-.04em;margin:0}.sub{color:var(--muted);margin:2px 0 0}.live{border:1px solid #28554f;background:#12312f;color:var(--green);padding:7px 11px;border-radius:999px;font-size:11px;white-space:nowrap}.hero{display:grid;grid-template-columns:1.5fr 1fr;gap:16px;margin-bottom:16px}.hero-card,.panel,.metric{border:1px solid var(--line);background:linear-gradient(145deg,rgba(23,36,58,.96),rgba(16,27,44,.96));border-radius:18px;box-shadow:0 14px 36px #0002}.hero-card{padding:25px;position:relative;overflow:hidden}.hero-card:after{content:"";position:absolute;width:240px;height:240px;border:1px solid #65d7d018;border-radius:50%;right:-50px;top:-90px;box-shadow:0 0 0 25px #65d7d00b,0 0 0 50px #65d7d008}.hero h2{font-size:29px;line-height:1.12;letter-spacing:-.04em;max-width:520px;margin:10px 0}.hero p{color:var(--muted);max-width:580px;margin:0}.hero-right{padding:20px;display:flex;flex-direction:column;justify-content:space-between}.mini-label{font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.12em}.big-number{font-size:34px;font-weight:750;letter-spacing:-.04em;margin-top:6px}.hero-note{font-size:12px;color:var(--muted);margin-top:10px}.metrics{display:grid;grid-template-columns:repeat(4,1fr);gap:13px;margin:16px 0}.metric{padding:18px}.metric .label{font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.1em}.metric .value{font-size:27px;font-weight:750;letter-spacing:-.04em;margin:6px 0}.metric .hint{font-size:11px;color:var(--muted)}.accent{color:var(--cyan)}.danger{color:var(--red)}.warn{color:var(--amber)}.green{color:var(--green)}.layout{display:grid;grid-template-columns:1.65fr 1fr;gap:16px}.panel{padding:19px;min-width:0;margin-bottom:16px}.panel-head{display:flex;justify-content:space-between;gap:12px;align-items:flex-start;margin-bottom:15px}.panel h3{font-size:15px;margin:0;letter-spacing:-.01em}.panel .desc{font-size:11px;color:var(--muted);margin-top:4px}.tag{font-size:10px;color:var(--cyan);border:1px solid #2a5559;background:#112b34;padding:4px 8px;border-radius:999px;white-space:nowrap}.scroll{overflow-x:auto}table{width:100%;border-collapse:collapse;white-space:nowrap;font-size:12px}th{text-align:left;font-weight:600;color:var(--muted);font-size:10px;text-transform:uppercase;letter-spacing:.08em;padding:10px 9px;border-bottom:1px solid var(--line)}td{padding:12px 9px;border-bottom:1px solid #223047}tr:last-child td{border-bottom:0}.product{font-weight:650}.sku{font-size:10px;color:var(--muted);display:block}.pill{display:inline-block;border-radius:6px;padding:4px 7px;font-size:10px;font-weight:800;letter-spacing:.04em}.CRITICAL{color:#ff9c9c;background:#49272e}.HIGH{color:#ffd17a;background:#45371e}.WATCH{color:#b6d7ff;background:#20354d}.HEALTHY{color:#9ee8b4;background:#1c3b31}.actions{display:grid;gap:13px}.formbox{border:1px solid var(--line);border-radius:12px;padding:14px;background:#0d1727}.formbox h4{margin:0 0 5px;font-size:13px}.formbox p{margin:0 0 12px;color:var(--muted);font-size:11px}.fields{display:grid;grid-template-columns:1fr 1fr;gap:9px}.field{display:flex;flex-direction:column;gap:5px}.field.full{grid-column:1/-1}label{color:var(--muted);font-size:10px}input,select{width:100%;min-width:0;background:#111f33;color:var(--ink);border:1px solid #2c405b;border-radius:8px;padding:10px;font:inherit;font-size:12px}button{border:0;border-radius:8px;padding:10px 13px;background:var(--cyan);color:#071b25;font-weight:800;font-size:11px;cursor:pointer;margin-top:10px}button:hover{filter:brightness(1.07)}.secondary{background:#243953;color:var(--ink)}.flash{border:1px solid #33546b;background:#142c40;color:#d8f4ff;padding:11px 14px;border-radius:10px;margin-bottom:12px}.flash.error{border-color:#6b3a3f;background:#321e2a;color:#ffc7c7}.empty{padding:20px;color:var(--muted);text-align:center}.foot{font-size:11px;color:var(--muted);margin-top:8px}.bar{height:6px;border-radius:99px;background:#24344b;overflow:hidden;margin-top:8px}.bar span{display:block;height:100%;background:linear-gradient(90deg,var(--cyan),#4f8fff)}@media(max-width:980px){.hero,.layout{grid-template-columns:1fr}.metrics{grid-template-columns:repeat(2,1fr)}}@media(max-width:560px){main{padding:18px 12px}.top{align-items:flex-start}.live{display:none}.metrics{gap:8px}.metric{padding:13px}.metric .value{font-size:22px}.hero h2{font-size:25px}.fields{grid-template-columns:1fr}.field.full{grid-column:auto}}
</style></head><body><main>
<header class="top"><div class="brand"><div class="mark">S</div><div><div class="eyebrow">Inventory intelligence platform</div><h1>SupplySense</h1><p class="sub">A database-first decision engine powered by Oracle SQL &amp; PL/SQL</p></div></div><div class="live">● ORACLE DATA VIEW</div></header>
{% for category,message in get_flashed_messages(with_categories=true) %}<div class="flash {{ 'error' if category=='error' else '' }}">{{message}}</div>{% endfor %}
<section class="hero"><div class="hero-card"><div class="eyebrow">From stock tracking to stock decisions</div><h2>Know what needs attention <span class="accent">before it runs out.</span></h2><p>SupplySense combines stock cover, supplier lead times, recent demand momentum and transaction-level audit history into one explainable inventory view.</p></div><div class="hero-card hero-right"><div><div class="mini-label">Most urgent recommendation</div><div class="big-number">{{ critical_count }} <span style="font-size:14px;color:var(--muted);font-weight:500">critical items</span></div><div class="hero-note">Critical = zero stock, below reorder threshold, or estimated stock cover shorter than supplier lead time.</div></div><div class="bar"><span style="width:{{ critical_pct }}%"></span></div></div></section>
<section class="metrics"><div class="metric"><div class="label">Active SKUs</div><div class="value">{{ kpis.product_count }}</div><div class="hint">Products in the catalogue</div></div><div class="metric"><div class="label">Units on hand</div><div class="value">{{ '{:,}'.format(kpis.units_in_stock or 0) }}</div><div class="hint">Current available inventory</div></div><div class="metric"><div class="label">Inventory cost value</div><div class="value">₹{{ '{:,.0f}'.format(kpis.inventory_cost_value or 0) }}</div><div class="hint">On-hand units × unit cost</div></div><div class="metric"><div class="label">Critical / High risk</div><div class="value"><span class="danger">{{ kpis.critical_count }}</span> <span style="color:var(--muted)">/</span> <span class="warn">{{ kpis.high_count }}</span></div><div class="hint">Risk based on demand and lead time</div></div></section>
<div class="layout"><div><section class="panel"><div class="panel-head"><div><h3>Stockout Risk Intelligence</h3><div class="desc">Ranked by urgency · demand window: last 30 days · previous window: 30 days before that</div></div><span class="tag">LIVE SQL VIEW</span></div><div class="scroll"><table><thead><tr><th>Product</th><th>Stock</th><th>30d demand</th><th>Cover</th><th>Risk</th><th>Suggested order</th></tr></thead><tbody>{% for p in intelligence %}<tr><td><span class="product">{{p.product_name}}</span><span class="sku">{{p.sku}}</span></td><td>{{p.quantity_in_stock}} <span style="color:var(--muted)">/ {{p.reorder_level}}</span></td><td>{{p.units_30d}} <span style="color:var(--muted)">units</span></td><td>{% if p.days_of_cover is not none %}{{p.days_of_cover}} d{% else %}—{% endif %}</td><td><span class="pill {{p.risk_level}}">{{p.risk_level}}</span></td><td>{{p.suggested_reorder_qty}}</td></tr>{% else %}<tr><td colspan="6" class="empty">No products found. Run the SQL setup scripts first.</td></tr>{% endfor %}</tbody></table></div><div class="foot">Recommendations are explainable rules based on observed sales, supplier lead time and a 14-day buffer. This is not a trained machine-learning model.</div></section>
<section class="panel"><div class="panel-head"><div><h3>Demand &amp; Category Performance</h3><div class="desc">Recent sales, revenue and estimated gross margin by category</div></div><span class="tag">ANALYTICS</span></div><div class="scroll"><table><thead><tr><th>Category</th><th>Products</th><th>Units · 30d</th><th>Revenue</th><th>Gross margin*</th></tr></thead><tbody>{% for c in categories %}<tr><td class="product">{{c.category_name}}</td><td>{{c.product_count}}</td><td>{{c.units_sold_30d}}</td><td>₹{{'{:,.0f}'.format(c.revenue_30d or 0)}}</td><td class="green">₹{{'{:,.0f}'.format(c.gross_margin_30d or 0)}}</td></tr>{% endfor %}</tbody></table></div><div class="foot">*Estimated gross margin = line revenue − current product unit cost × sold quantity.</div></section>
<section class="panel"><div class="panel-head"><div><h3>Recent Inventory Audit</h3><div class="desc">The database trigger records each actual stock quantity change</div></div><span class="tag">TRIGGER LOG</span></div><div class="scroll"><table><thead><tr><th>Product</th><th>Before</th><th>After</th><th>Δ units</th><th>Change</th><th>Time</th></tr></thead><tbody>{% for a in audits %}<tr><td class="product">{{a.product_name}}<span class="sku">{{a.sku}}</span></td><td>{{a.old_quantity}}</td><td>{{a.new_quantity}}</td><td class="{{'green' if a.quantity_delta>0 else 'danger'}}">{{'+' if a.quantity_delta>0 else ''}}{{a.quantity_delta}}</td><td>{{a.change_note}}</td><td>{{a.changed_at}}</td></tr>{% else %}<tr><td colspan="6" class="empty">No inventory changes recorded yet.</td></tr>{% endfor %}</tbody></table></div></section></div>
<aside class="actions"><section class="panel"><div class="panel-head"><div><h3>Run a transaction</h3><div class="desc">Actions call Oracle stored procedures and commit only on success</div></div></div>
<div class="formbox"><h4>Record a sale</h4><p>Locks the product row, validates stock, writes sale records, reduces stock and fires the audit trigger.</p><form method="post" action="{{url_for('sell')}}"><div class="fields"><div class="field"><label>Customer</label><select name="customer_id" required>{% for c in customers %}<option value="{{c.customer_id}}">{{c.customer_name}}</option>{% endfor %}</select></div><div class="field"><label>Product</label><select name="product_id" required>{% for p in products %}<option value="{{p.product_id}}">{{p.sku}} · {{p.product_name}} ({{p.quantity_in_stock}})</option>{% endfor %}</select></div><div class="field full"><label>Quantity</label><input name="quantity" type="number" min="1" step="1" value="1" required></div></div><button type="submit">Process sale →</button></form></div>
<div class="formbox" style="margin-top:12px"><h4>Receive a purchase order</h4><p>Receives all order lines atomically and updates stock plus audit history.</p><form method="post" action="{{url_for('receive_po')}}"><div class="field"><label>Pending order</label><select name="purchase_id" required>{% for po in pending_orders %}<option value="{{po.purchase_id}}">{{po.purchase_reference}} · {{po.supplier_name}}</option>{% endfor %}</select></div><button type="submit" class="secondary" {% if not pending_orders %}disabled{% endif %}>Receive order →</button></form></div>
<div class="formbox" style="margin-top:12px"><h4>Controlled stock adjustment</h4><p>Manual adjustments are validated in PL/SQL and captured by the audit trigger.</p><form method="post" action="{{url_for('adjust')}}"><div class="fields"><div class="field full"><label>Product</label><select name="product_id" required>{% for p in products %}<option value="{{p.product_id}}">{{p.sku}} · {{p.product_name}}</option>{% endfor %}</select></div><div class="field full"><label>New stock quantity</label><input name="new_quantity" type="number" min="0" step="1" required></div></div><button type="submit" class="secondary">Save adjustment →</button></form></div></section>
<section class="panel"><div class="panel-head"><div><h3>Demand signals</h3><div class="desc">Products with the largest recent demand changes</div></div></div><div class="scroll"><table><thead><tr><th>Product</th><th>Change</th><th>Signal</th></tr></thead><tbody>{% for p in demand_signals %}<tr><td class="product">{{p.product_name}}<span class="sku">{{p.sku}}</span></td><td class="{{'green' if (p.demand_change_pct or 0)>0 else 'danger'}}">{{'+' if (p.demand_change_pct or 0)>0 else ''}}{{p.demand_change_pct}}%</td><td>{{p.demand_signal}}</td></tr>{% endfor %}</tbody></table></div></section></aside></div>
<footer class="foot">SupplySense · Oracle is the source of truth · SQL views calculate analytics · PL/SQL procedures enforce business operations · triggers preserve inventory history.</footer>
</main></body></html>'''


def connect():
    if not DB_PASSWORD:
        raise RuntimeError("DB_PASSWORD is not set. Set DB_USER, DB_PASSWORD and DB_DSN before starting the app.")
    return oracledb.connect(user=DB_USER, password=DB_PASSWORD, dsn=DB_DSN)


def rows_as_dicts(cursor):
    names = [d[0].lower() for d in cursor.description]
    return [dict(zip(names, row)) for row in cursor.fetchall()]


def query_all(sql, binds=None):
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, binds or {})
            return rows_as_dicts(cur)


def dashboard_data():
    kpi_rows = query_all("""SELECT COUNT(*) product_count, NVL(SUM(quantity_in_stock),0) units_in_stock,
      NVL(SUM(quantity_in_stock*unit_cost),0) inventory_cost_value,
      NVL(SUM(CASE WHEN risk_level='CRITICAL' THEN 1 ELSE 0 END),0) critical_count,
      NVL(SUM(CASE WHEN risk_level='HIGH' THEN 1 ELSE 0 END),0) high_count
      FROM v_product_intelligence""")
    kpis = kpi_rows[0]
    intelligence = query_all("""SELECT product_id,product_name,sku,quantity_in_stock,reorder_level,units_30d,
      days_of_cover,risk_level,suggested_reorder_qty FROM v_product_intelligence
      ORDER BY CASE risk_level WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'WATCH' THEN 3 ELSE 4 END,
      days_of_cover NULLS LAST, product_name""")
    categories = query_all("SELECT category_name,product_count,units_sold_30d,revenue_30d,gross_margin_30d FROM v_category_performance ORDER BY revenue_30d DESC, category_name")
    audits = query_all("""SELECT p.product_name,p.sku,a.old_quantity,a.new_quantity,a.quantity_delta,a.change_note,
      TO_CHAR(a.changed_at,'YYYY-MM-DD HH24:MI:SS') changed_at FROM inventory_audit a
      JOIN products p ON p.product_id=a.product_id ORDER BY a.changed_at DESC FETCH FIRST 8 ROWS ONLY""")
    products = query_all("SELECT product_id,product_name,sku,quantity_in_stock FROM products ORDER BY product_name")
    customers = query_all("SELECT customer_id,customer_name FROM customers ORDER BY customer_name")
    pending_orders = query_all("""SELECT po.purchase_id,po.purchase_reference,s.supplier_name FROM purchase_orders po
      JOIN suppliers s ON s.supplier_id=po.supplier_id WHERE po.status='PENDING' ORDER BY po.order_date""")
    demand_signals = query_all("""SELECT product_name,sku,demand_change_pct,demand_signal FROM v_product_intelligence
      ORDER BY demand_change_pct DESC FETCH FIRST 5 ROWS ONLY""")
    return {"kpis": kpis, "intelligence": intelligence, "categories": categories, "audits": audits,
            "products": products, "customers": customers, "pending_orders": pending_orders,
            "demand_signals": demand_signals}


@app.get("/")
def index():
    try:
        data = dashboard_data()
        data["critical_count"] = data["kpis"]["critical_count"]
        data["critical_pct"] = min(100, round(data["kpis"]["critical_count"] * 100 / max(data["kpis"]["product_count"], 1)))
        return render_template_string(PAGE, **data)
    except Exception:
        app.logger.exception("SupplySense dashboard load failed")
        return ("<h2>SupplySense could not load from Oracle</h2><p>Check that Oracle is running, "
                "the SUPPLYSENSE schema is selected, setup scripts ran in order, and DB_USER / "
                "DB_PASSWORD / DB_DSN are correct.</p><p>See README.md for setup steps. Full details are in the terminal log.</p>"), 500


@app.post("/sell")
def sell():
    try:
        customer_id = int(request.form["customer_id"])
        product_id = int(request.form["product_id"])
        quantity = int(request.form["quantity"])
        with connect() as conn:
            try:
                with conn.cursor() as cur:
                    out_id = cur.var(oracledb.NUMBER)
                    cur.callproc("PROCESS_SALE", [customer_id, product_id, quantity, out_id])
                    sale_id = int(out_id.getvalue())
                conn.commit()
            except Exception:
                conn.rollback()
                raise
        flash(f"Sale #{sale_id} completed in Oracle. Stock and audit history were updated.", "success")
    except Exception as exc:
        flash(f"Sale not completed: {exc}", "error")
    return redirect(url_for("index"))


@app.post("/receive-po")
def receive_po():
    try:
        purchase_id = int(request.form["purchase_id"])
        with connect() as conn:
            try:
                with conn.cursor() as cur:
                    cur.callproc("RECEIVE_PURCHASE_ORDER", [purchase_id])
                conn.commit()
            except Exception:
                conn.rollback()
                raise
        flash("Purchase order received. Stock, order status and audit history were updated.", "success")
    except Exception as exc:
        flash(f"Purchase order was not received: {exc}", "error")
    return redirect(url_for("index"))


@app.post("/adjust")
def adjust():
    try:
        product_id = int(request.form["product_id"])
        new_quantity = int(request.form["new_quantity"])
        with connect() as conn:
            try:
                with conn.cursor() as cur:
                    cur.callproc("ADJUST_STOCK", [product_id, new_quantity])
                conn.commit()
            except Exception:
                conn.rollback()
                raise
        flash("Stock adjustment saved. The database audit trigger recorded the change.", "success")
    except Exception as exc:
        flash(f"Stock adjustment was not saved: {exc}", "error")
    return redirect(url_for("index"))


if __name__ == "__main__":
    # Debug is deliberately disabled by default; this is a local academic demo.
    app.run(host="127.0.0.1", port=int(os.getenv("PORT", "5000")), debug=False)
