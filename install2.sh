#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════
#  🚀 X-UI Proxy Panel Manager - Interactive Installer
# ═══════════════════════════════════════════════════════════════

# ─── Color Palette ───
CLR_RESET='\033[0m'
CLR_BLACK='\033[0;30m'
CLR_RED='\033[0;31m'
CLR_GREEN='\033[0;32m'
CLR_YELLOW='\033[0;33m'
CLR_BLUE='\033[0;34m'
CLR_MAGENTA='\033[0;35m'
CLR_CYAN='\033[0;36m'
CLR_WHITE='\033[0;37m'
CLR_BOLD='\033[1m'
CLR_DIM='\033[2m'

# ─── Helpers ───
print_header() {
    clear 2>/dev/null || true
    echo ""
    echo -e "${CLR_CYAN}${CLR_BOLD}"
    echo "    ██╗  ██╗    ██╗   ██╗    ██╗         ██████╗  ██████╗ ██╗  ██╗██╗   ██╗"
    echo "    ╚██╗██╔╝    ██║   ██║    ██║         ██╔══██╗██╔═══██╗╚██╗██╔╝██║   ██║"
    echo "     ╚███╔╝     ██║   ██║    ██║         ██████╔╝██║   ██║ ╚███╔╝ ██║   ██║"
    echo "     ██╔██╗     ██║   ██║    ██║         ██╔═══╝ ██║   ██║ ██╔██╗ ██║   ██║"
    echo "    ██╔╝ ██╗    ╚██████╔╝    ███████╗    ██║     ╚██████╔╝██╔╝ ██╗╚██████╔╝"
    echo "    ╚═╝  ╚═╝     ╚═════╝     ╚══════╝    ╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ "
    echo -e "${CLR_RESET}"
    echo -e "${CLR_MAGENTA}${CLR_BOLD}              🛡️  Proxy Panel Manager - Interactive Setup  🛡️${CLR_RESET}"
    echo ""
    draw_line 76
    echo ""
}

draw_line() {
    local width=${1:-76}
    printf "${CLR_DIM}"
    printf "%${width}s" | tr ' ' '─'
    printf "${CLR_RESET}\n"
}

draw_box_top() {
    local width=${1:-76}
    printf "${CLR_CYAN}┌"
    printf "%$((width-2))s" | tr ' ' '─'
    printf "┐${CLR_RESET}\n"
}

draw_box_bottom() {
    local width=${1:-76}
    printf "${CLR_CYAN}└"
    printf "%$((width-2))s" | tr ' ' '─'
    printf "┘${CLR_RESET}\n"
}

draw_box_line() {
    local text="$1"
    local width=${2:-76}
    local padding=$(( (width - 2 - ${#text}) / 2 ))
    printf "${CLR_CYAN}│${CLR_RESET}"
    printf "%${padding}s" ""
    printf "%s" "$text"
    printf "%$((width - 2 - padding - ${#text}))s" ""
    printf "${CLR_CYAN}│${CLR_RESET}\n"
}

spinner() {
    local pid=$1
    local msg="$2"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r${CLR_YELLOW}%s${CLR_RESET} %s" "${spin:$i:1}" "$msg"
        sleep 0.1
    done
    printf "\r${CLR_GREEN}✓${CLR_RESET} %s\n" "$msg"
}

progress_bar() {
    local current=$1
    local total=$2
    local msg="$3"
    local width=40
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))
    printf "\r${CLR_BLUE}[${CLR_GREEN}"
    printf "%${filled}s" | tr ' ' '█'
    printf "${CLR_DIM}"
    printf "%${empty}s" | tr ' ' '░'
    printf "${CLR_BLUE}]${CLR_RESET} ${CLR_WHITE}%3d%%${CLR_RESET} %s" $(( current * 100 / total )) "$msg"
}

ask_input() {
    local prompt="$1"
    local var_name="$2"
    local default="$3"
    local is_secret="${4:-false}"
    local required="${5:-true}"
    local validate_regex="${6:-.*}"
    local hint="${7:-}"

    while true; do
        echo ""
        echo -e "${CLR_CYAN}│${CLR_RESET} ${CLR_BOLD}${prompt}${CLR_RESET}"
        if [ -n "$hint" ]; then
            echo -e "${CLR_DIM}  ${hint}${CLR_RESET}"
        fi
        if [ -n "$default" ]; then
            echo -e "${CLR_DIM}  [Default: ${default}]${CLR_RESET}"
        fi
        echo -ne "${CLR_YELLOW}  ➤ ${CLR_RESET}"

        if [ "$is_secret" = "true" ]; then
            read -s input
            echo ""
        else
            read input
        fi

        if [ -z "$input" ] && [ -n "$default" ]; then
            input="$default"
        fi

        if [ "$required" = "true" ] && [ -z "$input" ]; then
            echo -e "${CLR_RED}  ✗ این فیلد الزامی است!${CLR_RESET}"
            continue
        fi

        if [ -n "$input" ] && ! echo "$input" | grep -qE "$validate_regex"; then
            echo -e "${CLR_RED}  ✗ فرمت ورودی نامعتبر!${CLR_RESET}"
            continue
        fi

        eval "$var_name='$input'"
        break
    done
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"

    while true; do
        echo -ne "${CLR_CYAN}│${CLR_RESET} ${CLR_BOLD}${prompt}${CLR_RESET} ${CLR_DIM}[Y/n]:${CLR_RESET} "
        read answer
        answer=${answer:-$default}
        case "$answer" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo -e "${CLR_RED}  لطفاً Y یا N وارد کنید${CLR_RESET}";;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════
#  STEP 0: System Detection
# ═══════════════════════════════════════════════════════════════
print_header

echo -e "${CLR_BOLD}${CLR_WHITE}🔍 در حال شناسایی سیستم...${CLR_RESET}"
draw_line 76

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_NAME=$NAME
    OS_VERSION=$VERSION_ID
else
    echo -e "${CLR_RED}✗ سیستم عامل شناسایی نشد!${CLR_RESET}"
    exit 1
fi

echo -e "${CLR_GREEN}  ✓${CLR_RESET} سیستم عامل: ${CLR_BOLD}${OS_NAME}${CLR_RESET}"
echo -e "${CLR_GREEN}  ✓${CLR_RESET} نسخه: ${CLR_BOLD}${OS_VERSION}${CLR_RESET}"
echo -e "${CLR_GREEN}  ✓${CLR_RESET} معماری: ${CLR_BOLD}$(uname -m)${CLR_RESET}"
echo ""

# ═══════════════════════════════════════════════════════════════
#  STEP 1: Interactive Configuration
# ═══════════════════════════════════════════════════════════════
echo -e "${CLR_BOLD}${CLR_WHITE}⚙️  پیکربندی اولیه${CLR_RESET}"
draw_line 76

ask_input "🌐 پورت پنل وب را وارد کنید" "PANEL_PORT" "8080" "false" "true" "^[0-9]+$" "پورتی که پنل وب روی آن اجرا می‌شود (مثال: 8080, 3000)"
ask_input "🤖 توکن ربات تلگرام را وارد کنید" "BOT_TOKEN" "" "true" "true" "^[0-9]+:.*$" "از @BotFather دریافت کنید"

echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}🔗 اتصال به پنل X-UI${CLR_RESET}"
draw_line 76

ask_input "🖥️  آدرس پنل X-UI" "XUI_URL" "" "false" "true" "^https?://" "مثال: http://1.2.3.4:54321 یا https://panel.example.com:443"
ask_input "👤 نام کاربری X-UI" "XUI_USER" "admin" "false" "true" "" ""
ask_input "🔑 رمز عبور X-UI" "XUI_PASS" "" "true" "true" "" ""

echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}🏪 تنظیمات فروشگاه${CLR_RESET}"
draw_line 76

ask_input "🏷️  نام فروشگاه" "STORE_NAME" "فروشگاه من" "false" "true" "" ""
ask_input "🔌 پورت Inbound" "INBOUND_PORT" "443" "false" "true" "^[0-9]+$" "پورت inbound سرور X-UI (مثال: 443, 8443)"
ask_input "🏷️  پرفیکس نام کاربری" "USER_PREFIX" "User" "false" "false" "" "مثال: User, Client, VIP"
ask_input "🔢 شمارنده شروع" "START_COUNTER" "1" "false" "true" "^[0-9]+$" "شماره شروع برای نام‌گذاری کاربران"

echo ""
if ask_yes_no "🔒 آیا سرور شما فیلتر است و نیاز به تونل VLESS دارید؟" "n"; then
    ask_input "🌐 لینک VLESS تونل را وارد کنید" "VPN_CONFIG" "" "false" "false" "^vless://" "مثال: vless://uuid@server:port?security=tls..."
else
    VPN_CONFIG=""
fi

echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}📦 تنظیمات پکیج پیش‌فرض${CLR_RESET}"
draw_line 76

ask_input "📦 نام پکیج" "PKG_NAME" "پکیج ۱۰ گیگ" "false" "true" "" ""
ask_input "💾 حجم (گیگابایت)" "PKG_VOLUME" "10" "false" "true" "^[0-9]+$" ""
ask_input "📅 مدت زمان (روز)" "PKG_DAYS" "30" "false" "true" "^[0-9]+$" ""
ask_input "🏷️  پسوند نام کاربری" "USER_SUFFIX" "" "false" "false" "" "مثال: -M, -VIP (اختیاری)"

echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}👤 کاربر مدیر ربات${CLR_RESET}"
draw_line 76

ask_input "💬 Chat ID تلگرام مدیر" "ADMIN_CHAT_ID" "" "false" "true" "^[0-9-]+$" "از @userinfobot بگیرید"
ask_input "👤 نام مدیر" "ADMIN_NAME" "مدیر" "false" "true" "" ""

# ═══════════════════════════════════════════════════════════════
#  STEP 2: Confirm Configuration
# ═══════════════════════════════════════════════════════════════
print_header

echo -e "${CLR_BOLD}${CLR_WHITE}📋 خلاصه پیکربندی${CLR_RESET}"
draw_line 76

draw_box_top 76
draw_box_line "🌐 پنل وب: پورت ${PANEL_PORT}" 76
draw_box_line "🤖 ربات: ${BOT_TOKEN:0:20}..." 76
draw_box_line "🖥️  X-UI: ${XUI_URL}" 76
draw_box_line "👤 کاربر X-UI: ${XUI_USER}" 76
draw_box_line "🔑 رمز X-UI: $(printf '%*s' "${#XUI_PASS}" '' | tr ' ' '*')" 76
draw_box_line "🏪 فروشگاه: ${STORE_NAME} | پورت: ${INBOUND_PORT}" 76
draw_box_line "🏷️  پرفیکس: ${USER_PREFIX} | شمارنده: ${START_COUNTER}" 76
if [ -n "$VPN_CONFIG" ]; then
    draw_box_line "🔒 تونل: فعال" 76
else
    draw_box_line "🔒 تونل: غیرفعال" 76
fi
draw_box_line "📦 پکیج: ${PKG_NAME} | ${PKG_VOLUME}GB | ${PKG_DAYS} روز" 76
draw_box_line "👤 مدیر: ${ADMIN_NAME} | Chat ID: ${ADMIN_CHAT_ID}" 76
draw_box_bottom 76

echo ""
if ! ask_yes_no "آیا تنظیمات بالا صحیح است و می‌خواهید ادامه دهید؟" "y"; then
    echo -e "${CLR_RED}❌ نصب لغو شد.${CLR_RESET}"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
#  STEP 3: System Update & Dependencies
# ═══════════════════════════════════════════════════════════════
print_header

echo -e "${CLR_BOLD}${CLR_WHITE}📦 در حال نصب پیش‌نیازهای سیستم...${CLR_RESET}"
draw_line 76

TOTAL_STEPS=7
CURRENT_STEP=0

update_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    progress_bar $CURRENT_STEP $TOTAL_STEPS "$1"
    echo ""
}

(
    if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq python3 python3-pip python3-venv git curl wget sqlite3 net-tools lsof >/dev/null 2>&1
    elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ] || [ "$OS" == "rocky" ] || [ "$OS" == "almalinux" ]; then
        yum update -y -q >/dev/null 2>&1
        yum install -y -q python3 python3-pip git curl wget sqlite3 net-tools lsof >/dev/null 2>&1
    elif [ "$OS" == "arch" ] || [ "$OS" == "manjaro" ]; then
        pacman -Sy --noconfirm -q python python-pip git curl wget sqlite net-tools lsof >/dev/null 2>&1
    else
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq python3 python3-pip git curl wget sqlite3 net-tools lsof >/dev/null 2>&1
    fi
) &
spinner $! "به‌روزرسانی پکیج‌های سیستم"
update_progress "سیستم به‌روز شد"

(
    bash -c "$(curl -L -s https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1
) &
spinner $! "نصب Xray Core"
update_progress "Xray نصب شد"

# ═══════════════════════════════════════════════════════════════
#  STEP 4: Setup Application
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}📁 در حال راه‌اندازی برنامه...${CLR_RESET}"
draw_line 76

APP_DIR="/opt/xui-proxy-panel"
mkdir -p "$APP_DIR"
cd "$APP_DIR"

if [ ! -f "bot.py" ] || [ ! -f "main.py" ]; then
    echo -e "${CLR_YELLOW}⚠️  فایل‌های bot.py و main.py یافت نشد!${CLR_RESET}"
    echo -e "${CLR_DIM}   لطفاً ابتدا فایل‌ها را در ${APP_DIR} کپی کنید.${CLR_RESET}"
    echo ""
    echo -e "${CLR_CYAN}   راهنما:${CLR_RESET}"
    echo -e "   git clone https://github.com/YOUR_USERNAME/xui-proxy-panel.git ${APP_DIR}"
    echo ""
    exit 1
fi

(
    python3 -m venv venv >/dev/null 2>&1
) &
spinner $! "ساخت محیط مجازی Python"
update_progress "venv ساخته شد"

(
    source venv/bin/activate
    pip install --upgrade pip -q >/dev/null 2>&1
    pip install -r requirements.txt -q >/dev/null 2>&1
) &
spinner $! "نصب پیش‌نیازهای Python"
update_progress "پکیج‌های Python نصب شد"

# ═══════════════════════════════════════════════════════════════
#  STEP 5: Create panel.html if missing
# ═══════════════════════════════════════════════════════════════
if [ ! -f "panel.html" ]; then
    cat > panel.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>X-UI Proxy Panel Manager</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',Tahoma,sans-serif;background:#0f172a;color:#e2e8f0;min-height:100vh}
.container{max-width:1200px;margin:0 auto;padding:20px}
h1{text-align:center;color:#38bdf8;margin-bottom:30px}
.card{background:#1e293b;border-radius:12px;padding:20px;margin-bottom:20px;box-shadow:0 4px 6px rgba(0,0,0,0.3)}
input,select,button,textarea{width:100%;padding:12px;margin:8px 0;border-radius:8px;border:1px solid #334155;background:#0f172a;color:#e2e8f0;font-size:14px;font-family:inherit}
button{background:#0ea5e9;border:none;cursor:pointer;font-weight:bold;transition:0.3s}
button:hover{background:#0284c7}
.danger{background:#ef4444}
.danger:hover{background:#dc2626}
table{width:100%;border-collapse:collapse;margin-top:15px}
th,td{padding:12px;text-align:right;border-bottom:1px solid #334155}
th{background:#1e293b;color:#38bdf8}
tr:hover{background:#334155}
.stats{display:flex;justify-content:space-around;flex-wrap:wrap;gap:20px;margin-bottom:30px}
.stat-box{background:#1e293b;padding:20px 40px;border-radius:12px;text-align:center}
.stat-number{font-size:32px;font-weight:bold;color:#38bdf8}
.tabs{display:flex;gap:10px;margin-bottom:20px;flex-wrap:wrap}
.tab{padding:10px 20px;background:#1e293b;border-radius:8px;cursor:pointer;border:1px solid #334155}
.tab.active{background:#0ea5e9;color:white}
.hidden{display:none}
#toast{position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#1e293b;padding:15px 30px;border-radius:8px;border:1px solid #334155;display:none;z-index:1000}
small{color:#94a3b8;display:block;margin-top:4px}
</style>
</head>
<body>
<div class="container">
<h1>🚀 X-UI Proxy Panel Manager</h1>
<div class="stats">
<div class="stat-box"><div class="stat-number" id="totalConfigs">0</div><div>کل کانفیگ‌ها</div></div>
<div class="stat-box"><div class="stat-number" id="activeStores">0</div><div>فروشگاه‌های فعال</div></div>
<div class="stat-box"><div class="stat-number" id="serverTime">-</div><div>زمان سرور</div></div>
</div>
<div class="tabs">
<div class="tab active" onclick="showTab('panels')">🖥️ سرورها</div>
<div class="tab" onclick="showTab('stores')">🏪 فروشگاه‌ها</div>
<div class="tab" onclick="showTab('packages')">📦 پکیج‌ها</div>
<div class="tab" onclick="showTab('users')">👤 کاربران</div>
<div class="tab" onclick="showTab('settings')">⚙️ تنظیمات</div>
<div class="tab" onclick="showTab('reports')">📊 گزارشات</div>
</div>
<div id="panels" class="tab-content">
<div class="card">
<h3>➕ افزودن سرور جدید</h3>
<input type="text" id="panelName" placeholder="نام سرور">
<input type="text" id="panelUrl" placeholder="آدرس X-UI (مثال: http://1.2.3.4:54321)">
<input type="text" id="panelUser" placeholder="نام کاربری">
<input type="password" id="panelPass" placeholder="رمز عبور">
<button onclick="addPanel()">💾 ذخیره سرور</button>
</div>
<div class="card">
<h3>📋 لیست سرورها</h3>
<table><thead><tr><th>ID</th><th>نام</th><th>آدرس</th><th>عملیات</th></tr></thead><tbody id="panelsList"></tbody></table>
</div>
</div>
<div id="stores" class="tab-content hidden">
<div class="card">
<h3>➕ افزودن فروشگاه</h3>
<input type="text" id="storeName" placeholder="نام فروشگاه">
<select id="storePanel"></select>
<input type="number" id="storePort" placeholder="پورت اینباند">
<input type="text" id="storePrefix" placeholder="پرفیکس نام کاربری">
<input type="number" id="storeCounter" placeholder="شمارنده شروع" value="1">
<button onclick="addStore()">💾 ذخیره فروشگاه</button>
</div>
<div class="card">
<h3>📋 لیست فروشگاه‌ها</h3>
<table><thead><tr><th>ID</th><th>نام</th><th>سرور</th><th>پورت</th><th>پرفیکس</th><th>شمارنده</th><th>عملیات</th></tr></thead><tbody id="storesList"></tbody></table>
</div>
</div>
<div id="packages" class="tab-content hidden">
<div class="card">
<h3>➕ افزودن پکیج</h3>
<select id="pkgStore"></select>
<input type="text" id="pkgName" placeholder="نام پکیج">
<input type="number" id="pkgVolume" placeholder="حجم (GB)">
<input type="number" id="pkgDays" placeholder="مدت (روز)">
<input type="text" id="pkgSuffix" placeholder="پسوند نام کاربری">
<button onclick="addPackage()">💾 ذخیره پکیج</button>
</div>
<div class="card">
<h3>📋 لیست پکیج‌ها</h3>
<table><thead><tr><th>ID</th><th>فروشگاه</th><th>نام</th><th>حجم</th><th>روز</th><th>پسوند</th><th>عملیات</th></tr></thead><tbody id="packagesList"></tbody></table>
</div>
</div>
<div id="users" class="tab-content hidden">
<div class="card">
<h3>➕ افزودن کاربر ربات</h3>
<input type="text" id="userChatId" placeholder="Chat ID تلگرام">
<input type="text" id="userName" placeholder="نام صاحب">
<select id="userStores" multiple style="height:100px;"></select>
<small>برای انتخاب چند فروشگاه Ctrl را نگه دارید</small>
<button onclick="addUser()">💾 ذخیره کاربر</button>
</div>
<div class="card">
<h3>📋 لیست کاربران</h3>
<table><thead><tr><th>ID</th><th>Chat ID</th><th>نام</th><th>فروشگاه‌های مجاز</th><th>عملیات</th></tr></thead><tbody id="usersList"></tbody></table>
</div>
</div>
<div id="settings" class="tab-content hidden">
<div class="card">
<h3>⚙️ تنظیمات تونل VPN</h3>
<textarea id="vpnConfig" rows="6" placeholder="لینک VLESS برای تونل (اختیاری)"></textarea>
<small>اگر سرور شما فیلتر است، یک لینک VLESS معتبر اینجا قرار دهید</small>
<button onclick="saveSettings()">💾 ذخیره تنظیمات</button>
</div>
<div class="card">
<h3>💾 Backup & Restore</h3>
<button onclick="downloadBackup()">📥 دانلود بک‌آپ</button>
<input type="file" id="restoreFile" accept=".db" style="margin-top:10px;">
<button onclick="restoreBackup()" class="danger">📤 بازگردانی بک‌آپ</button>
</div>
</div>
<div id="reports" class="tab-content hidden">
<div class="card">
<h3>📊 گزارش کارکرد</h3>
<select id="reportStore"></select>
<input type="date" id="startDate">
<input type="date" id="endDate">
<button onclick="loadReport()">📈 نمایش گزارش</button>
<div id="reportResult" style="margin-top:20px;"></div>
</div>
</div>
</div>
<div id="toast"></div>
<script>
const API='';
function showToast(msg,isError=false){const t=document.getElementById('toast');t.textContent=msg;t.style.color=isError?'#ef4444':'#22c55e';t.style.display='block';setTimeout(()=>t.style.display='none',3000)}
function showTab(tab){document.querySelectorAll('.tab-content').forEach(el=>el.classList.add('hidden'));document.getElementById(tab).classList.remove('hidden');document.querySelectorAll('.tab').forEach(el=>el.classList.remove('active'));event.target.classList.add('active');if(tab!=='panels')loadData()}
async function apiGet(url){const r=await fetch(API+url);return r.json()}
async function apiPost(url,data){const r=await fetch(API+url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});return r.json()}
async function apiDelete(url){const r=await fetch(API+url,{method:'DELETE'});return r.json()}
async function loadStats(){const s=await apiGet('/api/stats');document.getElementById('totalConfigs').textContent=s.total_configs;document.getElementById('activeStores').textContent=s.active_stores;document.getElementById('serverTime').textContent=s.server_time}
async function loadPanels(){const data=await apiGet('/api/panels');let html='';data.forEach(p=>{html+=`<tr><td>${p.id}</td><td>${p.name}</td><td>${p.xui_url}</td><td><button class="danger" onclick="deletePanel(${p.id})">🗑️</button></td></tr>`});document.getElementById('panelsList').innerHTML=html;let opts='';data.forEach(p=>opts+=`<option value="${p.id}">${p.name}</option>`);document.getElementById('storePanel').innerHTML=opts}
async function addPanel(){await apiPost('/api/panels',{name:document.getElementById('panelName').value,xui_url:document.getElementById('panelUrl').value,xui_user:document.getElementById('panelUser').value,xui_pass:document.getElementById('panelPass').value});showToast('✅ سرور ذخیره شد');loadPanels()}
async function deletePanel(id){if(!confirm('آیا مطمئنید؟'))return;await apiDelete('/api/panels/'+id);showToast('🗑️ حذف شد');loadPanels()}
async function loadStores(){const data=await apiGet('/api/stores');let html='';data.forEach(s=>{html+=`<tr><td>${s.id}</td><td>${s.name}</td><td>${s.panel_name||'-'}</td><td>${s.inbound_port}</td><td>${s.prefix}</td><td>${s.counter}</td><td><button class="danger" onclick="deleteStore(${s.id})">🗑️</button></td></tr>`});document.getElementById('storesList').innerHTML=html;let opts='';data.forEach(s=>opts+=`<option value="${s.id}">${s.name}</option>`);document.getElementById('pkgStore').innerHTML=opts;document.getElementById('reportStore').innerHTML=opts;document.getElementById('userStores').innerHTML=opts}
async function addStore(){await apiPost('/api/stores',{name:document.getElementById('storeName').value,panel_id:parseInt(document.getElementById('storePanel').value),inbound_port:parseInt(document.getElementById('storePort').value),prefix:document.getElementById('storePrefix').value,counter:parseInt(document.getElementById('storeCounter').value)});showToast('✅ فروشگاه ذخیره شد');loadStores()}
async function deleteStore(id){if(!confirm('آیا مطمئنید؟'))return;await apiDelete('/api/stores/'+id);showToast('🗑️ حذف شد');loadStores()}
async function loadPackages(){const data=await apiGet('/api/packages');let html='';data.forEach(p=>{html+=`<tr><td>${p.id}</td><td>${p.store_name||'-'}</td><td>${p.name}</td><td>${p.volume}GB</td><td>${p.days}</td><td>${p.suffix}</td><td><button class="danger" onclick="deletePackage(${p.id})">🗑️</button></td></tr>`});document.getElementById('packagesList').innerHTML=html}
async function addPackage(){await apiPost('/api/packages',{store_id:parseInt(document.getElementById('pkgStore').value),name:document.getElementById('pkgName').value,volume:parseInt(document.getElementById('pkgVolume').value),days:parseInt(document.getElementById('pkgDays').value),suffix:document.getElementById('pkgSuffix').value});showToast('✅ پکیج ذخیره شد');loadPackages()}
async function deletePackage(id){if(!confirm('آیا مطمئنید؟'))return;await apiDelete('/api/packages/'+id);showToast('🗑️ حذف شد');loadPackages()}
async function loadUsers(){const data=await apiGet('/api/users');let html='';data.forEach(u=>{html+=`<tr><td>${u.id}</td><td>${u.chat_id}</td><td>${u.owner_name}</td><td>${u.allowed_stores}</td><td><button class="danger" onclick="deleteUser(${u.id})">🗑️</button></td></tr>`});document.getElementById('usersList').innerHTML=html}
async function addUser(){const selected=Array.from(document.getElementById('userStores').selectedOptions).map(o=>parseInt(o.value));await apiPost('/api/users',{chat_id:document.getElementById('userChatId').value,owner_name:document.getElementById('userName').value,allowed_stores:selected});showToast('✅ کاربر ذخیره شد');loadUsers()}
async function deleteUser(id){if(!confirm('آیا مطمئنید؟'))return;await apiDelete('/api/users/'+id);showToast('🗑️ حذف شد');loadUsers()}
async function saveSettings(){await apiPost('/api/settings',{vpn_config:document.getElementById('vpnConfig').value});showToast('✅ تنظیمات ذخیره شد')}
async function loadSettings(){const s=await apiGet('/api/settings');if(s.vpn_config)document.getElementById('vpnConfig').value=s.vpn_config}
function downloadBackup(){window.location.href=API+'/api/backup'}
async function restoreBackup(){const file=document.getElementById('restoreFile').files[0];if(!file)return showToast('❌ فایل انتخاب نشده',true);const form=new FormData();form.append('file',file);await fetch(API+'/api/restore',{method:'POST',body:form});showToast('✅ بک‌آپ بازگردانی شد')}
async function loadReport(){const storeId=document.getElementById('reportStore').value;const start=document.getElementById('startDate').value;const end=document.getElementById('endDate').value;if(!storeId||!start||!end)return showToast('❌ همه فیلدها را پر کنید',true);const data=await apiGet(`/api/reports?store_id=${storeId}&start_date=${start}&end_date=${end}`);let html='<table><thead><tr><th>پکیج</th><th>تعداد</th></tr></thead><tbody>';data.forEach(r=>html+=`<tr><td>${r.package_name}</td><td>${r.count}</td></tr>`);html+='</tbody></table>';document.getElementById('reportResult').innerHTML=html}
function loadData(){loadPanels();loadStores();loadPackages();loadUsers();loadSettings();loadStats()}
setInterval(loadStats,30000);loadData();
</script>
</body>
</html>
HTMLEOF
    echo -e "${CLR_GREEN}  ✓${CLR_RESET} panel.html ساخته شد"
fi
update_progress "فایل‌ها پیکربندی شدند"

# ═══════════════════════════════════════════════════════════════
#  STEP 6: Initialize Database
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}🗄️  در حال راه‌اندازی دیتابیس...${CLR_RESET}"
draw_line 76

(
    source venv/bin/activate
    python3 << 'PYEOF'
import sqlite3
conn = sqlite3.connect('panel_database.db')
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

cursor.execute("CREATE TABLE IF NOT EXISTS stores (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, panel_id INTEGER, inbound_port INTEGER, prefix TEXT, counter INTEGER)")
cursor.execute("CREATE TABLE IF NOT EXISTS packages (id INTEGER PRIMARY KEY AUTOINCREMENT, store_id INTEGER, name TEXT, volume INTEGER, days INTEGER, suffix TEXT)")
cursor.execute("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, chat_id TEXT, owner_name TEXT, allowed_stores TEXT)")
cursor.execute("CREATE TABLE IF NOT EXISTS configs_log (id INTEGER PRIMARY KEY AUTOINCREMENT, store_id INTEGER, package_name TEXT, volume INTEGER, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)")
cursor.execute("CREATE TABLE IF NOT EXISTS settings (id INTEGER PRIMARY KEY AUTOINCREMENT, vpn_config TEXT)")
cursor.execute("CREATE TABLE IF NOT EXISTS panels (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, xui_url TEXT, xui_user TEXT, xui_pass TEXT)")

# Values will be inserted via bash variables after this script
conn.commit()
conn.close()
PYEOF
) &
spinner $! "راه‌اندازی دیتابیس"
update_progress "دیتابیس آماده شد"

# ═══════════════════════════════════════════════════════════════
#  STEP 6b: Insert default data via Python with variables
# ═══════════════════════════════════════════════════════════════
(
    source venv/bin/activate
    python3 -c "
import sqlite3
conn = sqlite3.connect('panel_database.db')
cursor = conn.cursor()

cursor.execute('INSERT INTO panels (name, xui_url, xui_user, xui_pass) VALUES (?, ?, ?, ?)',
    ('سرور اصلی', '${XUI_URL}', '${XUI_USER}', '${XUI_PASS}'))
panel_id = cursor.lastrowid

cursor.execute('INSERT INTO stores (name, panel_id, inbound_port, prefix, counter) VALUES (?, ?, ?, ?, ?)',
    ('${STORE_NAME}', panel_id, ${INBOUND_PORT}, '${USER_PREFIX}', ${START_COUNTER}))
store_id = cursor.lastrowid

cursor.execute('INSERT INTO packages (store_id, name, volume, days, suffix) VALUES (?, ?, ?, ?, ?)',
    (store_id, '${PKG_NAME}', ${PKG_VOLUME}, ${PKG_DAYS}, '${USER_SUFFIX}'))

cursor.execute('INSERT INTO users (chat_id, owner_name, allowed_stores) VALUES (?, ?, ?)',
    ('${ADMIN_CHAT_ID}', '${ADMIN_NAME}', str(store_id)))

vpn = '''${VPN_CONFIG}'''.strip()
if vpn:
    cursor.execute('INSERT INTO settings (vpn_config) VALUES (?)', (vpn,))
else:
    cursor.execute('INSERT INTO settings (vpn_config) VALUES (?)', ('',))

conn.commit()
conn.close()
"
) &
spinner $! "درج داده‌های پیش‌فرض"

# ═══════════════════════════════════════════════════════════════
#  STEP 7: Systemd Services
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}🔧 در حال ساخت سرویس‌های سیستم...${CLR_RESET}"
draw_line 76

cat > /etc/systemd/system/xui-panel-api.service << EOF
[Unit]
Description=X-UI Proxy Panel API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/venv/bin/python ${APP_DIR}/main.py
Restart=always
RestartSec=5
Environment=PORT=${PANEL_PORT}

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/xui-panel-bot.service << EOF
[Unit]
Description=X-UI Proxy Panel Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/venv/bin/python ${APP_DIR}/bot.py
Restart=always
RestartSec=5
Environment=BOT_TOKEN=${BOT_TOKEN}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload >/dev/null 2>&1
systemctl enable xui-panel-api.service >/dev/null 2>&1
systemctl enable xui-panel-bot.service >/dev/null 2>&1

update_progress "سرویس‌ها ساخته شدند"

# ═══════════════════════════════════════════════════════════════
#  STEP 8: Start Services
# ═══════════════════════════════════════════════════════════════
print_header

echo -e "${CLR_BOLD}${CLR_GREEN}🚀 در حال استارت سرویس‌ها...${CLR_RESET}"
draw_line 76

systemctl start xui-panel-api
sleep 2
systemctl start xui-panel-bot
sleep 2

API_STATUS=$(systemctl is-active xui-panel-api)
BOT_STATUS=$(systemctl is-active xui-panel-bot)

echo ""
draw_box_top 76
if [ "$API_STATUS" = "active" ]; then
    draw_box_line "${CLR_GREEN}✓ API Service: RUNNING${CLR_RESET}" 76
else
    draw_box_line "${CLR_RED}✗ API Service: FAILED${CLR_RESET}" 76
fi
if [ "$BOT_STATUS" = "active" ]; then
    draw_box_line "${CLR_GREEN}✓ Bot Service: RUNNING${CLR_RESET}" 76
else
    draw_box_line "${CLR_RED}✗ Bot Service: FAILED${CLR_RESET}" 76
fi
draw_box_bottom 76

# ═══════════════════════════════════════════════════════════════
#  FINAL: Summary
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${CLR_BOLD}${CLR_CYAN}╔══════════════════════════════════════════════════════════════════════╗${CLR_RESET}"
echo -e "${CLR_BOLD}${CLR_CYAN}║${CLR_RESET}           ${CLR_GREEN}🎉 نصب با موفقیت انجام شد! 🎉${CLR_RESET}                      ${CLR_BOLD}${CLR_CYAN}║${CLR_RESET}"
echo -e "${CLR_BOLD}${CLR_CYAN}╚══════════════════════════════════════════════════════════════════════╝${CLR_RESET}"
echo ""

draw_box_top 76
draw_box_line "🌐 پنل وب: ${CLR_CYAN}http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP'):${PANEL_PORT}${CLR_RESET}" 76
draw_box_line "🤖 ربات تلگرام: ${CLR_GREEN}فعال${CLR_RESET}" 76
draw_box_line "🗄️  دیتابیس: ${APP_DIR}/panel_database.db" 76
draw_box_line "📁 مسیر نصب: ${APP_DIR}" 76
draw_box_bottom 76

echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}📋 دستورات مفید:${CLR_RESET}"
draw_line 76
echo -e "${CLR_YELLOW}  systemctl status xui-panel-api${CLR_RESET}    → وضعیت API"
echo -e "${CLR_YELLOW}  systemctl status xui-panel-bot${CLR_RESET}    → وضعیت ربات"
echo -e "${CLR_YELLOW}  journalctl -u xui-panel-api -f${CLR_RESET}    → لاگ API (زنده)"
echo -e "${CLR_YELLOW}  journalctl -u xui-panel-bot -f${CLR_RESET}    → لاگ ربات (زنده)"
echo -e "${CLR_YELLOW}  systemctl restart xui-panel-api${CLR_RESET}   → ری‌استارت API"
echo -e "${CLR_YELLOW}  systemctl restart xui-panel-bot${CLR_RESET}   → ری‌استارت ربات"
echo ""

draw_box_top 76
draw_box_line "${CLR_MAGENTA}⚠️  نکات امنیتی:${CLR_RESET}" 76
draw_box_line "• پورت ${PANEL_PORT} را در فایروال باز کنید" 76
draw_box_line "• توصیه می‌شود Nginx Reverse Proxy استفاده کنید" 76
draw_box_line "• فایل panel_database.db را بک‌آپ بگیرید" 76
draw_box_bottom 76

echo ""
echo -e "${CLR_DIM}  X-UI Proxy Panel Manager - v1.0.0${CLR_RESET}"
echo -e "${CLR_DIM}  Made with ❤️  for the proxy community${CLR_RESET}"
echo ""
