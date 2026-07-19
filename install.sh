#!/bin/bash

# رنگ‌ها برای زیبایی خروجی
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=================================================${NC}"
echo -e "${GREEN}      X-UI Proxy Manager Auto Installer          ${NC}"
echo -e "${CYAN}=================================================${NC}"

# ۱. گرفتن اطلاعات از شما به صورت تعاملی
read -p "1. Enter Telegram Bot Token: " BOT_TOKEN

read -p "2. Enter Web Panel Username [admin]: " PANEL_USER
PANEL_USER=${PANEL_USER:-admin}

read -p "3. Enter Web Panel Password [admin123]: " PANEL_PASS
PANEL_PASS=${PANEL_PASS:-admin123}

# تولید یک پورت رندوم برای پیشنهاد به کاربر
RANDOM_PORT=$(shuf -i 10000-60000 -n 1)
read -p "4. Enter Web Panel Port [$RANDOM_PORT]: " PANEL_PORT
PANEL_PORT=${PANEL_PORT:-$RANDOM_PORT}

echo -e "\n${GREEN}[+] Starting Installation...${NC}"

# ۲. نصب پیش‌نیازهای لینوکسی
echo "[+] Updating OS and installing dependencies..."
apt update && apt install -y python3 python3-venv sqlite3 curl

# ۳. ساخت دایرکتوری اصلی پروژه
INSTALL_DIR="/opt/proxy-panel"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# ۴. راه‌اندازی محیط مجازی و نصب پکیج‌های پایتون
echo "[+] Setting up Python Virtual Environment..."
python3 -m venv panel_env
source panel_env/bin/activate
pip install fastapi uvicorn pydantic aiogram aiohttp python-multipart > /dev/null 2>&1

# ۵. ساخت فایل main.py
echo "[+] Creating main.py..."
cat << 'EOF' > main.py
import os, shutil, sqlite3, uvicorn, datetime
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.responses import HTMLResponse, FileResponse
from pydantic import BaseModel
from typing import Optional, List

app = FastAPI(title="X-UI Proxy Panel Manager")

def get_db():
    conn = sqlite3.connect('panel_database.db')
    conn.row_factory = sqlite3.Row
    return conn

def setup_database():
    conn = get_db(); cursor = conn.cursor()
    cursor.execute('''CREATE TABLE IF NOT EXISTS stores (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, panel_id INTEGER DEFAULT 0, inbound_port INTEGER, prefix TEXT, counter INTEGER)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS packages (id INTEGER PRIMARY KEY AUTOINCREMENT, store_id INTEGER, name TEXT, volume INTEGER, days INTEGER, suffix TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, chat_id TEXT, owner_name TEXT, allowed_stores TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS configs_log (id INTEGER PRIMARY KEY AUTOINCREMENT, store_id INTEGER, package_name TEXT, volume INTEGER, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS settings (id INTEGER PRIMARY KEY AUTOINCREMENT, vpn_config TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS panels (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, xui_url TEXT, xui_user TEXT, xui_pass TEXT)''')
    conn.commit(); conn.close()

setup_database()

class PanelCreate(BaseModel): name: str; xui_url: str; xui_user: str; xui_pass: str
class StoreCreate(BaseModel): name: str; panel_id: int; inbound_port: int; prefix: Optional[str] = ""; counter: int
class PackageCreate(BaseModel): store_id: int; name: str; volume: int; days: int; suffix: Optional[str] = ""
class UserCreate(BaseModel): chat_id: str; owner_name: str; allowed_stores: List[int]
class SettingsUpdate(BaseModel): vpn_config: Optional[str] = ""

@app.get("/api/backup")
def download_backup(): return FileResponse("panel_database.db", media_type="application/octet-stream", filename=f"backup_{datetime.datetime.now().strftime('%Y%m%d')}.db")
@app.post("/api/restore")
async def restore_backup(file: UploadFile = File(...)):
    with open("panel_database.db", "wb") as buffer: shutil.copyfileobj(file.file, buffer)
    return {"status": "success"}

@app.get("/api/stats")
def get_stats():
    conn = get_db(); cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM stores")
    stores_count = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM configs_log")
    total_configs = cursor.fetchone()[0]
    cursor.execute('''SELECT stores.name, COUNT(configs_log.id) as config_count FROM stores LEFT JOIN configs_log ON stores.id = configs_log.store_id GROUP BY stores.id''')
    store_stats = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return {"total_configs": total_configs, "active_stores": stores_count, "store_stats": store_stats, "server_time": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}

@app.get("/api/panels")
def get_panels(): conn = get_db(); cursor = conn.cursor(); cursor.execute("SELECT * FROM panels ORDER BY id DESC"); rows = cursor.fetchall(); conn.close(); return [dict(row) for row in rows]
@app.post("/api/panels")
def create_panel(panel: PanelCreate): conn = get_db(); cursor = conn.cursor(); cursor.execute("INSERT INTO panels (name, xui_url, xui_user, xui_pass) VALUES (?, ?, ?, ?)", (panel.name, panel.xui_url, panel.xui_user, panel.xui_pass)); conn.commit(); conn.close(); return {"status": "success"}
@app.put("/api/panels/{item_id}")
def update_panel(item_id: int, panel: PanelCreate): conn = get_db(); cursor = conn.cursor(); cursor.execute("UPDATE panels SET name=?, xui_url=?, xui_user=?, xui_pass=? WHERE id=?", (panel.name, panel.xui_url, panel.xui_user, panel.xui_pass, item_id)); conn.commit(); conn.close(); return {"status": "success"}
@app.delete("/api/panels/{item_id}")
def delete_panel(item_id: int): conn = get_db(); cursor = conn.cursor(); cursor.execute("DELETE FROM panels WHERE id = ?", (item_id,)); conn.commit(); conn.close(); return {"status": "success"}

@app.get("/api/stores")
def get_stores(): conn = get_db(); cursor = conn.cursor(); cursor.execute('''SELECT stores.*, panels.name as panel_name FROM stores LEFT JOIN panels ON stores.panel_id = panels.id ORDER BY stores.id DESC'''); rows = cursor.fetchall(); conn.close(); return [dict(row) for row in rows]
@app.post("/api/stores")
def create_store(store: StoreCreate): conn = get_db(); cursor = conn.cursor(); cursor.execute("INSERT INTO stores (name, panel_id, inbound_port, prefix, counter) VALUES (?, ?, ?, ?, ?)", (store.name, store.panel_id, store.inbound_port, store.prefix, store.counter)); conn.commit(); conn.close(); return {"status": "success"}
@app.put("/api/stores/{item_id}")
def update_store(item_id: int, store: StoreCreate): conn = get_db(); cursor = conn.cursor(); cursor.execute("UPDATE stores SET name=?, panel_id=?, inbound_port=?, prefix=?, counter=? WHERE id=?", (store.name, store.panel_id, store.inbound_port, store.prefix, store.counter, item_id)); conn.commit(); conn.close(); return {"status": "success"}
@app.delete("/api/stores/{item_id}")
def delete_store(item_id: int): conn = get_db(); cursor = conn.cursor(); cursor.execute("DELETE FROM stores WHERE id = ?", (item_id,)); conn.commit(); conn.close(); return {"status": "success"}

@app.get("/api/packages")
def get_packages(): conn = get_db(); cursor = conn.cursor(); cursor.execute("SELECT packages.*, stores.name as store_name FROM packages LEFT JOIN stores ON packages.store_id = stores.id ORDER BY packages.id DESC"); rows = cursor.fetchall(); conn.close(); return [dict(row) for row in rows]
@app.post("/api/packages")
def create_package(pkg: PackageCreate): conn = get_db(); cursor = conn.cursor(); cursor.execute("INSERT INTO packages (store_id, name, volume, days, suffix) VALUES (?, ?, ?, ?, ?)", (pkg.store_id, pkg.name, pkg.volume, pkg.days, pkg.suffix)); conn.commit(); conn.close(); return {"status": "success"}
@app.put("/api/packages/{item_id}")
def update_package(item_id: int, pkg: PackageCreate): conn = get_db(); cursor = conn.cursor(); cursor.execute("UPDATE packages SET store_id=?, name=?, volume=?, days=?, suffix=? WHERE id=?", (pkg.store_id, pkg.name, pkg.volume, pkg.days, pkg.suffix, item_id)); conn.commit(); conn.close(); return {"status": "success"}
@app.delete("/api/packages/{item_id}")
def delete_package(item_id: int): conn = get_db(); cursor = conn.cursor(); cursor.execute("DELETE FROM packages WHERE id = ?", (item_id,)); conn.commit(); conn.close(); return {"status": "success"}

@app.get("/api/users")
def get_users(): conn = get_db(); cursor = conn.cursor(); cursor.execute("SELECT * FROM users ORDER BY id DESC"); rows = cursor.fetchall(); conn.close(); return [dict(row) for row in rows]
@app.post("/api/users")
def create_user(user: UserCreate): conn = get_db(); cursor = conn.cursor(); cursor.execute("INSERT INTO users (chat_id, owner_name, allowed_stores) VALUES (?, ?, ?)", (user.chat_id, user.owner_name, ",".join(map(str, user.allowed_stores)))); conn.commit(); conn.close(); return {"status": "success"}
@app.delete("/api/users/{item_id}")
def delete_user(item_id: int): conn = get_db(); cursor = conn.cursor(); cursor.execute("DELETE FROM users WHERE id = ?", (item_id,)); conn.commit(); conn.close(); return {"status": "success"}

@app.get("/api/reports")
def get_reports(store_id: int, start_date: str, end_date: str): conn = get_db(); cursor = conn.cursor(); cursor.execute('''SELECT package_name, COUNT(*) as count FROM configs_log WHERE store_id = ? AND created_at >= ? AND created_at <= ? GROUP BY package_name''', (store_id, start_date, end_date)); rows = cursor.fetchall(); conn.close(); return [dict(row) for row in rows]

@app.post("/api/settings")
def update_settings(settings: SettingsUpdate):
    conn = get_db(); cursor = conn.cursor()
    try:
        cursor.execute("UPDATE settings SET vpn_config=? WHERE id=(SELECT id FROM settings LIMIT 1)", (settings.vpn_config,))
        if cursor.rowcount == 0: cursor.execute("INSERT INTO settings (vpn_config) VALUES (?)", (settings.vpn_config,))
    except: pass
    conn.commit(); conn.close(); return {"status": "success"}
@app.get("/api/settings")
def get_settings():
    conn = get_db(); cursor = conn.cursor()
    try:
        cursor.execute("SELECT vpn_config FROM settings LIMIT 1"); row = cursor.fetchone(); conn.close(); return dict(row) if row else {}
    except: conn.close(); return {}

@app.get("/", response_class=HTMLResponse)
async def serve_panel():
    with open("panel.html", "r", encoding="utf-8") as f: return f.read()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=__PORT__)
EOF

# ۶. ساخت فایل bot.py
echo "[+] Creating bot.py..."
cat << 'EOF' > bot.py
import asyncio, sqlite3, datetime, time, json, uuid, aiohttp, urllib.parse
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
    ext_proxies = stream_settings.get("externalProxy", [])
    server_ip = default_ip
    port = inbound_port
    if ext_proxies and len(ext_proxies) > 0:
        server_ip = ext_proxies[0].get("dest", default_ip)
        port = ext_proxies[0].get("port", inbound_port)
    params = {"type": net, "security": sec}
    if sec == "tls":
        tls = stream_settings.get("tlsSettings", {})
        if tls.get("serverName"): params["sni"] = tls.get("serverName")
        if tls.get("fingerprint"): params["fp"] = tls.get("fingerprint")
        if tls.get("alpn"): params["alpn"] = ",".join(tls.get("alpn")) if isinstance(tls.get("alpn"), list) else tls.get("alpn")
    elif sec == "reality":
        rs = stream_settings.get("realitySettings", {})
        if rs.get("serverName"): params["sni"] = rs.get("serverName")
        if rs.get("fingerprint"): params["fp"] = rs.get("fingerprint")
        if rs.get("publicKey"): params["pbk"] = rs.get("publicKey")
        if rs.get("shortId"): params["sid"] = rs.get("shortId")
        if rs.get("spiderX"): params["spx"] = rs.get("spiderX")
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
    return f"vless://{client_uuid}@{server_ip}:{port}?{query}#{urllib.parse.quote(remark)}"

async def create_xui_client(url, user, pwd, port, prefix, suffix, volume_gb, days, start_counter):
    url = url.rstrip('/') 
    server_ip_or_domain = urlparse(url).hostname 
    async with aiohttp.ClientSession() as session:
        login_resp = await session.post(f"{url}/login", data={"username": user, "password": pwd})
        if not json.loads(await login_resp.text()).get("success"): return False, "❌ لاگین ناموفق"
        cookie_header = "; ".join([rc.split(';')[0] for rc in login_resp.headers.getall('Set-Cookie', [])])
        headers = {"Accept": "application/json", "Cookie": cookie_header}
        
        sub_settings = {}
        s_resp = await session.post(f"{url}/panel/setting/all", headers=headers)
        if s_resp.status == 404: s_resp = await session.get(f"{url}/panel/setting/all", headers=headers)
        try: sub_settings = (await s_resp.json()).get("obj", {})
        except: pass

        i_resp = await session.get(f"{url}/panel/api/inbounds/list", headers=headers)
        target_inbound = None
        all_remarks = []
        for inbound in (await i_resp.json()).get("obj", []):
            if str(inbound.get("port")) == str(port): target_inbound = inbound
            try:
                for client in json.loads(inbound.get("settings", "{}")).get("clients", []):
                    all_remarks.append(client.get("email", ""))
            except: pass
                
        if not target_inbound: return False, "❌ پورت پیدا نشد!"

        current_counter = start_counter
        while f"{prefix}{suffix}{current_counter}" in all_remarks: current_counter += 1
        remark = f"{prefix}{suffix}{current_counter}"

        client_uuid = str(uuid.uuid4())
        sub_id = str(uuid.uuid4())[:16]
        
        new_client = {
            "id": client_uuid, "alterId": 0, "email": remark, "limitIp": 0,
            "totalGB": int(volume_gb) * 1073741824 if volume_gb > 0 else 0,
            "expiryTime": -(days * 86400 * 1000) if days > 0 else 0,
            "enable": True, "subId": sub_id
        }
        
        add_resp = await session.post(f"{url}/panel/api/inbounds/addClient", json={"id": target_inbound["id"], "settings": json.dumps({"clients": [new_client]})}, headers=headers)
        if json.loads(await add_resp.text()).get("success"):
            sub_domain = sub_settings.get("subDomain", "") or server_ip_or_domain
            sub_port = sub_settings.get("subPort", "")
            sub_path = sub_settings.get("subPath", "/sub/")
            proto = "https" if str(sub_port) in ["443", "2053", "2083", "2096", "8443"] else "http"
            port_str = "" if str(sub_port) in ["80", "443", ""] else f":{sub_port}"
            if not sub_path.startswith('/'): sub_path = '/' + sub_path
            if not sub_path.endswith('/'): sub_path = sub_path + '/'
            sub_link = f"{proto}://{sub_domain}{port_str}{sub_path}{sub_id}"
            
            try: ss = json.loads(target_inbound.get("streamSettings", "{}"))
            except: ss = {}
            return True, {"sub_link": sub_link, "actual_config": build_vless_link(client_uuid, server_ip_or_domain, port, ss, remark), "new_counter": current_counter}
        return False, "❌ خطا در ساخت"

main_keyboard = ReplyKeyboardMarkup(keyboard=[[KeyboardButton(text="🛒 سفارش جدید")], [KeyboardButton(text="📊 گزارش کارکرد"), KeyboardButton(text="🔄 راه‌اندازی مجدد")]], resize_keyboard=True)

@dp.message(CommandStart())
@dp.message(F.text == "🔄 راه‌اندازی مجدد")
async def cmd_start(message: types.Message):
    conn = get_db(); user = conn.execute("SELECT * FROM users WHERE chat_id=?", (str(message.chat.id),)).fetchone(); conn.close()
    if not user: return await message.answer("⛔️ شما دسترسی ندارید.", reply_markup=types.ReplyKeyboardRemove())
    await message.answer(f"سلام {user['owner_name']} عزیز!\nاز منوی پایین انتخاب کنید 👇", reply_markup=main_keyboard)

@dp.message(F.text == "🛒 سفارش جدید")
async def new_order(message: types.Message):
    conn = get_db(); user = conn.execute("SELECT * FROM users WHERE chat_id=?", (str(message.chat.id),)).fetchone()
    if not user: return conn.close()
    allowed = user['allowed_stores'].split(',') if user['allowed_stores'] else []
    b = InlineKeyboardBuilder()
    for sid in allowed:
        if sid:
            store = conn.execute("SELECT * FROM stores WHERE id=?", (sid,)).fetchone()
            if store: b.button(text=f"🏪 {store['name']}", callback_data=f"store_{store['id']}")
    b.adjust(1)
    await message.answer("لطفاً فروشگاه را انتخاب کنید:", reply_markup=b.as_markup())
    conn.close()

@dp.callback_query(F.data.startswith("store_"))
async def show_packages(callback: types.CallbackQuery):
    store_id = callback.data.split("_")[1]
    conn = get_db(); store = conn.execute("SELECT * FROM stores WHERE id=?", (store_id,)).fetchone()
    packages = conn.execute("SELECT * FROM packages WHERE store_id=?", (store_id,)).fetchall(); conn.close()
    b = InlineKeyboardBuilder()
    for pkg in packages: b.button(text=f"📦 {pkg['name']} ({pkg['volume']}GB)", callback_data=f"pkg_{pkg['id']}")
    b.adjust(1)
    await callback.message.edit_text(f"فروشگاه: {store['name']}\nلطفاً پکیج را انتخاب کنید:", reply_markup=b.as_markup())

@dp.callback_query(F.data.startswith("pkg_"))
async def ask_quantity(callback: types.CallbackQuery):
    pkg_id = callback.data.split("_")[1]
    b = InlineKeyboardBuilder()
    b.button(text="۱ عدد", callback_data=f"qty_{pkg_id}_1")
    b.button(text="۵ عدد", callback_data=f"qty_{pkg_id}_5")
    b.button(text="۱۰ عدد", callback_data=f"qty_{pkg_id}_10")
    b.adjust(3)
    await callback.message.edit_text("تعداد کانفیگ مورد نیاز را انتخاب کنید:", reply_markup=b.as_markup())

@dp.callback_query(F.data.startswith("qty_"))
async def generate_configs(callback: types.CallbackQuery):
    _, pkg_id, qty = callback.data.split("_")
    conn = get_db(); pkg = conn.execute("SELECT * FROM packages WHERE id=?", (pkg_id,)).fetchone()
    store = conn.execute("SELECT * FROM stores WHERE id=?", (pkg['store_id'],)).fetchone()
    panel = conn.execute("SELECT * FROM panels WHERE id=?", (store['panel_id'],)).fetchone()
    if not panel:
        panel = conn.execute("SELECT * FROM panels LIMIT 1").fetchone()
        if not panel: return await callback.message.edit_text("❌ هیچ سروری تعریف نشده است!")
    
    await callback.message.edit_text(f"⏳ در حال تولید کانفیگ از سرور {panel['name']}...\nلطفاً صبور باشید.")
    current_counter = store['counter']
    
    for i in range(int(qty)):
        success, result = await create_xui_client(panel['xui_url'], panel['xui_user'], panel['xui_pass'], store['inbound_port'], store['prefix'] or "", pkg['suffix'] or "", pkg['volume'], pkg['days'], current_counter)
        if success:
            smart_counter = result["new_counter"]
            conn.execute("INSERT INTO configs_log (store_id, package_name, volume, created_at) VALUES (?, ?, ?, ?)", (store['id'], pkg['name'], pkg['volume'], datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
            msg = f"✅ کانفیگ شما ساخته شد:\n\n`{result['actual_config']}`\n\n🔗 لینک سابسکریپشن:\n`{result['sub_link']}`\n\n🔢 کد اختصاصی: {smart_counter}"
            await callback.message.answer(msg, parse_mode="Markdown")
            current_counter = smart_counter + 1
        else: await callback.message.answer(f"⚠️ خطا:\n{result}")

    conn.execute("UPDATE stores SET counter=? WHERE id=?", (current_counter, store['id'])); conn.commit(); conn.close()
    await callback.message.delete()

@dp.message(F.text == "📊 گزارش کارکرد")
async def store_report(message: types.Message):
    conn = get_db(); user = conn.execute("SELECT * FROM users WHERE chat_id=?", (str(message.chat.id),)).fetchone()
    if not user: return conn.close()
    report_text = "📊 **گزارش کارکرد شما:**\n\n"
    for store_id in (user['allowed_stores'].split(',') if user['allowed_stores'] else []):
        store = conn.execute("SELECT * FROM stores WHERE id=?", (store_id,)).fetchone()
        if store:
            report_text += f"🏪 **{store['name']}**\n"
            stats = conn.execute('SELECT package_name, COUNT(*) as count FROM configs_log WHERE store_id = ? GROUP BY package_name', (store_id,)).fetchall()
            for stat in stats: report_text += f"▫️ {stat['package_name']}: `{stat['count']} عدد`\n"
            report_text += "➖➖➖➖➖➖➖\n"
    conn.close()
    await message.answer(report_text, parse_mode="Markdown")

if __name__ == "__main__": asyncio.run(dp.start_polling(bot))
EOF

# ۷. ساخت فایل panel.html و جایگذاری یوزر/پسورد وارد شده توسط شما
echo "[+] Creating panel UI..."
cat << 'EOF' > panel.html
<!DOCTYPE html>
<html lang="fa" dir="rtl"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>پنل مدیریت</title><script src="https://cdn.tailwindcss.com"></script><script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.13.3/dist/cdn.min.js"></script><link href="https://v1.fontapi.ir/css/Vazir" rel="stylesheet"><link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"><script> tailwind.config = { theme: { extend: { fontFamily: { sans: ['Vazir', 'sans-serif'] }, colors: { dark: { 900: '#121212', 800: '#1e1e1e', 700: '#2c2c2c', 600: '#3d3d3d' }, pistachio: { 400: '#b4e650', 500: '#9cd33b', 600: '#85b927' } } } } } </script><style> body { font-family: 'Vazir', sans-serif; background-color: #121212; color: #ffffff; -webkit-tap-highlight-color: transparent; } ::-webkit-scrollbar { width: 0px; background: transparent; } .glow-pistachio { box-shadow: 0 0 15px rgba(156, 211, 59, 0.3); } </style></head><body x-data="panelApp()" x-init="initData()" class="antialiased w-full h-screen overflow-hidden flex flex-col">
    <div x-show="!loggedIn" class="flex-1 flex items-center justify-center p-6 bg-dark-900"><div class="w-full max-w-sm bg-dark-800 rounded-3xl p-8 border border-dark-700 shadow-2xl relative"><div class="text-center mb-8 relative z-10"><div class="w-20 h-20 bg-dark-700 rounded-full flex items-center justify-center mx-auto mb-4"><i class="fa-solid fa-fingerprint text-pistachio-500 text-4xl"></i></div><h2 class="text-2xl font-black text-white">ورود مدیریت کل</h2></div><div class="space-y-5"><input x-model="loginUser" type="text" placeholder="نام کاربری" class="w-full bg-dark-700 border border-dark-600 rounded-2xl p-3.5 outline-none"><input x-model="loginPass" type="password" placeholder="رمز عبور" class="w-full bg-dark-700 border border-dark-600 rounded-2xl p-3.5 outline-none"><button @click="doLogin()" class="w-full bg-pistachio-500 text-dark-900 font-extrabold rounded-2xl py-3.5 mt-4 glow-pistachio">ورود</button></div></div></div>
    <div x-show="loggedIn" class="flex flex-col h-screen w-full bg-dark-900" x-cloak><header class="bg-dark-800 px-6 py-4 flex justify-between items-center border-b border-dark-700"><div><h1 class="text-lg font-bold text-white">پنل جامع</h1></div></header>
        <main class="flex-1 overflow-y-auto p-5 pb-36">
            <div x-show="activeTab === 'dashboard'" class="space-y-4"><div class="bg-dark-800 p-5 rounded-3xl border border-dark-700"><p class="text-sm text-gray-400">کل کانفیگ‌ها</p><p class="text-3xl font-black text-white" x-text="stats.total_configs"></p></div></div>
            <div x-show="activeTab === 'stores'" class="space-y-5"><div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 space-y-4"><input x-model="newStore.name" placeholder="نام فروشگاه" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none"><select x-model="newStore.panel_id" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none"><option value="">-- سرور --</option><template x-for="p in panelsList"><option :value="p.id" x-text="p.name"></option></template></select><div class="grid grid-cols-2 gap-3"><input x-model="newStore.inbound_port" placeholder="پورت" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none" dir="ltr"><input x-model="newStore.prefix" placeholder="پیشوند" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none" dir="ltr"></div><input x-model="newStore.counter" placeholder="کانتر شروع" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none" dir="ltr"><button @click="saveStore()" class="w-full bg-pistachio-500 text-dark-900 font-bold py-3.5 rounded-xl">ذخیره</button></div><div class="space-y-3"><template x-for="store in storesList"><div class="flex justify-between bg-dark-900 p-3 rounded-xl border border-dark-600"><div><p class="font-bold" x-text="store.name"></p><p class="text-xs text-gray-400">پورت: <span x-text="store.inbound_port"></span></p></div><button @click="deleteStore(store.id)" class="text-red-500"><i class="fa-solid fa-trash"></i></button></div></template></div></div>
            <div x-show="activeTab === 'packages'" class="space-y-5"><div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 space-y-4"><select x-model="newPackage.store_id" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none"><option value="">-- فروشگاه --</option><template x-for="s in storesList"><option :value="s.id" x-text="s.name"></option></template></select><input x-model="newPackage.name" placeholder="نام دکمه" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none"><div class="grid grid-cols-2 gap-3"><input x-model="newPackage.volume" placeholder="حجم" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none"><input x-model="newPackage.days" placeholder="روز" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none"></div><input x-model="newPackage.suffix" placeholder="پسوند" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none"><button @click="savePackage()" class="w-full bg-pistachio-500 text-dark-900 font-bold py-3.5 rounded-xl">ذخیره</button></div><div class="space-y-3"><template x-for="pkg in packagesList"><div class="flex justify-between bg-dark-900 p-3 rounded-xl border border-dark-600"><div><p class="font-bold" x-text="pkg.name"></p></div><button @click="deletePackage(pkg.id)" class="text-red-500"><i class="fa-solid fa-trash"></i></button></div></template></div></div>
            <div x-show="activeTab === 'users'" class="space-y-5"><div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 space-y-4"><input x-model="newUser.chat_id" placeholder="Chat ID" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none"><input x-model="newUser.owner_name" placeholder="نام نماینده" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none"><div class="space-y-2"><template x-for="s in storesList"><label class="flex items-center gap-2"><input type="checkbox" :value="s.id" x-model="newUser.allowed_stores"><span x-text="s.name"></span></label></template></div><button @click="saveUser()" class="w-full bg-pistachio-500 text-dark-900 font-bold py-3.5 rounded-xl">ذخیره</button></div></div>
            <div x-show="activeTab === 'settings'" class="space-y-5"><div class="bg-dark-800 p-5 rounded-3xl border border-dark-700 space-y-4"><h4 class="text-pistachio-500 font-bold mb-4">سرورها</h4><input x-model="newPanel.name" placeholder="نام سرور" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none"><input x-model="newPanel.xui_url" placeholder="URL" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none"><div class="grid grid-cols-2 gap-3"><input x-model="newPanel.xui_user" placeholder="User" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none"><input x-model="newPanel.xui_pass" placeholder="Pass" class="w-full bg-dark-900 border border-dark-600 rounded-xl p-3 outline-none"></div><button @click="savePanel()" class="w-full bg-pistachio-500 text-dark-900 font-bold py-3.5 rounded-xl">ذخیره</button></div><div class="space-y-3"><template x-for="p in panelsList"><div class="flex justify-between bg-dark-900 p-3 rounded-xl border border-dark-600"><div><p class="font-bold" x-text="p.name"></p></div><button @click="deletePanel(p.id)" class="text-red-500"><i class="fa-solid fa-trash"></i></button></div></template></div></div>
        </main>
        <nav class="fixed bottom-0 w-full bg-dark-800 border-t border-dark-700 py-3"><div class="flex justify-around"><button @click="activeTab='dashboard'" :class="activeTab==='dashboard'?'text-pistachio-500':'text-gray-500'"><i class="fa-solid fa-chart-pie"></i></button><button @click="activeTab='stores'" :class="activeTab==='stores'?'text-pistachio-500':'text-gray-500'"><i class="fa-solid fa-store"></i></button><button @click="activeTab='packages'" :class="activeTab==='packages'?'text-pistachio-500':'text-gray-500'"><i class="fa-solid fa-box"></i></button><button @click="activeTab='users'" :class="activeTab==='users'?'text-pistachio-500':'text-gray-500'"><i class="fa-solid fa-users"></i></button><button @click="activeTab='settings'" :class="activeTab==='settings'?'text-pistachio-500':'text-gray-500'"><i class="fa-solid fa-gear"></i></button></div></nav>
    </div>
    <script>
        function panelApp() { return { loggedIn: false, activeTab: 'dashboard', loginUser: '', loginPass: '', panelsList: [], storesList: [], packagesList: [], usersList: [], stats: { total_configs: 0 }, newPanel: { name: '', xui_url: '', xui_user: '', xui_pass: '' }, newStore: { name: '', panel_id: '', inbound_port: '', prefix: '', counter: '' }, newPackage: { store_id: '', name: '', volume: '', days: '', suffix: '' }, newUser: { chat_id: '', owner_name: '', allowed_stores: [] },
                doLogin() { if(this.loginUser === '__USER__' && this.loginPass === '__PASS__') { this.loggedIn = true; } else { alert('❌ خطا'); } },
                initData() { this.fetchStats(); this.fetchPanels(); this.fetchStores(); this.fetchPackages(); this.fetchUsers(); },
                async fetchStats() { let res = await fetch('/api/stats'); this.stats = await res.json(); },
                async fetchPanels() { let res = await fetch('/api/panels'); this.panelsList = await res.json(); },
                async savePanel() { await fetch('/api/panels', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(this.newPanel) }); this.newPanel = {name:'', xui_url:'', xui_user:'', xui_pass:''}; this.fetchPanels(); },
                async deletePanel(id) { await fetch('/api/panels/' + id, { method: 'DELETE' }); this.fetchPanels(); },
                async fetchStores() { let res = await fetch('/api/stores'); this.storesList = await res.json(); },
                async saveStore() { await fetch('/api/stores', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(this.newStore) }); this.newStore = {name:'', panel_id:'', inbound_port:'', prefix:'', counter:''}; this.fetchStores(); },
                async deleteStore(id) { await fetch('/api/stores/' + id, { method: 'DELETE' }); this.fetchStores(); },
                async fetchPackages() { let res = await fetch('/api/packages'); this.packagesList = await res.json(); },
                async savePackage() { await fetch('/api/packages', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(this.newPackage) }); this.newPackage = {store_id:'', name:'', volume:'', days:'', suffix:''}; this.fetchPackages(); },
                async deletePackage(id) { await fetch('/api/packages/' + id, { method: 'DELETE' }); this.fetchPackages(); },
                async fetchUsers() { let res = await fetch('/api/users'); this.usersList = await res.json(); },
                async saveUser() { await fetch('/api/users', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(this.newUser) }); this.newUser = {chat_id:'', owner_name:'', allowed_stores:[]}; this.fetchUsers(); },
                async deleteUser(id) { await fetch('/api/users/' + id, { method: 'DELETE' }); this.fetchUsers(); } } }
    </script></body></html>
EOF

# جایگذاری متغیرهای وارد شده در فایل‌ها با sed (برای جلوگیری از خطای Bash)
sed -i "s/__PORT__/$PANEL_PORT/g" main.py
sed -i "s/__BOT_TOKEN__/$BOT_TOKEN/g" bot.py
sed -i "s/__USER__/$PANEL_USER/g" panel.html
sed -i "s/__PASS__/$PANEL_PASS/g" panel.html

# ۸. ساخت سرویس Systemd برای همیشه روشن ماندن
echo "[+] Creating Systemd services (Daemonizing)..."
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

# ۹. فعال‌سازی سرویس‌ها
echo "[+] Starting services..."
systemctl daemon-reload
systemctl enable proxy-panel > /dev/null 2>&1
systemctl enable proxy-bot > /dev/null 2>&1
systemctl restart proxy-panel
systemctl restart proxy-bot

# نمایش اطلاعات پایانی
MYIP=$(curl -s ifconfig.me)
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
