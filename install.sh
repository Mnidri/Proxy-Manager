#!/bin/bash

# ==========================================
# X-UI Proxy Manager Auto Installer
# ==========================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=================================================${NC}"
echo -e "${GREEN}      X-UI Proxy Manager Auto Installer          ${NC}"
echo -e "${CYAN}=================================================${NC}"

# ۱. دریافت اطلاعات به صورت تعاملی
read -p "1. Enter Telegram Bot Token: " BOT_TOKEN

read -p "2. Enter Web Panel Username [admin]: " PANEL_USER
PANEL_USER=${PANEL_USER:-admin}

read -p "3. Enter Web Panel Password [admin123]: " PANEL_PASS
PANEL_PASS=${PANEL_PASS:-admin123}

# پیشنهاد یک پورت رندوم برای امنیت بیشتر
RANDOM_PORT=$(shuf -i 10000-60000 -n 1)
read -p "4. Enter Web Panel Port [$RANDOM_PORT]: " PANEL_PORT
PANEL_PORT=${PANEL_PORT:-$RANDOM_PORT}

echo -e "\n${GREEN}[+] Starting Installation & Updating OS...${NC}"
apt update && apt install -y python3 python3-venv sqlite3 curl

# ۲. ایجاد محیط پروژه
INSTALL_DIR="/opt/proxy-manager"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

echo "[+] Setting up Python Virtual Environment..."
python3 -m venv panel_env
source panel_env/bin/activate
pip install fastapi uvicorn pydantic aiogram aiohttp python-multipart > /dev/null 2>&1

# ۳. ایجاد فایل main.py دقیقا بر اساس سورس نهایی شما
echo "[+] Creating main.py..."
cat << 'EOF' > main.py
import os
import shutil
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.responses import HTMLResponse, FileResponse
from pydantic import BaseModel
from typing import Optional, List
import sqlite3
import uvicorn
import datetime

app = FastAPI(title="X-UI Proxy Panel Manager")

def get_db():
    conn = sqlite3.connect('panel_database.db')
    conn.row_factory = sqlite3.Row
    return conn

def setup_database():
    conn = get_db(); cursor = conn.cursor()
    cursor.execute('''CREATE TABLE IF NOT EXISTS stores (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, inbound_port INTEGER, prefix TEXT, counter INTEGER)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS packages (id INTEGER PRIMARY KEY AUTOINCREMENT, store_id INTEGER, name TEXT, volume INTEGER, days INTEGER, suffix TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, chat_id TEXT, owner_name TEXT, allowed_stores TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS configs_log (id INTEGER PRIMARY KEY AUTOINCREMENT, store_id INTEGER, package_name TEXT, volume INTEGER, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS settings (id INTEGER PRIMARY KEY AUTOINCREMENT, vpn_config TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS panels (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, xui_url TEXT, xui_user TEXT, xui_pass TEXT)''')
    
    # ارتقای اتوماتیک دیتابیس بدون پاک شدن اطلاعات قبلی
    try:
        cursor.execute("SELECT panel_id FROM stores LIMIT 1")
    except sqlite3.OperationalError:
        cursor.execute("ALTER TABLE stores ADD COLUMN panel_id INTEGER DEFAULT 0")
        try:
            cursor.execute("SELECT xui_url, xui_user, xui_pass FROM settings LIMIT 1")
            old_setting = cursor.fetchone()
            if old_setting and 'xui_url' in old_setting.keys() and old_setting['xui_url']:
                cursor.execute("INSERT INTO panels (name, xui_url, xui_user, xui_pass) VALUES (?, ?, ?, ?)", 
                              ("سرور اصلی", old_setting['xui_url'], old_setting['xui_user'], old_setting['xui_pass']))
                cursor.execute("UPDATE stores SET panel_id = (SELECT id FROM panels LIMIT 1)")
        except Exception:
            pass

    conn.commit(); conn.close()

setup_database()

class PanelCreate(BaseModel): name: str; xui_url: str; xui_user: str; xui_pass: str
class StoreCreate(BaseModel): name: str; panel_id: int; inbound_port: int; prefix: Optional[str] = ""; counter: int
class PackageCreate(BaseModel): store_id: int; name: str; volume: int; days: int; suffix: Optional[str] = ""
class UserCreate(BaseModel): chat_id: str; owner_name: str; allowed_stores: List[int]
class SettingsUpdate(BaseModel): vpn_config: Optional[str] = ""

# --- Backup & Restore ---
@app.get("/api/backup")
def download_backup():
    file_name = f"panel_backup_{datetime.datetime.now().strftime('%Y%m%d_%H%M')}.db"
    return FileResponse("panel_database.db", media_type="application/octet-stream", filename=file_name)

@app.post("/api/restore")
async def restore_backup(file: UploadFile = File(...)):
    with open("panel_database.db", "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"status": "success"}

# --- Stats ---
@app.get("/api/stats")
def get_stats():
    conn = get_db(); cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM stores")
    stores_count = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM configs_log")
    total_configs = cursor.fetchone()[0]
    cursor.execute('''SELECT stores.name, COUNT(configs_log.id) as config_count FROM stores LEFT JOIN configs_log ON stores.id = configs_log.store_id GROUP BY stores.id''')
    store_stats = [dict(row) for row in cursor.fetchall()]
    server_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn.close()
    return {"total_configs": total_configs, "active_stores": stores_count, "store_stats": store_stats, "server_time": server_time}

# --- Panels (Servers) ---
@app.get("/api/panels")
def get_panels():
    conn = get_db(); cursor = conn.cursor()
    cursor.execute("SELECT * FROM panels ORDER BY id DESC")
    rows = cursor.fetchall(); conn.close()
    return [dict(row) for row in rows]

@app.post("/api/panels")
def create_panel(panel: PanelCreate):
    conn = get_db(); cursor = conn.cursor()
    cursor.execute("INSERT INTO panels (name, xui_url, xui_user, xui_pass) VALUES (?, ?, ?, ?)", (panel.name, panel.xui_url, panel.xui_user, panel.xui_pass))
    conn.commit(); conn.close()
    return {"status": "success"}

@app.put("/api/panels/{item_id}")
def update_panel(item_id: int, panel: PanelCreate):
    conn = get_db(); cursor = conn.cursor()
    cursor.execute("UPDATE panels SET name=?, xui_url=?, xui_user=?, xui_pass=? WHERE id=?", (panel.name, panel.xui_url, panel.xui_user, panel.xui_pass, item_id))
    conn.commit(); conn.close()
    return {"status": "success"}

@app.delete("/api/panels/{item_id}")
def delete_panel(item_id: int):
    conn = get_db(); cursor = conn.cursor()
    cursor.execute("DELETE FROM panels WHERE id = ?", (item_id,))
    conn.commit(); conn.close()
    return {"status": "success"}

# --- Settings ---
@app.post("/api/settings")
def update_settings(settings: SettingsUpdate):
    conn = get_db(); cursor = conn.cursor()
    try:
        cursor.execute("UPDATE settings SET vpn_config=? WHERE id=(SELECT id FROM settings LIMIT 1)", (settings.vpn_config,))
        if cursor.rowcount == 0:
            cursor.execute("INSERT INTO settings (vpn_config) VALUES (?)", (settings.vpn_config,))
    except:
        pass
    conn.commit(); conn.close()
    return {"status": "success"}

@app.get("/api/settings")
def get_settings():
    conn = get_db(); cursor = conn.cursor()
    try:
        cursor.execute("SELECT vpn_config FROM settings LIMIT 1")
        row = cursor.fetchone()
        conn.close()
        return dict(row) if row else {}
    except:
        conn.close()
        return {}

# --- Other APIs (Stores, Packages, Users, Reports) ---
@app.get("/api/reports")
def get_reports(store_id: int, start_date: str, end_date: str):
    conn = get_db(); cursor = conn.cursor()
    cursor.execute('''SELECT package_name, COUNT(*) as count FROM configs_log WHERE store_id = ? AND created_at >= ? AND created_at <= ? GROUP BY package_name''', (store_id, start_date, end_date))
    rows = cursor.fetchall(); conn.close()
    return [dict(row) for row in rows]

@app.post("/api/stores")
def create_store(store: StoreCreate):
    conn = get_db(); cursor = conn.cursor()
    cursor.execute("INSERT INTO stores (name, panel_id, inbound_port, prefix, counter) VALUES (?, ?, ?, ?, ?)", (store.name, store.panel_id, store.inbound_port, store.prefix, store.counter))
    conn.commit(); conn.close()
    return {"status": "success"}

@app.put("/api/stores/{item_id}")
def update_store(item_id: int, store: StoreCreate):
    conn = get_db(); cursor = conn.cursor()
    cursor.execute("UPDATE stores SET name=?, panel_id=?, inbound_port=?, prefix=?, counter=? WHERE id=?", (store.name, store.panel_id, store.inbound_port, store.prefix, store.counter, item_id))
    conn.commit(); conn.close()
    return {"status": "success"}

@app.get("/api/stores")
def get_stores():
    conn = get_db(); cursor = conn.cursor()
    cursor.execute('''SELECT stores.*, panels.name as panel_name FROM stores LEFT JOIN panels ON stores.panel_id = panels.id ORDER BY stores.id DESC''')
    rows = cursor.fetchall(); conn.close()
    return [dict(row) for row in rows]

@app.delete("/api/stores/{item_id}")
def delete_store(item_id: int):
    conn = get_db(); cursor = conn.cursor()
    cursor.execute("DELETE FROM stores WHERE id = ?", (item_id,))
    conn.commit(); conn.close()
    return {"status": "success"}

@app.post("/api/packages")
def create_package(pkg: PackageCreate):
    conn = get_db(); cursor = conn.cursor()
    cursor.execute("INSERT INTO packages (store_id, name, volume, days, suffix) VALUES (?, ?, ?, ?, ?)", (pkg.store_id, pkg.name, pkg.volume, pkg.days, pkg.suffix))
    conn.commit(); conn.close()
    return {"status": "success"}

@app.put("/api/packages/{item_id}")
def update_package(item_id: int, pkg: PackageCreate):
    conn = get_db(); cursor = conn.cursor()
    cursor.execute("UPDATE packages SET store_id=?, name=?, volume=?, days=?, suffix=? WHERE id=?", (pkg.store_id, pkg.name, pkg.volume, pkg.days, pkg.suffix, item_id))
    conn.commit(); conn.close()
    return {"status": "success"}

@app.get("/api/packages")
def get_packages():
    conn = get_db(); cursor = conn.cursor()
    cursor.execute("SELECT packages.*, stores.name as store_name FROM packages LEFT JOIN stores ON packages.store_id = stores.id ORDER BY packages.id DESC")
    rows = cursor.fetchall(); conn.close()
    return [dict(row) for row in rows]

@app.delete("/api/packages/{item_id}")
def delete_package(item_id: int):
    conn = get_db(); cursor = conn.cursor()
    cursor.execute("DELETE FROM packages WHERE id = ?", (item_id,))
    conn.commit(); conn.close()
    return {"status": "success"}

@app.post("/api/users")
def create_user(user: UserCreate):
    conn = get_db(); cursor = conn.cursor()
    stores_str = ",".join(map(str, user.allowed_stores))
    cursor.execute("INSERT INTO users (chat_id, owner_name, allowed_stores) VALUES (?, ?, ?)", (user.chat_id, user.owner_name, stores_str))
    conn.commit(); conn.close()
    return {"status": "success"}

@app.get("/api/users")
def get_users():
    conn = get_db(); cursor = conn.cursor()
    cursor.execute("SELECT * FROM users ORDER BY id DESC")
    rows = cursor.fetchall(); conn.close()
    return [dict(row) for row in rows]

@app.delete("/api/users/{item_id}")
def delete_user(item_id: int):
    conn = get_db(); cursor = conn.cursor()
    cursor.execute("DELETE FROM users WHERE id = ?", (item_id,))
    conn.commit(); conn.close()
    return {"status": "success"}

@app.get("/", response_class=HTMLResponse)
async def serve_panel():
    with open("panel.html", "r", encoding="utf-8") as f: return f.read()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=__PORT__)
EOF

# ۴. ایجاد فایل bot.py دقیقا بر اساس سورس نهایی شما
echo "[+] Creating bot.py..."
cat << 'EOF' > bot.py
import asyncio
import sqlite3
import datetime
import time
import json
import uuid
import aiohttp
import urllib.parse
from urllib.parse import urlparse
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import CommandStart
from aiogram.utils.keyboard import InlineKeyboardBuilder
from aiogram.types import ReplyKeyboardMarkup, KeyboardButton

BOT_TOKEN = "__BOT_TOKEN__"

bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()

def get_db():
    conn = sqlite3.connect('panel_database.db')
    conn.row_factory = sqlite3.Row
    return conn

def build_vless_link(client_uuid, default_ip, inbound_port, stream_settings, remark):
    net = stream_settings.get("network", "tcp")
    sec = stream_settings.get("security", "none")
    
    # مدیریت آی‌پی‌های تمیز (External Proxy) در سنایی
    ext_proxies = stream_settings.get("externalProxy", [])
    server_ip = default_ip
    port = inbound_port
    if ext_proxies and len(ext_proxies) > 0:
        server_ip = ext_proxies[0].get("dest", default_ip)
        port = ext_proxies[0].get("port", inbound_port)
        
    params = {"type": net, "security": sec}
    
    # تنظیمات TLS و Reality
    if sec == "tls":
        tls = stream_settings.get("tlsSettings", {})
        if tls.get("serverName"): params["sni"] = tls.get("serverName")
        if tls.get("fingerprint"): params["fp"] = tls.get("fingerprint")
        if tls.get("alpn"):
            alpn = tls.get("alpn")
            params["alpn"] = ",".join(alpn) if isinstance(alpn, list) else alpn
    elif sec == "reality":
        rs = stream_settings.get("realitySettings", {})
        if rs.get("serverName"): params["sni"] = rs.get("serverName")
        if rs.get("fingerprint"): params["fp"] = rs.get("fingerprint")
        if rs.get("publicKey"): params["pbk"] = rs.get("publicKey")
        if rs.get("shortId"): params["sid"] = rs.get("shortId")
        if rs.get("spiderX"): params["spx"] = rs.get("spiderX")
        
    # تنظیمات شبکه‌های مختلف
    if net == "ws":
        ws = stream_settings.get("wsSettings", {})
        if ws.get("path"): params["path"] = ws.get("path")
        if ws.get("headers", {}).get("Host"): params["host"] = ws.get("headers").get("Host")
        elif ws.get("host"): params["host"] = ws.get("host")
    elif net == "grpc":
        grpc = stream_settings.get("grpcSettings", {})
        if grpc.get("serviceName"): params["serviceName"] = grpc.get("serviceName")
        if grpc.get("multiMode"): params["mode"] = "multi"
    elif net == "tcp":
        tcp = stream_settings.get("tcpSettings", {})
        header = tcp.get("header", {})
        if header.get("type"): params["headerType"] = header.get("type")
        if header.get("type") == "http":
            req = header.get("request", {})
            if req.get("path"): params["path"] = ",".join(req.get("path")) if isinstance(req.get("path"), list) else req.get("path")
            if req.get("headers", {}).get("Host"): params["host"] = ",".join(req.get("headers")["Host"]) if isinstance(req.get("headers")["Host"], list) else req.get("headers")["Host"]
            
    query = urllib.parse.urlencode(params, safe="=,/")
    encoded_remark = urllib.parse.quote(remark)
    
    return f"vless://{client_uuid}@{server_ip}:{port}?{query}#{encoded_remark}"

async def create_xui_client(url, user, pwd, port, prefix, suffix, volume_gb, days, start_counter):
    url = url.rstrip('/') 
    parsed_url = urlparse(url)
    server_ip_or_domain = parsed_url.hostname 
    
    async with aiohttp.ClientSession() as session:
        # ۱. لاگین
        login_resp = await session.post(f"{url}/login", data={"username": user, "password": pwd})
        login_text = await login_resp.text()
        try:
            if not json.loads(login_text).get("success"): return False, "❌ لاگین ناموفق به سرور"
        except Exception: return False, "❌ آدرس سرور در پنل اشتباه است."

        raw_cookies = login_resp.headers.getall('Set-Cookie', [])
        cookie_header = "; ".join([rc.split(';')[0] for rc in raw_cookies])
        headers = {"Accept": "application/json", "Cookie": cookie_header}

        # ۲. استخراج تنظیمات سابسکریپشن به صورت کاملا سیال و داینامیک
        sub_settings = {}
        settings_resp = await session.post(f"{url}/panel/setting/all", headers=headers)
        if settings_resp.status == 404: settings_resp = await session.get(f"{url}/panel/setting/all", headers=headers)
        try:
            settings_data = await settings_resp.json()
            sub_settings = settings_data.get("obj", {})
        except: pass

        # ۳. دریافت اطلاعات پورت‌ها و اکانت‌ها
        inbounds_resp = await session.get(f"{url}/panel/api/inbounds/list", headers=headers)
        if inbounds_resp.status != 200: return False, "❌ خطا در دریافت پورت‌ها"
        
        inbounds_data = await inbounds_resp.json()
        target_inbound = None
        all_existing_remarks = []
        
        for inbound in inbounds_data.get("obj", []):
            if str(inbound.get("port")) == str(port):
                target_inbound = inbound
            try:
                for client in json.loads(inbound.get("settings", "{}")).get("clients", []):
                    all_existing_remarks.append(client.get("email", ""))
            except: pass
                
        if not target_inbound: return False, f"❌ پورت {port} در سرور پیدا نشد!"

        # ۴. شمارنده هوشمند
        current_counter = start_counter
        while True:
            remark = f"{prefix}{suffix}{current_counter}"
            if remark not in all_existing_remarks: break
            current_counter += 1

        client_uuid = str(uuid.uuid4())
        sub_id = str(uuid.uuid4())[:16]
        total_bytes = int(volume_gb) * 1073741824 if volume_gb > 0 else 0
        expiry_time = -(days * 86400 * 1000) if days > 0 else 0
        
        new_client = {
            "id": client_uuid, "alterId": 0, "email": remark, "limitIp": 0,
            "totalGB": total_bytes, "expiryTime": expiry_time, "enable": True, "subId": sub_id
        }
        
        # ۵. ارسال دستور ساخت
        payload = {"id": target_inbound["id"], "settings": json.dumps({"clients": [new_client]})}
        add_resp = await session.post(f"{url}/panel/api/inbounds/addClient", json=payload, headers=headers)
        add_text = await add_resp.text()
        
        if json.loads(add_text).get("success"):
            # ۶. ساخت لینک سابسکریپشن دقیقاً بر اساس تنظیمات سرور
            sub_domain = sub_settings.get("subDomain", "") or server_ip_or_domain
            sub_port = sub_settings.get("subPort", "")
            sub_path = sub_settings.get("subPath", "/sub/")
            
            # تشخیص پروتکل بر اساس پورت‌های رایج کلودفلر/HTTPS
            proto = "https" if str(sub_port) in ["443", "2053", "2083", "2096", "8443"] else "http"
            port_str = "" if str(sub_port) in ["80", "443", ""] else f":{sub_port}"
            if not sub_path.startswith('/'): sub_path = '/' + sub_path
            if not sub_path.endswith('/'): sub_path = sub_path + '/'
            
            sub_link = f"{proto}://{sub_domain}{port_str}{sub_path}{sub_id}"

            # ۷. مونتاژ کانفیگ خام VLESS دقیقا مثل خود سنایی
            try:
                stream_settings = json.loads(target_inbound.get("streamSettings", "{}"))
            except:
                stream_settings = {}
                
            actual_config = build_vless_link(client_uuid, server_ip_or_domain, port, stream_settings, remark)
            
            return True, {"sub_link": sub_link, "actual_config": actual_config, "new_counter": current_counter}
        else:
            return False, "❌ خطا در ساخت کلاینت روی سرور"

main_keyboard = ReplyKeyboardMarkup(keyboard=[[KeyboardButton(text="🛒 سفارش جدید")], [KeyboardButton(text="📊 گزارش کارکرد"), KeyboardButton(text="🔄 راه‌اندازی مجدد")]], resize_keyboard=True)

@dp.message(CommandStart())
@dp.message(F.text == "🔄 راه‌اندازی مجدد")
async def cmd_start(message: types.Message):
    chat_id = str(message.chat.id)
    conn = get_db()
    user = conn.execute("SELECT * FROM users WHERE chat_id=?", (chat_id,)).fetchone()
    conn.close()
    if not user:
        await message.answer("⛔️ شما دسترسی لازم را ندارید.", reply_markup=types.ReplyKeyboardRemove())
        return
    await message.answer(f"سلام {user['owner_name']} عزیز!\nاز منوی پایین انتخاب کنید 👇", reply_markup=main_keyboard)

@dp.message(F.text == "🛒 سفارش جدید")
async def new_order(message: types.Message):
    chat_id = str(message.chat.id)
    conn = get_db()
    user = conn.execute("SELECT * FROM users WHERE chat_id=?", (chat_id,)).fetchone()
    if not user: return conn.close()
    
    allowed_stores = user['allowed_stores'].split(',') if user['allowed_stores'] else []
    builder = InlineKeyboardBuilder()
    for store_id in allowed_stores:
        if store_id:
            store = conn.execute("SELECT * FROM stores WHERE id=?", (store_id,)).fetchone()
            if store: builder.button(text=f"🏪 {store['name']}", callback_data=f"store_{store['id']}")
    builder.adjust(1)
    await message.answer("لطفاً فروشگاه را انتخاب کنید:", reply_markup=builder.as_markup())
    conn.close()

@dp.callback_query(F.data.startswith("store_"))
async def show_packages(callback: types.CallbackQuery):
    store_id = callback.data.split("_")[1]
    conn = get_db()
    store = conn.execute("SELECT * FROM stores WHERE id=?", (store_id,)).fetchone()
    packages = conn.execute("SELECT * FROM packages WHERE store_id=?", (store_id,)).fetchall()
    conn.close()
    builder = InlineKeyboardBuilder()
    for pkg in packages: builder.button(text=f"📦 {pkg['name']} ({pkg['volume']}GB)", callback_data=f"pkg_{pkg['id']}")
    builder.adjust(1)
    await callback.message.edit_text(f"فروشگاه: {store['name']}\nلطفاً پکیج را انتخاب کنید:", reply_markup=builder.as_markup())

@dp.callback_query(F.data.startswith("pkg_"))
async def ask_quantity(callback: types.CallbackQuery):
    pkg_id = callback.data.split("_")[1]
    builder = InlineKeyboardBuilder()
    builder.button(text="۱ عدد", callback_data=f"qty_{pkg_id}_1")
    builder.button(text="۵ عدد", callback_data=f"qty_{pkg_id}_5")
    builder.button(text="۱۰ عدد", callback_data=f"qty_{pkg_id}_10")
    builder.adjust(3)
    await callback.message.edit_text("تعداد کانفیگ مورد نیاز را انتخاب کنید:", reply_markup=builder.as_markup())

@dp.callback_query(F.data.startswith("qty_"))
async def generate_configs(callback: types.CallbackQuery):
    _, pkg_id, qty = callback.data.split("_")
    qty = int(qty)
    conn = get_db()
    
    pkg = conn.execute("SELECT * FROM packages WHERE id=?", (pkg_id,)).fetchone()
    store = conn.execute("SELECT * FROM stores WHERE id=?", (pkg['store_id'],)).fetchone()
    
    panel = conn.execute("SELECT * FROM panels WHERE id=?", (store['panel_id'],)).fetchone()
    if not panel:
        panel = conn.execute("SELECT * FROM panels LIMIT 1").fetchone()
        if not panel:
            await callback.message.edit_text("❌ هیچ سروری در پنل مدیریت تعریف نشده است!")
            return conn.close()

    await callback.message.edit_text(f"⏳ در حال تولید کانفیگ از سرور {panel['name']}...\nلطفاً صبور باشید.")
    
    current_counter = store['counter']
    
    for i in range(qty):
        prefix = store['prefix'] if store['prefix'] else ""
        suffix = pkg['suffix'] if pkg['suffix'] else ""
        
        success, result = await create_xui_client(
            url=panel['xui_url'], user=panel['xui_user'], pwd=panel['xui_pass'], 
            port=store['inbound_port'], prefix=prefix, suffix=suffix, 
            volume_gb=pkg['volume'], days=pkg['days'], start_counter=current_counter
        )
        
        if success:
            smart_counter = result["new_counter"]
            now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            conn.execute("INSERT INTO configs_log (store_id, package_name, volume, created_at) VALUES (?, ?, ?, ?)", (store['id'], pkg['name'], pkg['volume'], now))
            
            # پیام نهایی پاکسازی شده (بدون کانفیگ VPN ادمین)
            msg = f"✅ کانفیگ شما ساخته شد:\n\n`{result['actual_config']}`\n\n🔗 لینک سابسکریپشن:\n{result['sub_link']}\n\n🔢 کد اختصاصی: {smart_counter}"
            await callback.message.answer(msg, parse_mode="Markdown")
            current_counter = smart_counter + 1
        else:
            await callback.message.answer(f"⚠️ خطا:\n{result}")

    conn.execute("UPDATE stores SET counter=? WHERE id=?", (current_counter, store['id']))
    conn.commit()
    conn.close()
    await callback.message.delete()

async def main():
    print("🚀 ربات هوشمند با موتور سیال استخراج Vless راه‌اندازی شد!")
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
EOF

# ۵. ایجاد فایل panel.html با رابط کاربری کاملِ ۶ تب
echo "[+] Creating panel.html UI..."
cat << 'EOF' > panel.html
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>پنل مدیریت جامع کانفیگ</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.13.3/dist/cdn.min.js"></script>
    <link href="https://v1.fontapi.ir/css/Vazir" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script> tailwind.config = { theme: { extend: { fontFamily: { sans: ['Vazir', 'sans-serif'] }, colors: { dark: { 900: '#121212', 800: '#1e1e1e', 700: '#2c2c2c', 600: '#3d3d3d' }, pistachio: { 400: '#b4e650', 500: '#9cd33b', 600: '#85b927' } } } } } </script>
    <style> body { font-family: 'Vazir', sans-serif; background-color: #121212; color: #ffffff; -webkit-tap-highlight-color: transparent; } ::-webkit-scrollbar { width: 0px; background: transparent; } .glow-pistachio { box-shadow: 0 0 15px rgba(156, 211, 59, 0.3); } </style>
</head>
<body x-data="panelApp()" x-init="initData()" class="antialiased w-full h-screen overflow-hidden flex flex-col">

    <!-- لاگین -->
    <div x-show="!loggedIn" class="flex-1 flex items-center justify-center p-6 bg-dark-900" x-transition>
        <div class="w-full max-w-sm bg-dark-800 rounded-3xl p-8 border border-dark-700 shadow-2xl relative overflow-hidden">
            <div class="absolute top-0 left-1/2 -translate-x-1/2 w-32 h-32 bg-pistachio-500 rounded-full blur-[70px] opacity-20"></div>
            <div class="text-center mb-8 relative z-10">
                <div class="w-20 h-20 bg-dark-700 rounded-full flex items-center justify-center mx-auto mb-4 border border-pistachio-500/30"><i class="fa-solid fa-fingerprint text-pistachio-500 text-4xl"></i></div>
                <h2 class="text-2xl font-black text-white">ورود مدیریت کل</h2>
            </div>
            <div class="space-y-5 relative z-10">
                <input x-model="loginUser" type="text" placeholder="نام کاربری" class="w-full bg-dark-700 border border-dark-600 text-white rounded-2xl p-3.5 outline-none">
                <input x-model="loginPass" type="password" placeholder="رمز عبور" class="w-full bg-dark-700 border border-dark-600 text-white rounded-2xl p-3.5 outline-none">
                <button @click="doLogin()" class="w-full bg-pistachio-500 text-dark-900 font-extrabold rounded-2xl py-3.5 mt-4 glow-pistachio">ورود</button>
            </div>
        </div>
    </div>

    <!-- اپلیکیشن اصلی -->
    <div x-show="loggedIn" class="flex flex-col h-screen w-full bg-dark-900" x-cloak>
        <header class="bg-dark-800 px-6 py-4 flex justify-between items-center border-b border-dark-700 sticky top-0 z-20">
            <div>
                <h1 class="text-lg font-bold text-white">
                    <span x-show="activeTab === 'dashboard'">داشبورد</span>
                    <span x-show="activeTab === 'stores'">مدیریت فروشگاه‌ها</span>
                    <span x-show="activeTab === 'packages'">پکیج‌های حجمی</span>
                    <span x-show="activeTab === 'reports'">گزارشات و مالی</span>
                    <span x-show="activeTab === 'users'">نمایندگان</span>
                    <span x-show="activeTab === 'settings'">تنظیمات سیستم</span>
                </h1>
                <p class="text-[10px] text-pistachio-500 flex items-center gap-1 mt-1"><span class="w-1.5 h-1.5 rounded-full bg-pistachio-400 animate-pulse"></span> متصل</p>
            </div>
            <div class="text-left bg-dark-900 px-3 py-1.5 rounded-xl border border-dark-600">
                <div class="text-pistachio-500 font-mono text-sm font-bold" x-text="serverClock.split(' ')[1] || '00:00:00'"></div>
                <div class="text-gray-400 font-mono text-[10px]" x-text="serverClock.split(' ')[0] || 'YYYY-MM-DD'"></div>
            </div>
        </header>

        <main class="flex-1 overflow-y-auto p-5 pb-36">
            
            <!-- 1. داشبورد -->
            <div x-show="activeTab === 'dashboard'" class="space-y-4">
                <div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 flex items-center justify-between">
                    <div><p class="text-sm text-gray-400 mb-1">کل کانفیگ‌های ساخته شده</p><p class="text-3xl font-black text-white" x-text="stats.total_configs"></p></div>
                    <div class="w-12 h-12 rounded-2xl bg-dark-700 text-pistachio-500 flex items-center justify-center text-xl"><i class="fa-solid fa-bolt"></i></div>
                </div>
                <div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 mt-5">
                    <h4 class="text-pistachio-500 font-bold mb-4 border-b border-dark-700 pb-2"><i class="fa-solid fa-chart-pie ml-1"></i> آمار به تفکیک فروشگاه</h4>
                    <div class="space-y-3">
                        <template x-for="stat in stats.store_stats" :key="stat.name">
                            <div class="flex justify-between items-center bg-dark-900 p-3 rounded-xl border border-dark-600">
                                <span class="text-sm font-bold text-white" x-text="stat.name"></span>
                                <span class="text-pistachio-500 font-bold text-sm bg-dark-800 px-3 py-1 rounded-lg" x-text="stat.config_count + ' کانفیگ'"></span>
                            </div>
                        </template>
                    </div>
                </div>
            </div>

            <!-- 2. فروشگاه‌ها -->
            <div x-show="activeTab === 'stores'" class="space-y-5">
                <h3 class="text-pistachio-500 font-bold mb-2 pl-2 border-r-2 border-pistachio-500"><i class="fa-solid ml-1" :class="editStoreId ? 'fa-pen' : 'fa-plus-circle'"></i> <span x-text="editStoreId ? 'ویرایش فروشگاه' : 'افزودن فروشگاه جدید'"></span></h3>
                <div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 space-y-4">
                    <div><label class="block text-xs text-gray-400 mb-1">نام نمایشی فروشگاه</label><input x-model="newStore.name" type="text" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 text-white outline-none"></div>
                    <div>
                        <label class="block text-xs text-pistachio-500 font-bold mb-1">اتصال به کدام سرور؟</label>
                        <select x-model="newStore.panel_id" class="w-full bg-dark-900 border border-pistachio-500/50 rounded-xl p-3 text-white outline-none">
                            <option value="">-- انتخاب سرور --</option>
                            <template x-for="p in panelsList" :key="p.id"><option :value="p.id" x-text="p.name"></option></template>
                        </select>
                    </div>
                    <div class="grid grid-cols-2 gap-3">
                        <div><label class="block text-xs text-gray-400 mb-1">پورت X-UI</label><input x-model="newStore.inbound_port" type="number" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 text-white outline-none" dir="ltr"></div>
                        <div><label class="block text-xs text-gray-400 mb-1">پیشوند (انگلیسی)</label><input x-model="newStore.prefix" type="text" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 text-white outline-none" dir="ltr"></div>
                    </div>
                    <div><label class="block text-xs text-gray-400 mb-1">شروع کانتر</label><input x-model="newStore.counter" type="number" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 text-white outline-none" dir="ltr"></div>
                    
                    <div class="flex gap-2 mt-2">
                        <button @click="saveStore()" class="flex-1 bg-pistachio-500 text-dark-900 font-bold py-3.5 rounded-xl glow-pistachio" x-text="editStoreId ? 'ثبت تغییرات' : 'ذخیره فروشگاه'"></button>
                        <button x-show="editStoreId" @click="cancelEditStore()" class="w-1/3 bg-dark-700 text-gray-400 border border-dark-600 font-bold py-3.5 rounded-xl">لغو</button>
                    </div>
                </div>
                <div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 mt-5">
                    <h4 class="text-pistachio-500 font-bold mb-4 border-b border-dark-700 pb-2">لیست فروشگاه‌ها</h4>
                    <div class="space-y-3">
                        <template x-for="store in storesList" :key="store.id">
                            <div class="flex justify-between items-center bg-dark-900 p-3 rounded-xl border border-dark-600">
                                <div>
                                    <p class="text-sm font-bold text-white" x-text="store.name"></p>
                                    <p class="text-[10px] text-gray-400 mt-1">سرور: <span class="text-pistachio-500" x-text="store.panel_name || 'نامشخص'"></span> | پورت: <span x-text="store.inbound_port" class="text-pistachio-500"></span></p>
                                </div>
                                <div class="flex gap-2">
                                    <button @click="startEditStore(store)" class="text-blue-400 hover:bg-blue-500/20 p-2.5 rounded-xl transition-colors bg-dark-800"><i class="fa-solid fa-pen"></i></button>
                                    <button @click="deleteStore(store.id)" class="text-red-500 hover:bg-red-500/20 p-2.5 rounded-xl transition-colors bg-dark-800"><i class="fa-solid fa-trash"></i></button>
                                </div>
                            </div>
                        </template>
                    </div>
                </div>
            </div>

            <!-- 3. پکیج‌ها -->
            <div x-show="activeTab === 'packages'" class="space-y-5">
                <h3 class="text-pistachio-500 font-bold mb-2 pl-2 border-r-2 border-pistachio-500"><i class="fa-solid ml-1" :class="editPackageId ? 'fa-pen' : 'fa-box'"></i> <span x-text="editPackageId ? 'ویرایش پکیج' : 'تعریف پکیج جدید'"></span></h3>
                <div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 space-y-4">
                    <div>
                        <label class="block text-xs text-gray-400 mb-1">انتخاب فروشگاه</label>
                        <select x-model="newPackage.store_id" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 text-white outline-none">
                            <option value="">-- انتخاب کنید --</option>
                            <template x-for="store in storesList" :key="store.id"><option :value="store.id" x-text="store.name"></option></template>
                        </select>
                    </div>
                    <div><label class="block text-xs text-gray-400 mb-1">نام دکمه نمایشی</label><input x-model="newPackage.name" type="text" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 text-white outline-none"></div>
                    <div class="grid grid-cols-2 gap-3">
                        <div><label class="block text-xs text-gray-400 mb-1">حجم (GB)</label><input x-model="newPackage.volume" type="number" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 text-white outline-none" dir="ltr"></div>
                        <div><label class="block text-xs text-gray-400 mb-1">زمان (روز)</label><input x-model="newPackage.days" type="number" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 text-white outline-none" dir="ltr"></div>
                    </div>
                    <div><label class="block text-xs text-gray-400 mb-1">پسوند اختصاصی (انگلیسی)</label><input x-model="newPackage.suffix" type="text" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 text-white outline-none" dir="ltr"></div>
                    <div class="flex gap-2 mt-2">
                        <button @click="savePackage()" class="flex-1 bg-pistachio-500 text-dark-900 font-bold py-3.5 rounded-xl glow-pistachio" x-text="editPackageId ? 'ثبت تغییرات' : 'افزودن پکیج'"></button>
                        <button x-show="editPackageId" @click="cancelEditPackage()" class="w-1/3 bg-dark-700 text-gray-400 border border-dark-600 font-bold py-3.5 rounded-xl hover:text-white">لغو</button>
                    </div>
                </div>
                <div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 mt-5">
                    <h4 class="text-pistachio-500 font-bold mb-4 border-b border-dark-700 pb-2">پکیج‌ها به تفکیک فروشگاه</h4>
                    <div class="space-y-3">
                        <template x-for="store in storesList" :key="store.id">
                            <div x-data="{ open: false }" class="bg-dark-900 rounded-xl border border-dark-600 overflow-hidden">
                                <button @click="open = !open" class="w-full flex justify-between items-center p-4 bg-dark-800/50 hover:bg-dark-700 transition-colors">
                                    <span class="font-bold text-white text-sm" x-text="'📦 پکیج‌های ' + store.name"></span>
                                    <i class="fa-solid fa-chevron-down transition-transform text-pistachio-500" :class="open ? 'rotate-180' : ''"></i>
                                </button>
                                <div x-show="open" class="p-3 space-y-2 border-t border-dark-600">
                                    <template x-for="pkg in packagesList.filter(p => p.store_id === store.id)" :key="pkg.id">
                                        <div class="flex justify-between items-center bg-dark-800 p-3 rounded-xl border border-dark-700">
                                            <div><p class="text-sm font-bold text-white" x-text="pkg.name"></p><p class="text-[11px] text-gray-400 mt-1"><span x-text="pkg.volume"></span> گیگ | <span x-text="pkg.days"></span> روز</p></div>
                                            <div class="flex gap-2">
                                                <button @click="startEditPackage(pkg)" class="text-blue-400 hover:bg-blue-500/20 p-2 rounded-lg transition-colors bg-dark-900"><i class="fa-solid fa-pen"></i></button>
                                                <button @click="deletePackage(pkg.id)" class="text-red-500 hover:bg-red-500/20 p-2 rounded-lg transition-colors bg-dark-900"><i class="fa-solid fa-trash"></i></button>
                                            </div>
                                        </div>
                                    </template>
                                </div>
                            </div>
                        </template>
                    </div>
                </div>
            </div>

            <!-- 4. گزارشات -->
            <div x-show="activeTab === 'reports'" class="space-y-5">
                <h3 class="text-pistachio-500 font-bold mb-2 pl-2 border-r-2 border-pistachio-500"><i class="fa-solid fa-chart-bar ml-1"></i> گزارش‌گیری</h3>
                <div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 space-y-4">
                    <div>
                        <label class="block text-xs text-gray-400 mb-1">انتخاب فروشگاه</label>
                        <select x-model="reportParams.store_id" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 text-white outline-none">
                            <option value="">-- انتخاب کنید --</option>
                            <template x-for="store in storesList" :key="store.id"><option :value="store.id" x-text="store.name"></option></template>
                        </select>
                    </div>
                    <div class="grid grid-cols-2 gap-3">
                        <div><label class="block text-xs text-gray-400 mb-1">از تاریخ و ساعت</label><input x-model="reportParams.start_date" type="datetime-local" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 text-white outline-none text-[11px]" dir="ltr"></div>
                        <div><label class="block text-xs text-gray-400 mb-1">تا تاریخ و ساعت</label><input x-model="reportParams.end_date" type="datetime-local" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 text-white outline-none text-[11px]" dir="ltr"></div>
                    </div>
                    <button @click="fetchReport()" class="w-full mt-2 bg-pistachio-500 text-dark-900 font-bold py-3.5 rounded-xl glow-pistachio">دریافت گزارش</button>
                </div>
                <div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 mt-5" x-show="reportResults !== null">
                    <h4 class="text-pistachio-500 font-bold mb-4 border-b border-dark-700 pb-2">نتیجه جستجو</h4>
                    <div class="space-y-3">
                        <template x-for="res in reportResults" :key="res.package_name">
                            <div class="flex justify-between items-center bg-dark-900 p-3 rounded-xl border border-dark-600">
                                <span class="text-sm font-bold text-white" x-text="res.package_name"></span>
                                <span class="text-pistachio-500 font-bold text-sm bg-dark-800 px-3 py-1 rounded-lg" x-text="res.count + ' عدد'"></span>
                            </div>
                        </template>
                    </div>
                </div>
            </div>

            <!-- 5. نمایندگان (کاربران) -->
            <div x-show="activeTab === 'users'" class="space-y-5">
                <h3 class="text-pistachio-500 font-bold mb-2 pl-2 border-r-2 border-pistachio-500"><i class="fa-solid fa-users ml-1"></i> تخصیص دسترسی بات</h3>
                <div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 space-y-4">
                    <div><label class="block text-xs text-gray-400 mb-1">Chat ID تلگرام</label><input x-model="newUser.chat_id" type="text" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 text-pistachio-400 tracking-wider outline-none" dir="ltr"></div>
                    <div><label class="block text-xs text-gray-400 mb-1">نام نماینده</label><input x-model="newUser.owner_name" type="text" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 text-white outline-none"></div>
                    <div class="bg-dark-900 p-4 rounded-xl border border-dark-600">
                        <p class="text-xs text-gray-400 mb-3 border-b border-dark-700 pb-2">فروشگاه‌های مجاز برای این فرد</p>
                        <div class="space-y-3">
                            <template x-for="store in storesList" :key="store.id">
                                <label class="flex items-center gap-3 w-full p-2 rounded-lg active:bg-dark-800">
                                    <input type="checkbox" :value="store.id" x-model="newUser.allowed_stores" class="w-5 h-5 rounded accent-pistachio-500">
                                    <span class="text-sm" x-text="store.name"></span>
                                </label>
                            </template>
                        </div>
                    </div>
                    <button @click="saveUser()" class="w-full mt-2 bg-pistachio-500 text-dark-900 font-bold py-3.5 rounded-xl glow-pistachio">ثبت نماینده</button>
                </div>
                <div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 mt-5">
                    <h4 class="text-pistachio-500 font-bold mb-4 border-b border-dark-700 pb-2">لیست نمایندگان مجاز</h4>
                    <div class="space-y-3">
                        <template x-for="user in usersList" :key="user.id">
                            <div class="flex justify-between items-center bg-dark-900 p-3 rounded-xl border border-dark-600">
                                <div><p class="text-sm font-bold text-white" x-text="user.owner_name"></p><p class="text-[11px] text-gray-400 mt-1" dir="ltr" x-text="user.chat_id"></p></div>
                                <button @click="deleteUser(user.id)" class="text-red-500 hover:bg-red-500/20 p-2.5 rounded-xl transition-colors bg-dark-800"><i class="fa-solid fa-trash"></i></button>
                            </div>
                        </template>
                    </div>
                </div>
            </div>

            <!-- 6. تنظیمات (مولتی‌پنل، مسیریابی و بکاپ) -->
            <div x-show="activeTab === 'settings'" class="space-y-6">
                
                <!-- بخش بکاپ و ریاستور -->
                <div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 shadow-lg relative overflow-hidden">
                    <div class="absolute -right-4 -top-4 w-16 h-16 bg-pistachio-500/10 rounded-full blur-xl"></div>
                    <h4 class="text-pistachio-500 font-bold mb-4 border-b border-dark-700 pb-2 flex justify-between"><span>محافظت از اطلاعات (دیتابیس)</span><i class="fa-solid fa-database"></i></h4>
                    <div class="grid grid-cols-2 gap-4">
                        <button @click="downloadBackup()" class="flex flex-col items-center justify-center bg-dark-900 border border-dark-600 hover:border-pistachio-500 rounded-2xl p-4 transition-colors">
                            <i class="fa-solid fa-download text-3xl text-pistachio-500 mb-2"></i>
                            <span class="text-xs font-bold text-white">دریافت فایل بکاپ</span>
                        </button>
                        <div class="relative flex flex-col items-center justify-center bg-dark-900 border border-dark-600 hover:border-blue-500 rounded-2xl p-4 transition-colors cursor-pointer">
                            <input type="file" @change="uploadBackup" class="absolute inset-0 w-full h-full opacity-0 cursor-pointer" accept=".db">
                            <i class="fa-solid fa-upload text-3xl text-blue-500 mb-2"></i>
                            <span class="text-xs font-bold text-white">بازگردانی دیتابیس</span>
                        </div>
                    </div>
                </div>

                <!-- بخش مدیریت سرورهای X-UI -->
                <div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 shadow-lg">
                    <h4 class="text-pistachio-500 font-bold mb-4 border-b border-dark-700 pb-2 flex justify-between"><span>مدیریت سرورهای X-UI</span><i class="fa-solid fa-server"></i></h4>
                    
                    <!-- فرم افزودن / ویرایش سرور -->
                    <div class="space-y-4 mb-6 bg-dark-900 p-4 rounded-2xl border border-dark-600">
                        <h5 class="text-xs text-white font-bold mb-2"><i class="fa-solid" :class="editPanelId ? 'fa-pen' : 'fa-plus'"></i> <span x-text="editPanelId ? 'ویرایش سرور' : 'افزودن سرور جدید'"></span></h5>
                        <div><input x-model="newPanel.name" type="text" placeholder="نام دلخواه (مثلا سرور هلند)" class="w-full bg-dark-800 border border-dark-700 rounded-xl p-3 text-white outline-none"></div>
                        <div><input x-model="newPanel.xui_url" type="text" placeholder="آدرس سرور (https://ip:port/secret)" dir="ltr" class="w-full bg-dark-800 border border-dark-700 rounded-xl p-3 text-white outline-none"></div>
                        <div class="grid grid-cols-2 gap-3">
                            <div><input x-model="newPanel.xui_user" type="text" placeholder="یوزرنیم X-UI" dir="ltr" class="w-full bg-dark-800 border border-dark-700 rounded-xl p-3 text-white outline-none"></div>
                            <div><input x-model="newPanel.xui_pass" type="password" placeholder="پسورد X-UI" dir="ltr" class="w-full bg-dark-800 border border-dark-700 rounded-xl p-3 text-white outline-none"></div>
                        </div>
                        <div class="flex gap-2">
                            <button @click="savePanel()" class="flex-1 bg-pistachio-500 text-dark-900 font-bold py-3 rounded-xl glow-pistachio" x-text="editPanelId ? 'ذخیره تغییرات سرور' : 'ثبت سرور'"></button>
                            <button x-show="editPanelId" @click="cancelEditPanel()" class="w-1/3 bg-dark-700 text-gray-400 font-bold py-3 rounded-xl border border-dark-600">لغو</button>
                        </div>
                    </div>

                    <!-- لیست سرورها -->
                    <div class="space-y-3">
                        <template x-for="p in panelsList" :key="p.id">
                            <div class="flex justify-between items-center bg-dark-900 p-3 rounded-xl border border-dark-600">
                                <div><p class="text-sm font-bold text-white" x-text="p.name"></p><p class="text-[10px] text-gray-400 mt-1" dir="ltr" x-text="p.xui_url"></p></div>
                                <div class="flex gap-2">
                                    <button @click="startEditPanel(p)" class="text-blue-400 p-2 bg-dark-800 rounded-lg"><i class="fa-solid fa-pen"></i></button>
                                    <button @click="deletePanel(p.id)" class="text-red-500 p-2 bg-dark-800 rounded-lg"><i class="fa-solid fa-trash"></i></button>
                                </div>
                            </div>
                        </template>
                    </div>
                </div>

                <!-- بخش مسیریابی (کانفیگ ایران) -->
                <div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 shadow-lg">
                    <h4 class="text-sm text-white font-bold border-b border-dark-600 pb-2 flex justify-between"><span>مسیریابی امن VPN</span><i class="fa-solid fa-route text-pistachio-500"></i></h4>
                    <div class="mt-4"><label class="block text-xs text-gray-400 mb-2">کانفیگ اتصال (سرور ایران و ...)</label><textarea x-model="settingsData.vpn_config" rows="4" class="w-full bg-dark-900 text-pistachio-400 font-mono text-xs border border-dark-600 rounded-xl p-4 outline-none resize-none" dir="ltr" placeholder="vless://..."></textarea></div>
                    <button @click="saveSettings()" class="w-full mt-4 bg-dark-700 border border-pistachio-500 text-pistachio-500 font-bold py-3.5 rounded-xl active:bg-pistachio-500 active:text-dark-900 transition-colors">ذخیره کانفیگ مسیریابی</button>
                </div>
            </div>
        </main>

        <!-- منوی 6 تایی کامل -->
        <nav class="fixed bottom-0 w-full bg-dark-800/95 backdrop-blur-md border-t border-dark-700 pb-2 pt-2 px-1 z-30">
            <div class="flex justify-between items-center h-14">
                <button @click="activeTab = 'dashboard'" class="flex flex-col items-center justify-center w-full h-full transition-colors" :class="activeTab === 'dashboard' ? 'text-pistachio-500' : 'text-gray-500'"><i class="fa-solid fa-chart-pie text-lg mb-1"></i><span class="text-[9px] font-bold">داشبورد</span></button>
                <button @click="activeTab = 'stores'" class="flex flex-col items-center justify-center w-full h-full transition-colors" :class="activeTab === 'stores' ? 'text-pistachio-500' : 'text-gray-500'"><i class="fa-solid fa-store text-lg mb-1"></i><span class="text-[9px] font-bold">فروشگاه‌ها</span></button>
                <button @click="activeTab = 'packages'" class="flex flex-col items-center justify-center w-full h-full transition-colors" :class="activeTab === 'packages' ? 'text-pistachio-500' : 'text-gray-500'"><i class="fa-solid fa-box-open text-lg mb-1"></i><span class="text-[9px] font-bold">پکیج‌ها</span></button>
                <button @click="activeTab = 'reports'" class="flex flex-col items-center justify-center w-full h-full transition-colors" :class="activeTab === 'reports' ? 'text-pistachio-500' : 'text-gray-500'"><i class="fa-solid fa-chart-bar text-lg mb-1"></i><span class="text-[9px] font-bold">گزارشات</span></button>
                <button @click="activeTab = 'users'" class="flex flex-col items-center justify-center w-full h-full transition-colors" :class="activeTab === 'users' ? 'text-pistachio-500' : 'text-gray-500'"><i class="fa-solid fa-users text-lg mb-1"></i><span class="text-[9px] font-bold">نمایندگان</span></button>
                <button @click="activeTab = 'settings'" class="flex flex-col items-center justify-center w-full h-full transition-colors" :class="activeTab === 'settings' ? 'text-pistachio-500' : 'text-gray-500'"><i class="fa-solid fa-gear text-lg mb-1"></i><span class="text-[9px] font-bold">تنظیمات</span></button>
            </div>
        </nav>
    </div>

    <script>
        function panelApp() {
            return {
                loggedIn: false, activeTab: 'dashboard', 
                loginUser: '', loginPass: '',
                panelsList: [], storesList: [], packagesList: [], usersList: [],
                stats: { total_configs: 0, active_stores: 0, store_stats: [] },
                
                serverClock: '', clockInterval: null,
                editStoreId: null, editPackageId: null, editPanelId: null,

                newPanel: { name: '', xui_url: '', xui_user: '', xui_pass: '' },
                newStore: { name: '', panel_id: '', inbound_port: '', prefix: '', counter: '' },
                newPackage: { store_id: '', name: '', volume: '', days: '', suffix: '' },
                newUser: { chat_id: '', owner_name: '', allowed_stores: [] },
                settingsData: { vpn_config: '' },
                
                reportParams: { store_id: '', start_date: '', end_date: '' },
                reportResults: null,

                doLogin() {
                    if(this.loginUser === '__USER__' && this.loginPass === '__PASS__') { this.loggedIn = true; } else { alert('❌ نام کاربری یا رمز عبور اشتباه است!'); }
                },

                initData() { 
                    this.fetchStats(); this.fetchPanels(); this.fetchStores(); this.fetchPackages(); this.fetchUsers(); this.fetchSettings(); 
                },
                
                startClock(initialTime) {
                    if(this.clockInterval) clearInterval(this.clockInterval);
                    let t = new Date(initialTime.replace(' ', 'T'));
                    this.serverClock = initialTime;
                    this.clockInterval = setInterval(() => { t.setSeconds(t.getSeconds() + 1); this.serverClock = t.toISOString().replace('T', ' ').substring(0, 19); }, 1000);
                },

                async fetchStats() { let res = await fetch('/api/stats'); this.stats = await res.json(); this.startClock(this.stats.server_time); },
                
                downloadBackup() { window.location.href = '/api/backup'; },
                async uploadBackup(event) {
                    let file = event.target.files[0];
                    if(!file) return;
                    if(!confirm("⚠️ بازگردانی بکاپ، تمام اطلاعات فعلی را پاک و جایگزین می‌کند. مطمئن هستید؟")) return;
                    let formData = new FormData(); formData.append("file", file);
                    let res = await fetch('/api/restore', { method: 'POST', body: formData });
                    if(res.ok) { alert('✅ بکاپ با موفقیت بازگردانی شد. سیستم ری‌استارت می‌شود.'); window.location.reload(); }
                    else { alert('❌ خطا در بازگردانی'); }
                },

                async fetchPanels() { let res = await fetch('/api/panels'); this.panelsList = await res.json(); },
                startEditPanel(p) { this.editPanelId = p.id; this.newPanel = { name: p.name, xui_url: p.xui_url, xui_user: p.xui_user, xui_pass: p.xui_pass }; window.scrollTo({ top: 0, behavior: 'smooth' }); },
                cancelEditPanel() { this.editPanelId = null; this.newPanel = { name:'', xui_url:'', xui_user:'', xui_pass:'' }; },
                async savePanel() {
                    if(!this.newPanel.name || !this.newPanel.xui_url) return alert("نام و آدرس سرور الزامی است");
                    if(this.editPanelId) {
                        await fetch('/api/panels/' + this.editPanelId, { method: 'PUT', headers: {'Content-Type':'application/json'}, body: JSON.stringify(this.newPanel) });
                        this.cancelEditPanel();
                    } else {
                        await fetch('/api/panels', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(this.newPanel) });
                        this.newPanel = { name:'', xui_url:'', xui_user:'', xui_pass:'' };
                    }
                    this.fetchPanels();
                },
                async deletePanel(id) { if(confirm("مطمئن هستید؟")) { await fetch('/api/panels/' + id, { method: 'DELETE' }); this.fetchPanels(); } },

                async fetchStores() { let res = await fetch('/api/stores'); this.storesList = await res.json(); this.fetchStats(); },
                startEditStore(store) { this.editStoreId = store.id; this.newStore = { name: store.name, panel_id: store.panel_id, inbound_port: store.inbound_port, prefix: store.prefix, counter: store.counter }; window.scrollTo({ top: 0, behavior: 'smooth' }); },
                cancelEditStore() { this.editStoreId = null; this.newStore = {name:'', panel_id:'', inbound_port:'', prefix:'', counter:''}; },
                async saveStore() {
                    if(!this.newStore.name || !this.newStore.panel_id) return alert("انتخاب سرور و نام فروشگاه الزامی است");
                    if(this.editStoreId) {
                        await fetch('/api/stores/' + this.editStoreId, { method: 'PUT', headers: {'Content-Type':'application/json'}, body: JSON.stringify(this.newStore) });
                        this.cancelEditStore();
                    } else {
                        await fetch('/api/stores', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(this.newStore) });
                        this.newStore = {name:'', panel_id:'', inbound_port:'', prefix:'', counter:''};
                    }
                    this.fetchStores();
                },
                async deleteStore(id) { if(confirm("مطمئن هستید؟")) { await fetch('/api/stores/' + id, { method: 'DELETE' }); this.fetchStores(); this.fetchPackages(); } },

                async fetchPackages() { let res = await fetch('/api/packages'); this.packagesList = await res.json(); },
                startEditPackage(pkg) { this.editPackageId = pkg.id; this.newPackage = { store_id: pkg.store_id, name: pkg.name, volume: pkg.volume, days: pkg.days, suffix: pkg.suffix }; window.scrollTo({ top: 0, behavior: 'smooth' }); },
                cancelEditPackage() { this.editPackageId = null; this.newPackage = {store_id:'', name:'', volume:'', days:'', suffix:''}; },
                async savePackage() {
                    if(!this.newPackage.store_id) return alert("فروشگاه را انتخاب کنید");
                    if(this.editPackageId) {
                        await fetch('/api/packages/' + this.editPackageId, { method: 'PUT', headers: {'Content-Type':'application/json'}, body: JSON.stringify(this.newPackage) });
                        this.cancelEditPackage();
                    } else {
                        await fetch('/api/packages', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(this.newPackage) });
                        this.newPackage = {store_id:'', name:'', volume:'', days:'', suffix:''};
                    }
                    this.fetchPackages();
                },
                async deletePackage(id) { if(confirm("مطمئن هستید؟")) { await fetch('/api/packages/' + id, { method: 'DELETE' }); this.fetchPackages(); } },

                async fetchUsers() { let res = await fetch('/api/users'); this.usersList = await res.json(); },
                async saveUser() {
                    if(!this.newUser.chat_id) return alert("Chat ID الزامی است");
                    await fetch('/api/users', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(this.newUser) });
                    this.newUser = {chat_id:'', owner_name:'', allowed_stores:[]}; this.fetchUsers();
                },
                async deleteUser(id) { if(confirm("مطمئن هستید؟")) { await fetch('/api/users/' + id, { method: 'DELETE' }); this.fetchUsers(); } },

                async fetchSettings() { 
                    try { let res = await fetch('/api/settings'); if(res.ok) { let data = await res.json(); this.settingsData.vpn_config = data.vpn_config || ''; } } catch(e) {}
                },
                async saveSettings() {
                    await fetch('/api/settings', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(this.settingsData) });
                    alert("✅ کانفیگ مسیریابی ذخیره شد");
                },

                async fetchReport() {
                    if(!this.reportParams.store_id || !this.reportParams.start_date || !this.reportParams.end_date) return alert("پر کردن تمامی فیلدها الزامی است.");
                    let s_date = this.reportParams.start_date.replace('T', ' ') + ':00'; let e_date = this.reportParams.end_date.replace('T', ' ') + ':59';
                    let res = await fetch(`/api/reports?store_id=${this.reportParams.store_id}&start_date=${s_date}&end_date=${e_date}`);
                    this.reportResults = await res.json();
                }
            }
        }
    </script>
</body>
</html>
EOF

# ۶. اعمال متغیرهای وارد شده در فایل‌ها با sed
sed -i "s/__PORT__/$PANEL_PORT/g" main.py
sed -i "s/__BOT_TOKEN__/$BOT_TOKEN/g" bot.py
sed -i "s/__USER__/$PANEL_USER/g" panel.html
sed -i "s/__PASS__/$PANEL_PASS/g" panel.html

# ۷. ساخت سرویس‌های دائم‌کار (Systemd)
echo "[+] Creating Systemd services..."
cat << EOF > /etc/systemd/system/proxy-panel.service
[Unit]
Description=Proxy Manager Web Panel
After=network.target

[Service]
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/panel_env/bin/python main.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

cat << EOF > /etc/systemd/system/proxy-bot.service
[Unit]
Description=Proxy Manager Telegram Bot
After=network.target

[Service]
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/panel_env/bin/python bot.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# ۸. فعال‌سازی و استارت
echo "[+] Starting services..."
systemctl daemon-reload
systemctl enable proxy-panel > /dev/null 2>&1
systemctl enable proxy-bot > /dev/null 2>&1
systemctl restart proxy-panel
systemctl restart proxy-bot

# حل مشکل IPv6 با استخراج اجباری IPv4
MYIP=$(curl -s -4 ipv4.icanhazip.com || curl -s -4 api.ipify.org)

echo -e "\n${GREEN}=================================================${NC}"
echo -e "${GREEN}      Installation Completed Successfully!       ${NC}"
echo -e "${GREEN}=================================================${NC}"
echo -e "🔗 ${CYAN}Panel URL:${NC} http://$MYIP:$PANEL_PORT"
echo -e "👤 ${CYAN}Username:${NC}  $PANEL_USER"
echo -e "🔑 ${CYAN}Password:${NC}  $PANEL_PASS"
echo -e "🤖 ${CYAN}Bot Token:${NC} $BOT_TOKEN"
echo -e "\n${CYAN}Useful Commands:${NC}"
echo "Status Panel : systemctl status proxy-panel"
echo "Status Bot   : systemctl status proxy-bot"
echo "Restart Both : systemctl restart proxy-panel proxy-bot"
echo -e "${CYAN}=================================================${NC}\n"
