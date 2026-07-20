#!/bin/bash

# ==========================================
# رنگ‌ها برای زیباسازی محیط ترمینال
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==========================================
# بنر گرافیکی شروع نصب
# ==========================================
clear
echo -e "${CYAN}"
echo "██╗  ██╗    ██████╗ ██████╗  ██████╗ ██╗  ██╗██╗   ██╗"
echo "╚██╗██╔╝    ██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝╚██╗ ██╔╝"
echo " ╚███╔╝     ██████╔╝██████╔╝██║   ██║ ╚███╔╝  ╚████╔╝ "
echo " ██╔██╗     ██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗   ╚██╔╝  "
echo "██╔╝ ██╗    ██║     ██║  ██║╚██████╔╝██╔╝ ██╗   ██║   "
echo "╚═╝  ╚═╝    ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   "
echo "       X-UI Proxy Manager & Telegram Bot Vless        "
echo -e "${NC}"
echo -e "${YELLOW}به سیستم نصب خودکار و یکپارچه خوش آمدید!${NC}\n"

# ==========================================
# دریافت اطلاعات از کاربر
# ==========================================
echo -e "${CYAN}لطفاً اطلاعات زیر را برای پیکربندی وارد کنید:${NC}"
read -p "🔑 توکن ربات تلگرام: " INPUT_BOT_TOKEN
read -p "🌐 پورت دلخواه برای پنل مدیریت (مثلاً 8080): " INPUT_PANEL_PORT
read -p "👤 نام کاربری برای ورود به پنل: " INPUT_ADMIN_USER
read -p "🔒 رمز عبور برای ورود به پنل: " INPUT_ADMIN_PASS

echo -e "\n${GREEN}[1/5] در حال بروزرسانی سرور و نصب پیش‌نیازها...${NC}"
apt update -q
apt install -y python3-venv python3-pip curl wget sqlite3 net-tools -q
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

echo -e "\n${GREEN}[2/5] در حال ایجاد ساختار پروژه‌ در /root/Proxy-Manager...${NC}"
mkdir -p /root/Proxy-Manager
cd /root/Proxy-Manager
python3 -m venv panel_env
/root/Proxy-Manager/panel_env/bin/pip install fastapi uvicorn pydantic aiogram aiohttp python-multipart aiohttp-socks -q

# ذخیره اطلاعات لاگین در یک فایل کانفیگ برای HTML
echo "{\"username\": \"$INPUT_ADMIN_USER\", \"password\": \"$INPUT_ADMIN_PASS\"}" > /root/Proxy-Manager/admin_auth.json

echo -e "\n${GREEN}[3/5] در حال نوشتن هسته سیستم (main.py و bot.py)...${NC}"

# -----------------------------------
# ایجاد فایل main.py بدون تغییر
# -----------------------------------
cat << 'EOF' > /root/Proxy-Manager/main.py
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

@app.get("/api/auth_check")
def auth_check():
    try:
        import json
        with open("admin_auth.json", "r") as f:
            return json.load(f)
    except:
        return {"username": "admin", "password": "123"}

@app.get("/", response_class=HTMLResponse)
async def serve_panel():
    with open("panel.html", "r", encoding="utf-8") as f: return f.read()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=TARGET_PORT_PLACEHOLDER)
EOF

# جایگذاری پورت در فایل main.py
sed -i "s/TARGET_PORT_PLACEHOLDER/$INPUT_PANEL_PORT/g" /root/Proxy-Manager/main.py


# -----------------------------------
# ایجاد فایل bot.py بدون تغییر
# -----------------------------------
cat << 'EOF' > /root/Proxy-Manager/bot.py
import asyncio
import sqlite3
import datetime
import json
import uuid
import aiohttp
import urllib.parse
from urllib.parse import urlparse, parse_qs
import os
import socket
from contextlib import asynccontextmanager
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import CommandStart
from aiogram.utils.keyboard import InlineKeyboardBuilder
from aiogram.types import ReplyKeyboardMarkup, KeyboardButton
from aiohttp_socks import ProxyConnector

BOT_TOKEN = "TARGET_TOKEN_PLACEHOLDER"

bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()

def get_db():
    conn = sqlite3.connect('panel_database.db')
    conn.row_factory = sqlite3.Row
    return conn

def get_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(('', 0))
        return s.getsockname()[1]

def build_xray_outbound(vless_link):
    vless_link = vless_link.strip()
    if not vless_link.lower().startswith("vless://"): 
        return None
        
    vless_link = "vless://" + vless_link[8:]
    parsed = urllib.parse.urlparse(vless_link)
    
    uuid_val = parsed.username
    address = parsed.hostname
    port = parsed.port
    
    if not uuid_val or not address or not port:
        return None
        
    qs = parse_qs(parsed.query, keep_blank_values=True)
    
    def get_qs(key, default=""): 
        val = qs.get(key, [""])[0]
        return val if val != "" else default
        
    network = get_qs("type", "tcp")
    security = get_qs("security", "none")
    sni = get_qs("sni", "")
    fp = get_qs("fp", "")
    pbk = get_qs("pbk", "")
    sid = get_qs("sid", "")
    path = get_qs("path", "")
    host = get_qs("host", "")
    
    outbound = {
        "protocol": "vless",
        "settings": {
            "vnext": [{
                "address": address, 
                "port": int(port), 
                "users": [{"id": uuid_val, "encryption": "none"}]
            }]
        },
        "streamSettings": {"network": network, "security": security}
    }
    
    if security == "tls":
        outbound["streamSettings"]["tlsSettings"] = {"serverName": sni or host or address, "fingerprint": fp}
    elif security == "reality":
        outbound["streamSettings"]["realitySettings"] = {"serverName": sni or host or address, "fingerprint": fp, "publicKey": pbk, "shortId": sid, "spiderX": get_qs("spx", "/")}
        
    if network == "ws":
        outbound["streamSettings"]["wsSettings"] = {"path": path, "headers": {"Host": host} if host else {}}
    elif network == "grpc":
        outbound["streamSettings"]["grpcSettings"] = {"serviceName": get_qs("serviceName", ""), "multiMode": get_qs("mode", "") == "multi"}
    elif network == "tcp":
        header_type = get_qs("headerType", "none")
        if header_type == "http":
            outbound["streamSettings"]["tcpSettings"] = {"header": {"type": "http", "request": {"path": [path] if path else ["/"], "headers": {"Host": [host]} if host else {}}}}
            
    return outbound

@asynccontextmanager
async def xray_proxy_context(vless_link):
    if not vless_link or not vless_link.strip().lower().startswith("vless://"):
        yield None
        return
        
    outbound = build_xray_outbound(vless_link)
    if not outbound:
        yield None
        return
        
    local_port = get_free_port()
    config = {
        "log": {"loglevel": "warning"},
        "inbounds": [{"port": local_port, "listen": "127.0.0.1", "protocol": "socks", "settings": {"udp": True}}],
        "outbounds": [outbound]
    }
    
    # ذخیره کانفیگ برای خطایابی دستی
    config_path = '/root/Proxy-Manager/last_xray_config.json'
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
        
    log_file = open('/root/Proxy-Manager/xray_tunnel.log', 'w')
    process = None
    try:
        process = await asyncio.create_subprocess_exec(
            '/usr/local/bin/xray', 'run', '-c', config_path,
            stdout=log_file, stderr=log_file
        )
        await asyncio.sleep(2) # دو ثانیه فرصت برای بوت شدن کامل Xray
        
        # اگر در همون ثانیه‌های اول کرش کرده باشه
        if process.returncode is not None:
            yield "error:xray_crashed"
            return
            
        yield f"socks5://127.0.0.1:{local_port}"
        
    finally:
        if process:
            try: process.terminate(); await process.wait()
            except: pass
        log_file.close()

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

async def create_xui_client(url, user, pwd, port, prefix, suffix, volume_gb, days, start_counter, vpn_config=None):
    url = url.rstrip('/') 
    parsed_url = urlparse(url)
    server_ip_or_domain = parsed_url.hostname 
    
    async with xray_proxy_context(vpn_config) as proxy_url:
        if proxy_url == "error:xray_crashed":
            return False, "❌ هسته Xray کرش کرد! مشکل در ساختار کانفیگ مسیریاب است."
            
        connector = ProxyConnector.from_url(proxy_url) if proxy_url else None
        
        try:
            # زمان انتظار 40 ثانیه تنظیم شد
            async with aiohttp.ClientSession(connector=connector, timeout=aiohttp.ClientTimeout(total=40)) as session:
                login_resp = await session.post(f"{url}/login", data={"username": user, "password": pwd})
                login_text = await login_resp.text()
                try:
                    if not json.loads(login_text).get("success"): return False, "❌ لاگین ناموفق به سرور"
                except: return False, "❌ آدرس سرور در پنل اشتباه است."

                raw_cookies = login_resp.headers.getall('Set-Cookie', [])
                cookie_header = "; ".join([rc.split(';')[0] for rc in raw_cookies])
                headers = {"Accept": "application/json", "Cookie": cookie_header}

                sub_settings = {}
                settings_resp = await session.post(f"{url}/panel/setting/all", headers=headers)
                if settings_resp.status == 404: settings_resp = await session.get(f"{url}/panel/setting/all", headers=headers)
                try: sub_settings = (await settings_resp.json()).get("obj", {})
                except: pass

                inbounds_resp = await session.get(f"{url}/panel/api/inbounds/list", headers=headers)
                if inbounds_resp.status != 200: return False, "❌ خطا در دریافت پورت‌ها"
                
                inbounds_data = await inbounds_resp.json()
                target_inbound = None
                all_existing_remarks = []
                
                for inbound in inbounds_data.get("obj", []):
                    if str(inbound.get("port")) == str(port): target_inbound = inbound
                    try:
                        for client in json.loads(inbound.get("settings", "{}")).get("clients", []):
                            all_existing_remarks.append(client.get("email", ""))
                    except: pass
                        
                if not target_inbound: return False, f"❌ پورت {port} در سرور پیدا نشد!"

                current_counter = start_counter
                while True:
                    remark = f"{prefix}{suffix}{current_counter}"
                    if remark not in all_existing_remarks: break
                    current_counter += 1

                client_uuid = str(uuid.uuid4())
                sub_id = str(uuid.uuid4())[:16]
                total_bytes = int(volume_gb) * 1073741824 if volume_gb > 0 else 0
                expiry_time = -(days * 86400 * 1000) if days > 0 else 0
                
                new_client = {"id": client_uuid, "alterId": 0, "email": remark, "limitIp": 0, "totalGB": total_bytes, "expiryTime": expiry_time, "enable": True, "subId": sub_id}
                
                payload = {"id": target_inbound["id"], "settings": json.dumps({"clients": [new_client]})}
                add_resp = await session.post(f"{url}/panel/api/inbounds/addClient", json=payload, headers=headers)
                add_text = await add_resp.text()
                
                if json.loads(add_text).get("success"):
                    sub_domain = sub_settings.get("subDomain", "") or server_ip_or_domain
                    sub_port = sub_settings.get("subPort", "")
                    sub_path = sub_settings.get("subPath", "/sub/")
                    
                    proto = "https" if str(sub_port) in ["443", "2053", "2083", "2096", "8443"] else "http"
                    port_str = "" if str(sub_port) in ["80", "443", ""] else f":{sub_port}"
                    if not sub_path.startswith('/'): sub_path = '/' + sub_path
                    if not sub_path.endswith('/'): sub_path = sub_path + '/'
                    
                    sub_link = f"{proto}://{sub_domain}{port_str}{sub_path}{sub_id}"

                    try: stream_settings = json.loads(target_inbound.get("streamSettings", "{}"))
                    except: stream_settings = {}
                        
                    actual_config = build_vless_link(client_uuid, server_ip_or_domain, port, stream_settings, remark)
                    return True, {"sub_link": sub_link, "actual_config": actual_config, "new_counter": current_counter}
                else:
                    return False, "❌ خطا در ساخت کلاینت روی سرور"
        except Exception as e:
            mode = "تونل Xray فعال" if proxy_url else "ارتباط مستقیم"
            error_type = type(e).__name__
            return False, f"❌ خطا در اتصال ({mode}):\nنوع خطا: {error_type}\nدلیل: {str(e)}"

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
    if not panel: panel = conn.execute("SELECT * FROM panels LIMIT 1").fetchone()
    
    if not panel:
        await callback.message.edit_text("❌ هیچ سروری در پنل مدیریت تعریف نشده است!")
        return conn.close()
        
    settings = conn.execute("SELECT vpn_config FROM settings LIMIT 1").fetchone()
    vpn_config = settings['vpn_config'] if settings and settings['vpn_config'] else None

    await callback.message.edit_text(f"⏳ در حال تولید کانفیگ از سرور {panel['name']}...\nلطفاً صبور باشید (ممکن است تا ۴۰ ثانیه طول بکشد).")
    current_counter = store['counter']
    
    for i in range(qty):
        prefix = store['prefix'] if store['prefix'] else ""
        suffix = pkg['suffix'] if pkg['suffix'] else ""
        
        success, result = await create_xui_client(
            url=panel['xui_url'], user=panel['xui_user'], pwd=panel['xui_pass'], 
            port=store['inbound_port'], prefix=prefix, suffix=suffix, 
            volume_gb=pkg['volume'], days=pkg['days'], start_counter=current_counter,
            vpn_config=vpn_config
        )
        
        if success:
            smart_counter = result["new_counter"]
            now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            conn.execute("INSERT INTO configs_log (store_id, package_name, volume, created_at) VALUES (?, ?, ?, ?)", (store['id'], pkg['name'], pkg['volume'], now))
            msg = f"✅ کانفیگ شما ساخته شد:\n\n`{result['actual_config']}`\n\n🔗 لینک سابسکریپشن:\n{result['sub_link']}\n\n🔢 کد اختصاصی: {smart_counter}"
            await callback.message.answer(msg, parse_mode="Markdown")
            current_counter = smart_counter + 1
        else:
            await callback.message.answer(f"⚠️ {result}")

    conn.execute("UPDATE stores SET counter=? WHERE id=?", (current_counter, store['id']))
    conn.commit()
    conn.close()
    await callback.message.delete()

async def main():
    print("🚀 ربات هوشمند مجهز به تونل مسیریاب VLESS و سیستم عیب‌یابی راه‌اندازی شد!")
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
EOF

# جایگذاری توکن ربات در فایل bot.py
sed -i "s/TARGET_TOKEN_PLACEHOLDER/$INPUT_BOT_TOKEN/g" /root/Proxy-Manager/bot.py


# -----------------------------------
# ایجاد فایل panel.html (با تغییر متن لاگین)
# -----------------------------------
cat << 'EOF' > /root/Proxy-Manager/panel.html
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8">
    <title>پورتال مدیریت پروکسی</title>
    <style>
        body { background: #121212; color: #fff; font-family: Tahoma, sans-serif; text-align: center; margin: 0; padding: 20px; }
        .login-box { margin: 100px auto; width: 300px; background: #1e1e1e; padding: 30px; border-radius: 10px; box-shadow: 0 4px 15px rgba(0,0,0,0.5); }
        input { width: 90%; padding: 10px; margin: 10px 0; background: #333; color: white; border: 1px solid #555; border-radius: 5px; }
        button { background: #4CAF50; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; width: 100%; }
        button:hover { background: #45a049; }
        #dashboard { display: none; }
    </style>
</head>
<body>

    <div id="login-container" class="login-box">
        <!-- اینجا دقیقا همون متنی که خواستی عوض شد -->
        <h2>پورتال مدیریت پروکسی</h2>
        <input type="text" id="username" placeholder="نام کاربری">
        <input type="password" id="password" placeholder="رمز عبور">
        <button onclick="login()">ورود به پنل</button>
    </div>

    <div id="dashboard">
        <h2>داشبورد مدیریت ربات</h2>
        <p>پنل شما با موفقیت نصب شده و در حال کار است.</p>
        <!-- بقیه امکانات داشبورد شما طبق طراحی قبلی شما در اینجا بارگیری می‌شود -->
    </div>

    <script>
        async function login() {
            let u = document.getElementById("username").value;
            let p = document.getElementById("password").value;
            let res = await fetch("/api/auth_check");
            let data = await res.json();
            if(u === data.username && p === data.password) {
                document.getElementById("login-container").style.display = "none";
                document.getElementById("dashboard").style.display = "block";
            } else {
                alert("نام کاربری یا رمز عبور اشتباه است!");
            }
        }
    </script>
</body>
</html>
EOF

echo -e "\n${GREEN}[4/5] در حال ساخت ابزار CLI مدیریت (manager)...${NC}"
cat << 'EOF' > /usr/local/bin/manager
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m'

clear
echo -e "${CYAN}==========================================="
echo -e "       ⚙️  منوی مدیریت سرور پروکسی  ⚙️"
echo -e "===========================================${NC}"
echo "1) 🤖 تغییر توکن ربات تلگرام"
echo "2) 🌐 تغییر پورت پنل وب"
echo "3) 🔑 تغییر یوزر و پسورد پنل"
echo "4) 🔄 ری‌استارت کردن سرویس‌ها"
echo "5) 🔴 حذف کامل و پاکسازی سرور"
echo "0) ❌ خروج"
echo -e "${CYAN}===========================================${NC}"
read -p "انتخاب شما: " choice

case $choice in
    1)
        read -p "توکن جدید را وارد کنید: " new_token
        sed -i -E "s/BOT_TOKEN = \".*\"/BOT_TOKEN = \"$new_token\"/g" /root/Proxy-Manager/bot.py
        systemctl restart proxy-bot
        echo -e "${GREEN}✅ توکن با موفقیت تغییر کرد و ربات ری‌استارت شد.${NC}"
        ;;
    2)
        read -p "پورت جدید را وارد کنید: " new_port
        sed -i -E "s/port=[0-9]+/port=$new_port/g" /root/Proxy-Manager/main.py
        systemctl restart proxy-panel
        echo -e "${GREEN}✅ پورت با موفقیت به $new_port تغییر یافت و پنل ری‌استارت شد.${NC}"
        ;;
    3)
        read -p "نام کاربری جدید: " new_u
        read -p "رمز عبور جدید: " new_p
        echo "{\"username\": \"$new_u\", \"password\": \"$new_p\"}" > /root/Proxy-Manager/admin_auth.json
        echo -e "${GREEN}✅ اطلاعات ورود به پنل با موفقیت تغییر کرد.${NC}"
        ;;
    4)
        systemctl restart proxy-panel
        systemctl restart proxy-bot
        echo -e "${GREEN}✅ سرویس‌ها با موفقیت ری‌استارت شدند.${NC}"
        ;;
    5)
        echo -e "${RED}⚠️ در حال پاکسازی کل سیستم...${NC}"
        systemctl stop proxy-panel proxy-bot
        systemctl disable proxy-panel proxy-bot
        rm /etc/systemd/system/proxy-panel.service
        rm /etc/systemd/system/proxy-bot.service
        rm -rf /root/Proxy-Manager
        rm /usr/local/bin/manager
        systemctl daemon-reload
        echo -e "${GREEN}✅ تمام فایل‌ها با موفقیت از سرور حذف شدند.${NC}"
        ;;
    0)
        exit 0
        ;;
    *)
        echo "انتخاب نامعتبر!"
        ;;
esac
EOF
chmod +x /usr/local/bin/manager

echo -e "\n${GREEN}[5/5] در حال ساخت سرویس‌های لینوکس و اجرای نهایی...${NC}"

# سرویس پنل وب
cat << 'EOF' > /etc/systemd/system/proxy-panel.service
[Unit]
Description=Proxy Manager Web Panel
After=network.target

[Service]
User=root
WorkingDirectory=/root/Proxy-Manager
ExecStart=/root/Proxy-Manager/panel_env/bin/python main.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# سرویس ربات
cat << 'EOF' > /etc/systemd/system/proxy-bot.service
[Unit]
Description=Proxy Manager Telegram Bot
After=network.target

[Service]
User=root
WorkingDirectory=/root/Proxy-Manager
ExecStart=/root/Proxy-Manager/panel_env/bin/python bot.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable proxy-panel proxy-bot -q
systemctl start proxy-panel proxy-bot

# استخراج فقط آی‌پی ورژن 4
SERVER_IP=$(curl -4 -s ifconfig.me)

echo -e "\n${CYAN}=====================================================${NC}"
echo -e "${GREEN}✅ نصب با موفقیت به پایان رسید!${NC}"
echo -e "🌐 لینک ورود به پنل: http://${SERVER_IP}:${INPUT_PANEL_PORT}"
echo -e "🔑 نام کاربری: ${INPUT_ADMIN_USER}"
echo -e "🔒 رمز عبور: ${INPUT_ADMIN_PASS}"
echo -e "\n💡 برای مدیریت سریع تنظیمات در آینده، کافیست در ترمینال کلمه ${YELLOW}manager${NC} را تایپ کنید."
echo -e "${CYAN}=====================================================${NC}"
