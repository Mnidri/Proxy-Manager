#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════
#  X-UI Proxy Panel Manager - Interactive Installer v2
# ═══════════════════════════════════════════════════════════════

CLR_RESET='\033[0m'
CLR_RED='\033[0;31m'
CLR_GREEN='\033[0;32m'
CLR_YELLOW='\033[0;33m'
CLR_BLUE='\033[0;34m'
CLR_MAGENTA='\033[0;35m'
CLR_CYAN='\033[0;36m'
CLR_WHITE='\033[0;37m'
CLR_BOLD='\033[1m'
CLR_DIM='\033[2m'

APP_DIR="/opt/xui-proxy-panel"
DB_FILE="$APP_DIR/panel_database.db"
REPO_BASE="https://raw.githubusercontent.com/Mnidri/Proxy-Manager/main"

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
    echo -e "${CLR_MAGENTA}${CLR_BOLD}              Proxy Panel Manager - Interactive Setup  ${CLR_RESET}"
    echo ""
    printf "${CLR_DIM}"
    printf "%76s" | tr ' ' '─'
    printf "${CLR_RESET}\n"
    echo ""
}

draw_box_top() {
    printf "${CLR_CYAN}┌"
    printf "%74s" | tr ' ' '─'
    printf "┐${CLR_RESET}\n"
}
draw_box_bottom() {
    printf "${CLR_CYAN}└"
    printf "%74s" | tr ' ' '─'
    printf "┘${CLR_RESET}\n"
}
draw_box_line() {
    local text="$1"
    local padding=$(( (76 - ${#text}) / 2 ))
    printf "${CLR_CYAN}│${CLR_RESET}"
    printf "%${padding}s" ""
    printf "%s" "$text"
    printf "%$((76 - padding - ${#text}))s" ""
    printf "${CLR_CYAN}│${CLR_RESET}\n"
}

spinner() {
    local pid=$1; local msg="$2"
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
    local current=$1; local total=$2; local msg="$3"
    local width=40
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))
    printf "\r${CLR_BLUE}[${CLR_GREEN}"
    printf "%${filled}s" | tr ' ' '█'
    printf "${CLR_DIM}"
    printf "%${empty}s" | tr ' ' '░'
    printf "${CLR_BLUE}]${CLR_RESET} ${CLR_WHITE}%3d%%${CLR_RESET} %s" $(( current * 100 / total )) "$msg"
}

validate_url() {
    local url="$1"
    [[ "$url" == http://* || "$url" == https://* ]]
}
validate_token() {
    local tok="$1"
    [[ "$tok" == [0-9]*:* ]]
}
validate_number() {
    local n="$1"
    [[ "$n" =~ ^[0-9]+$ ]]
}
validate_chatid() {
    local cid="$1"
    [[ "$cid" =~ ^-?[0-9]+$ ]]
}

ask_input() {
    local prompt="$1"; local var_name="$2"; local default="$3"
    local is_secret="${4:-false}"; local required="${5:-true}"
    local validator="${6:-}"; local hint="${7:-}"
    
    while true; do
        echo ""
        echo -e "${CLR_CYAN}│${CLR_RESET} ${CLR_BOLD}${prompt}${CLR_RESET}"
        [ -n "$hint" ] && echo -e "${CLR_DIM}  ${hint}${CLR_RESET}"
        [ -n "$default" ] && echo -e "${CLR_DIM}  [پیش‌فرض: ${default}]${CLR_RESET}"
        echo -ne "${CLR_YELLOW}  ➤ ${CLR_RESET}"
        
        if [ "$is_secret" = "true" ]; then
            read -s input; echo ""
        else
            read input
        fi
        
        [ -z "$input" ] && [ -n "$default" ] && input="$default"
        
        if [ "$required" = "true" ] && [ -z "$input" ]; then
            echo -e "${CLR_RED}  ✗ این فیلد الزامی است!${CLR_RESET}"
            continue
        fi
        
        if [ -n "$validator" ] && [ -n "$input" ]; then
            local valid=0
            case "$validator" in
                "url") validate_url "$input" && valid=1 ;;
                "token") validate_token "$input" && valid=1 ;;
                "number") validate_number "$input" && valid=1 ;;
                "chatid") validate_chatid "$input" && valid=1 ;;
                *) valid=1 ;;
            esac
            if [ $valid -eq 0 ]; then
                echo -e "${CLR_RED}  ✗ فرمت ورودی نامعتبر!${CLR_RESET}"
                continue
            fi
        fi
        
        eval "$var_name='$input'"
        break
    done
}

ask_yes_no() {
    local prompt="$1"; local default="${2:-y}"
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
#  CHECK: Existing Installation
# ═══════════════════════════════════════════════════════════════
print_header

IS_UPDATE=false
if [ -d "$APP_DIR" ] && [ -f "$DB_FILE" ]; then
    echo -e "${CLR_YELLOW}⚠️  نصب قبلی شناسایی شد در: ${APP_DIR}${CLR_RESET}"
    echo ""
    draw_box_top
    draw_box_line "${CLR_YELLOW}🔧 نصب قبلی یافت شد${CLR_RESET}"
    draw_box_bottom
    echo ""
    
    if ask_yes_no "آیا می‌خواهید نصب قبلی را آپدیت کنید؟ (فایل‌ها جایگزین، دیتابیس حفظ)" "y"; then
        IS_UPDATE=true
        echo -e "${CLR_BLUE}  🔄 حالت آپدیت فعال شد...${CLR_RESET}"
        sleep 1
    else
        if ask_yes_no "آیا می‌خواهید نصب قبلی را حذف و نصب تمیز انجام دهید؟" "n"; then
            echo -e "${CLR_YELLOW}  🗑️ در حال حذف نصب قبلی...${CLR_RESET}"
            systemctl stop xui-panel-api 2>/dev/null || true
            systemctl stop xui-panel-bot 2>/dev/null || true
            systemctl disable xui-panel-api 2>/dev/null || true
            systemctl disable xui-panel-bot 2>/dev/null || true
            rm -f /etc/systemd/system/xui-panel-*.service
            rm -rf "$APP_DIR"
            systemctl daemon-reload 2>/dev/null || true
            echo -e "${CLR_GREEN}  ✓ نصب قبلی حذف شد${CLR_RESET}"
            IS_UPDATE=false
        else
            echo -e "${CLR_RED}❌ نصب لغو شد.${CLR_RESET}"
            exit 0
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════
#  LOAD: Existing Config (if update)
# ═══════════════════════════════════════════════════════════════
load_existing_config() {
    if [ "$IS_UPDATE" = "true" ] && [ -f "$DB_FILE" ]; then
        echo -e "${CLR_BLUE}  📖 در حال خواندن تنظیمات قبلی...${CLR_RESET}"
        
        local config_data
        config_data=$(python3 -c "
import sqlite3, json
try:
    conn = sqlite3.connect(\'$DB_FILE\')
    c = conn.cursor()
    c.execute(\'SELECT xui_url, xui_user, xui_pass FROM panels LIMIT 1\')
    panel = c.fetchone()
    c.execute(\'SELECT name, inbound_port, prefix, counter FROM stores LIMIT 1\')
    store = c.fetchone()
    c.execute(\'SELECT name, volume, days, suffix FROM packages LIMIT 1\')
    pkg = c.fetchone()
    c.execute(\'SELECT chat_id, owner_name FROM users LIMIT 1\')
    user = c.fetchone()
    c.execute(\'SELECT vpn_config FROM settings LIMIT 1\')
    setting = c.fetchone()
    result = {}
    if panel: result[\'xui_url\']=panel[0]; result[\'xui_user\']=panel[1]; result[\'xui_pass\']=panel[2]
    if store: result[\'store_name\']=store[0]; result[\'inbound_port\']=store[1]; result[\'prefix\']=store[2]; result[\'counter\']=store[3]
    if pkg: result[\'pkg_name\']=pkg[0]; result[\'pkg_volume\']=pkg[1]; result[\'pkg_days\']=pkg[2]; result[\'pkg_suffix\']=pkg[3]
    if user: result[\'chat_id\']=user[0]; result[\'owner_name\']=user[1]
    if setting: result[\'vpn_config\']=setting[0] if setting[0] else \'\'
    print(json.dumps(result, ensure_ascii=False))
except:
    print(\'{}\')
" 2>/dev/null || echo "{}")
        
        eval "$(echo "$config_data" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for k,v in d.items():
    if v is not None:
        print(f\"OLD_{k.upper()}='{str(v).replace(chr(39), chr(39)+chr(39))}'\")
" 2>/dev/null)" || true
        
        echo -e "${CLR_GREEN}  ✓ تنظیمات قبلی خوانده شد${CLR_RESET}"
    fi
}

# ═══════════════════════════════════════════════════════════════
#  STEP 1: Interactive Configuration
# ═══════════════════════════════════════════════════════════════
if [ "$IS_UPDATE" = "true" ]; then
    load_existing_config
    print_header
    echo -e "${CLR_BOLD}${CLR_WHITE}⚙️  آپدیت تنظیمات (Enter برای حفظ مقدار قبلی)${CLR_RESET}"
else
    print_header
    echo -e "${CLR_BOLD}${CLR_WHITE}⚙️  پیکربندی اولیه${CLR_RESET}"
fi

printf "${CLR_DIM}"
printf "%76s" | tr ' ' '─'
printf "${CLR_RESET}\n"

show_old() {
    local val="$1"
    [ -n "$val" ] && echo -e "${CLR_DIM}  [قبلی: ${val}]${CLR_RESET}"
}

ask_input "🌐 پورت پنل وب" "PANEL_PORT" "8080" "false" "true" "number" "پورتی که پنل وب روی آن اجرا می‌شود"
ask_input "🤖 توکن ربات تلگرام" "BOT_TOKEN" "" "true" "true" "token" "از @BotFather دریافت کنید"

echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}🔗 اتصال به پنل X-UI${CLR_RESET}"
printf "${CLR_DIM}"
printf "%76s" | tr ' ' '─'
printf "${CLR_RESET}\n"

show_old "${OLD_XUI_URL:-}"
ask_input "🖥️  آدرس پنل X-UI" "XUI_URL" "${OLD_XUI_URL:-}" "false" "true" "url" "مثال: http://1.2.3.4:54321"

show_old "${OLD_XUI_USER:-}"
ask_input "👤 نام کاربری X-UI" "XUI_USER" "${OLD_XUI_USER:-admin}" "false" "true" "" ""

show_old "${OLD_XUI_PASS:-}"
if [ -n "${OLD_XUI_PASS:-}" ]; then
    echo -e "${CLR_DIM}  [رمز قبلی: $(printf '%*s' "${#OLD_XUI_PASS}" '' | tr ' ' '*')]${CLR_RESET}"
fi
ask_input "🔑 رمز عبور X-UI" "XUI_PASS" "${OLD_XUI_PASS:-}" "true" "true" "" ""

echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}🏪 تنظیمات فروشگاه${CLR_RESET}"
printf "${CLR_DIM}"
printf "%76s" | tr ' ' '─'
printf "${CLR_RESET}\n"

show_old "${OLD_STORE_NAME:-}"
ask_input "🏷️  نام فروشگاه" "STORE_NAME" "${OLD_STORE_NAME:-فروشگاه من}" "false" "true" "" ""

show_old "${OLD_INBOUND_PORT:-}"
ask_input "🔌 پورت Inbound" "INBOUND_PORT" "${OLD_INBOUND_PORT:-443}" "false" "true" "number" "پورت inbound سرور X-UI"

show_old "${OLD_PREFIX:-}"
ask_input "🏷️  پرفیکس نام کاربری" "USER_PREFIX" "${OLD_PREFIX:-User}" "false" "false" "" "مثال: User, Client, VIP"

show_old "${OLD_COUNTER:-}"
ask_input "🔢 شمارنده شروع" "START_COUNTER" "${OLD_COUNTER:-1}" "false" "true" "number" ""

echo ""
if ask_yes_no "🔒 آیا نیاز به تونل VLESS دارید؟" "${OLD_VPN_CONFIG:+y}"; then
    show_old "${OLD_VPN_CONFIG:-}"
    ask_input "🌐 لینک VLESS تونل" "VPN_CONFIG" "${OLD_VPN_CONFIG:-}" "false" "false" "" "مثال: vless://uuid@server:port?..."
else
    VPN_CONFIG=""
fi

echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}📦 تنظیمات پکیج پیش‌فرض${CLR_RESET}"
printf "${CLR_DIM}"
printf "%76s" | tr ' ' '─'
printf "${CLR_RESET}\n"

show_old "${OLD_PKG_NAME:-}"
ask_input "📦 نام پکیج" "PKG_NAME" "${OLD_PKG_NAME:-پکیج ۱۰ گیگ}" "false" "true" "" ""

show_old "${OLD_PKG_VOLUME:-}"
ask_input "💾 حجم (گیگابایت)" "PKG_VOLUME" "${OLD_PKG_VOLUME:-10}" "false" "true" "number" ""

show_old "${OLD_PKG_DAYS:-}"
ask_input "📅 مدت زمان (روز)" "PKG_DAYS" "${OLD_PKG_DAYS:-30}" "false" "true" "number" ""

show_old "${OLD_PKG_SUFFIX:-}"
ask_input "🏷️  پسوند نام کاربری" "USER_SUFFIX" "${OLD_PKG_SUFFIX:-}" "false" "false" "" "اختیاری"

echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}👤 کاربر مدیر ربات${CLR_RESET}"
printf "${CLR_DIM}"
printf "%76s" | tr ' ' '─'
printf "${CLR_RESET}\n"

show_old "${OLD_CHAT_ID:-}"
ask_input "💬 Chat ID تلگرام مدیر" "ADMIN_CHAT_ID" "${OLD_CHAT_ID:-}" "false" "true" "chatid" "از @userinfobot بگیرید"

show_old "${OLD_OWNER_NAME:-}"
ask_input "👤 نام مدیر" "ADMIN_NAME" "${OLD_OWNER_NAME:-مدیر}" "false" "true" "" ""

# ═══════════════════════════════════════════════════════════════
#  STEP 2: Confirm
# ═══════════════════════════════════════════════════════════════
print_header

echo -e "${CLR_BOLD}${CLR_WHITE}📋 خلاصه پیکربندی${CLR_RESET}"
printf "${CLR_DIM}"
printf "%76s" | tr ' ' '─'
printf "${CLR_RESET}\n"

draw_box_top
draw_box_line "🌐 پنل وب: پورت ${PANEL_PORT}"
draw_box_line "🤖 ربات: ${BOT_TOKEN:0:20}..."
draw_box_line "🖥️  X-UI: ${XUI_URL}"
draw_box_line "👤 کاربر X-UI: ${XUI_USER}"
draw_box_line "🔑 رمز X-UI: $(printf '%*s' "${#XUI_PASS}" '' | tr ' ' '*')"
draw_box_line "🏪 فروشگاه: ${STORE_NAME} | پورت: ${INBOUND_PORT}"
draw_box_line "🏷️  پرفیکس: ${USER_PREFIX} | شمارنده: ${START_COUNTER}"
if [ -n "$VPN_CONFIG" ]; then
    draw_box_line "🔒 تونل: فعال"
else
    draw_box_line "🔒 تونل: غیرفعال"
fi
draw_box_line "📦 پکیج: ${PKG_NAME} | ${PKG_VOLUME}GB | ${PKG_DAYS} روز"
draw_box_line "👤 مدیر: ${ADMIN_NAME} | Chat ID: ${ADMIN_CHAT_ID}"
if [ "$IS_UPDATE" = "true" ]; then
    draw_box_line "${CLR_YELLOW}🔄 حالت: آپدیت (دیتابیس حفظ می‌شود)${CLR_RESET}"
else
    draw_box_line "${CLR_GREEN}🆕 حالت: نصب جدید${CLR_RESET}"
fi
draw_box_bottom

echo ""
if ! ask_yes_no "آیا تنظیمات صحیح است و ادامه می‌دهید؟" "y"; then
    echo -e "${CLR_RED}❌ لغو شد.${CLR_RESET}"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
#  STEP 3: System Dependencies
# ═══════════════════════════════════════════════════════════════
print_header

echo -e "${CLR_BOLD}${CLR_WHITE}📦 در حال نصب پیش‌نیازهای سیستم...${CLR_RESET}"
printf "${CLR_DIM}"
printf "%76s" | tr ' ' '─'
printf "${CLR_RESET}\n"

TOTAL_STEPS=8
CURRENT_STEP=0
update_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    progress_bar $CURRENT_STEP $TOTAL_STEPS "$1"
    echo ""
}

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS="unknown"
fi

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
spinner $! "نصب پکیج‌های سیستم"
update_progress "سیستم آماده شد"

(
    bash -c "$(curl -L -s https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1
) &
spinner $! "نصب Xray Core"
update_progress "Xray نصب شد"

# ═══════════════════════════════════════════════════════════════
#  STEP 4: Download / Update Files
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}📁 در حال آماده‌سازی فایل‌ها...${CLR_RESET}"
printf "${CLR_DIM}"
printf "%76s" | tr ' ' '─'
printf "${CLR_RESET}\n"

mkdir -p "$APP_DIR"
cd "$APP_DIR"

if [ ! -f "bot.py" ] || [ "$IS_UPDATE" = "true" ]; then
    ( curl -fsSL "${REPO_BASE}/bot.py" -o bot.py.tmp >/dev/null 2>&1 && mv bot.py.tmp bot.py ) &
    spinner $! "دانلود bot.py"
else
    echo -e "${CLR_GREEN}  ✓${CLR_RESET} bot.py موجود است"
fi

if [ ! -f "main.py" ] || [ "$IS_UPDATE" = "true" ]; then
    ( curl -fsSL "${REPO_BASE}/main.py" -o main.py.tmp >/dev/null 2>&1 && mv main.py.tmp main.py ) &
    spinner $! "دانلود main.py"
else
    echo -e "${CLR_GREEN}  ✓${CLR_RESET} main.py موجود است"
fi

if [ ! -f "requirements.txt" ] || [ "$IS_UPDATE" = "true" ]; then
    curl -fsSL "${REPO_BASE}/requirements.txt" -o requirements.txt >/dev/null 2>&1 || true
fi

if [ ! -f "panel.html" ] || [ "$IS_UPDATE" = "true" ]; then
    curl -fsSL "${REPO_BASE}/panel.html" -o panel.html >/dev/null 2>&1 || true
fi

if [ ! -f "bot.py" ] || [ ! -f "main.py" ]; then
    echo -e "${CLR_RED}❌ فایل‌های اصلی دانلود نشدند!${CLR_RESET}"
    exit 1
fi

update_progress "فایل‌ها آماده شدند"

# ═══════════════════════════════════════════════════════════════
#  STEP 5: Python Environment
# ═══════════════════════════════════════════════════════════════
if [ ! -d "$APP_DIR/venv" ] || [ "$IS_UPDATE" = "true" ]; then
    (
        if [ ! -d "$APP_DIR/venv" ]; then
            python3 -m venv venv >/dev/null 2>&1
        fi
        source venv/bin/activate
        pip install --upgrade pip -q >/dev/null 2>&1
        pip install -r requirements.txt -q >/dev/null 2>&1
    ) &
    spinner $! "نصب پیش‌نیازهای Python"
    update_progress "Python آماده شد"
else
    echo -e "${CLR_GREEN}  ✓${CLR_RESET} محیط Python موجود است"
    update_progress "Python آماده شد"
fi

# ═══════════════════════════════════════════════════════════════
#  STEP 6: Database Setup
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}🗄️  در حال پیکربندی دیتابیس...${CLR_RESET}"
printf "${CLR_DIM}"
printf "%76s" | tr ' ' '─'
printf "${CLR_RESET}\n"

if [ "$IS_UPDATE" = "true" ] && [ -f "$DB_FILE" ]; then
    (
        source venv/bin/activate
        python3 -c "
import sqlite3
conn = sqlite3.connect(\'$DB_FILE\')
cursor = conn.cursor()

cursor.execute(\'SELECT id FROM panels LIMIT 1\')
row = cursor.fetchone()
if row:
    cursor.execute(\'UPDATE panels SET name=?, xui_url=?, xui_user=?, xui_pass=? WHERE id=?\',
        (\'سرور اصلی\', \'${XUI_URL}\', \'${XUI_USER}\', \'${XUI_PASS}\', row[0]))
else:
    cursor.execute(\'INSERT INTO panels (name, xui_url, xui_user, xui_pass) VALUES (?, ?, ?, ?)\',
        (\'سرور اصلی\', \'${XUI_URL}\', \'${XUI_USER}\', \'${XUI_PASS}\'))

cursor.execute(\'SELECT id FROM stores LIMIT 1\')
row = cursor.fetchone()
if row:
    cursor.execute(\'UPDATE stores SET name=?, inbound_port=?, prefix=?, counter=? WHERE id=?\',
        (\'${STORE_NAME}\', ${INBOUND_PORT}, \'${USER_PREFIX}\', ${START_COUNTER}, row[0]))
    store_id = row[0]
else:
    cursor.execute(\'SELECT id FROM panels LIMIT 1\')
    panel_id = cursor.fetchone()[0]
    cursor.execute(\'INSERT INTO stores (name, panel_id, inbound_port, prefix, counter) VALUES (?, ?, ?, ?, ?)\',
        (\'${STORE_NAME}\', panel_id, ${INBOUND_PORT}, \'${USER_PREFIX}\', ${START_COUNTER}))
    store_id = cursor.lastrowid

cursor.execute(\'SELECT id FROM packages LIMIT 1\')
row = cursor.fetchone()
if row:
    cursor.execute(\'UPDATE packages SET name=?, volume=?, days=?, suffix=? WHERE id=?\',
        (\'${PKG_NAME}\', ${PKG_VOLUME}, ${PKG_DAYS}, \'${USER_SUFFIX}\', row[0]))
else:
    cursor.execute(\'INSERT INTO packages (store_id, name, volume, days, suffix) VALUES (?, ?, ?, ?, ?)\',
        (store_id, \'${PKG_NAME}\', ${PKG_VOLUME}, ${PKG_DAYS}, \'${USER_SUFFIX}\'))

cursor.execute(\'SELECT id FROM users LIMIT 1\')
row = cursor.fetchone()
if row:
    cursor.execute(\'UPDATE users SET chat_id=?, owner_name=? WHERE id=?\',
        (\'${ADMIN_CHAT_ID}\', \'${ADMIN_NAME}\', row[0]))
else:
    cursor.execute(\'INSERT INTO users (chat_id, owner_name, allowed_stores) VALUES (?, ?, ?)\',
        (\'${ADMIN_CHAT_ID}\', \'${ADMIN_NAME}\', str(store_id)))

cursor.execute(\'SELECT id FROM settings LIMIT 1\')
row = cursor.fetchone()
vpn_val = \'${VPN_CONFIG}\'.strip()
if row:
    cursor.execute(\'UPDATE settings SET vpn_config=? WHERE id=?\', (vpn_val, row[0]))
else:
    cursor.execute(\'INSERT INTO settings (vpn_config) VALUES (?)\', (vpn_val,))

conn.commit()
conn.close()
print(\'Database updated\')
" 2>/dev/null
    ) &
    spinner $! "آپدیت دیتابیس"
else
    (
        source venv/bin/activate
        python3 -c "
import sqlite3
conn = sqlite3.connect(\'$DB_FILE\')
cursor = conn.cursor()

cursor.execute(\'CREATE TABLE IF NOT EXISTS stores (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, panel_id INTEGER, inbound_port INTEGER, prefix TEXT, counter INTEGER)\')
cursor.execute(\'CREATE TABLE IF NOT EXISTS packages (id INTEGER PRIMARY KEY AUTOINCREMENT, store_id INTEGER, name TEXT, volume INTEGER, days INTEGER, suffix TEXT)\')
cursor.execute(\'CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, chat_id TEXT, owner_name TEXT, allowed_stores TEXT)\')
cursor.execute(\'CREATE TABLE IF NOT EXISTS configs_log (id INTEGER PRIMARY KEY AUTOINCREMENT, store_id INTEGER, package_name TEXT, volume INTEGER, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)\')
cursor.execute(\'CREATE TABLE IF NOT EXISTS settings (id INTEGER PRIMARY KEY AUTOINCREMENT, vpn_config TEXT)\')
cursor.execute(\'CREATE TABLE IF NOT EXISTS panels (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, xui_url TEXT, xui_user TEXT, xui_pass TEXT)\')

cursor.execute(\'INSERT INTO panels (name, xui_url, xui_user, xui_pass) VALUES (?, ?, ?, ?)\',
    (\'سرور اصلی\', \'${XUI_URL}\', \'${XUI_USER}\', \'${XUI_PASS}\'))
panel_id = cursor.lastrowid

cursor.execute(\'INSERT INTO stores (name, panel_id, inbound_port, prefix, counter) VALUES (?, ?, ?, ?, ?)\',
    (\'${STORE_NAME}\', panel_id, ${INBOUND_PORT}, \'${USER_PREFIX}\', ${START_COUNTER}))
store_id = cursor.lastrowid

cursor.execute(\'INSERT INTO packages (store_id, name, volume, days, suffix) VALUES (?, ?, ?, ?, ?)\',
    (store_id, \'${PKG_NAME}\', ${PKG_VOLUME}, ${PKG_DAYS}, \'${USER_SUFFIX}\'))

cursor.execute(\'INSERT INTO users (chat_id, owner_name, allowed_stores) VALUES (?, ?, ?)\',
    (\'${ADMIN_CHAT_ID}\', \'${ADMIN_NAME}\', str(store_id)))

vpn_val = \'${VPN_CONFIG}\'.strip()
cursor.execute(\'INSERT INTO settings (vpn_config) VALUES (?)\', (vpn_val,))

conn.commit()
conn.close()
print(\'Database created\')
" 2>/dev/null
    ) &
    spinner $! "ساخت دیتابیس"
fi

update_progress "دیتابیس آماده شد"

# ═══════════════════════════════════════════════════════════════
#  STEP 7: Update Bot Token
# ═══════════════════════════════════════════════════════════════
sed -i "s|BOT_TOKEN = \"[^\"]*\"|BOT_TOKEN = \"${BOT_TOKEN}\"|g" "$APP_DIR/bot.py" 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════
#  STEP 8: Systemd Services
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}🔧 در حال ساخت سرویس‌های سیستم...${CLR_RESET}"
printf "${CLR_DIM}"
printf "%76s" | tr ' ' '─'
printf "${CLR_RESET}\n"

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

update_progress "سرویس‌ها آماده شدند"

# ═══════════════════════════════════════════════════════════════
#  STEP 9: Start Services
# ═══════════════════════════════════════════════════════════════
print_header

echo -e "${CLR_BOLD}${CLR_GREEN}🚀 در حال استارت سرویس‌ها...${CLR_RESET}"
printf "${CLR_DIM}"
printf "%76s" | tr ' ' '─'
printf "${CLR_RESET}\n"

systemctl restart xui-panel-api
sleep 2
systemctl restart xui-panel-bot
sleep 2

API_STATUS=$(systemctl is-active xui-panel-api)
BOT_STATUS=$(systemctl is-active xui-panel-bot)

echo ""
draw_box_top
if [ "$API_STATUS" = "active" ]; then
    draw_box_line "${CLR_GREEN}✓ API Service: RUNNING${CLR_RESET}"
else
    draw_box_line "${CLR_RED}✗ API Service: FAILED${CLR_RESET}"
fi
if [ "$BOT_STATUS" = "active" ]; then
    draw_box_line "${CLR_GREEN}✓ Bot Service: RUNNING${CLR_RESET}"
else
    draw_box_line "${CLR_RED}✗ Bot Service: FAILED${CLR_RESET}"
fi
draw_box_bottom

# ═══════════════════════════════════════════════════════════════
#  FINAL SUMMARY
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${CLR_BOLD}${CLR_CYAN}╔══════════════════════════════════════════════════════════════════════╗${CLR_RESET}"
echo -e "${CLR_BOLD}${CLR_CYAN}║${CLR_RESET}           ${CLR_GREEN}🎉 عملیات با موفقیت انجام شد! 🎉${CLR_RESET}                      ${CLR_BOLD}${CLR_CYAN}║${CLR_RESET}"
echo -e "${CLR_BOLD}${CLR_CYAN}╚══════════════════════════════════════════════════════════════════════╝${CLR_RESET}"
echo ""

SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")

draw_box_top
draw_box_line "🌐 پنل وب: ${CLR_CYAN}http://${SERVER_IP}:${PANEL_PORT}${CLR_RESET}"
draw_box_line "🤖 ربات تلگرام: ${CLR_GREEN}فعال${CLR_RESET}"
draw_box_line "🗄️  دیتابیس: ${APP_DIR}/panel_database.db"
draw_box_line "📁 مسیر نصب: ${APP_DIR}"
if [ "$IS_UPDATE" = "true" ]; then
    draw_box_line "${CLR_YELLOW}🔄 نوع عملیات: آپدیت${CLR_RESET}"
else
    draw_box_line "${CLR_GREEN}🆕 نوع عملیات: نصب جدید${CLR_RESET}"
fi
draw_box_bottom

echo ""
echo -e "${CLR_BOLD}${CLR_WHITE}📋 دستورات مفید:${CLR_RESET}"
printf "${CLR_DIM}"
printf "%76s" | tr ' ' '─'
printf "${CLR_RESET}\n"
echo -e "${CLR_YELLOW}  systemctl status xui-panel-api${CLR_RESET}    → وضعیت API"
echo -e "${CLR_YELLOW}  systemctl status xui-panel-bot${CLR_RESET}    → وضعیت ربات"
echo -e "${CLR_YELLOW}  journalctl -u xui-panel-api -f${CLR_RESET}    → لاگ API (زنده)"
echo -e "${CLR_YELLOW}  journalctl -u xui-panel-bot -f${CLR_RESET}    → لاگ ربات (زنده)"
echo -e "${CLR_YELLOW}  systemctl restart xui-panel-api${CLR_RESET}   → ری‌استارت API"
echo -e "${CLR_YELLOW}  systemctl restart xui-panel-bot${CLR_RESET}   → ری‌استارت ربات"
echo ""

draw_box_top
draw_box_line "${CLR_MAGENTA}⚠️  نکات امنیتی:${CLR_RESET}"
draw_box_line "• پورت ${PANEL_PORT} را در فایروال باز کنید"
draw_box_line "• توصیه می‌شود Nginx Reverse Proxy استفاده کنید"
draw_box_line "• فایل panel_database.db را بک‌آپ بگیرید"
draw_box_bottom

echo ""
echo -e "${CLR_DIM}  X-UI Proxy Panel Manager - v2.0${CLR_RESET}"
echo -e "${CLR_DIM}  Made with ❤️  for the proxy community${CLR_RESET}"
echo ""