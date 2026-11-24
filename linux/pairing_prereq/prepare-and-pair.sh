#!/bin/bash
###############################################################################
# Illumio VEN — 方式一前置作業 (Linux)：相依套件檢查 + CA 憑證匯入
#
# 在執行 Illumio 官方配對腳本 (pair.sh) 之前使用:
#   1. 偵測 OS (RHEL 系 / Debian 系)
#   2. 檢查相依套件 (預設只報告；加 --strict 則缺件時以結束碼 5 結束)
#   3. 匯入 PCE 的 CA 憑證 (內容相同則跳過)
#
# 用法:
#   sudo bash prepare-and-pair.sh [--cert-file PATH] [--strict]
#
# 只使用系統內建工具 (bash、coreutils、rpm/dpkg)。可重複執行；全程不需互動。
###############################################################################

set -u
set -o pipefail

CERT_FILE=""        # CA 憑證路徑；留空 = 腳本同目錄 illumio-ca.crt，其次內嵌憑證
LOG_FILE="/var/log/illumio-deploy.log"
STRICT=0            # 1 = 相依套件缺失時視為失敗

# 內嵌憑證 (選用)。保留佔位符 = 不使用內嵌憑證。
EMBEDDED_CERT=$(cat << 'CERT_EOF'
-----BEGIN CERTIFICATE-----
PLACEHOLDER_CERTIFICATE_CONTENT_REPLACE_WITH_YOUR_ACTUAL_CERTIFICATE
-----END CERTIFICATE-----
CERT_EOF
)

# 結束碼 (各平台腳本一致，供派送工具判讀)
EX_OK=0; EX_USAGE=2; EX_PRIV=3; EX_OS=4; EX_DEPS=5; EX_CERT=6

usage() {
    cat << 'USAGE_EOF'
用法: sudo bash prepare-and-pair.sh [選項]

  --cert-file PATH   CA 憑證 (PEM)。預設: 腳本同目錄 illumio-ca.crt，其次內嵌憑證
  --strict           相依套件缺失時以結束碼 5 結束 (預設只報告)
  --log-file PATH    日誌檔。預設: /var/log/illumio-deploy.log
  -h, --help         顯示本說明

結束碼:
  0 成功   2 參數錯誤   3 權限不足   4 不支援的作業系統
  5 相依套件缺失 (僅 --strict)   6 未提供憑證、憑證無效或匯入失敗
USAGE_EOF
}

# ---------- 輸出與日誌 ----------
if [ -t 1 ]; then
    C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'; C_BLUE='\033[0;34m'; C_NC='\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_NC=''
fi

log() {
    local level="$1"; shift
    local color="$C_BLUE"
    case "$level" in
        OK) color="$C_GREEN" ;; SKIP|WARN) color="$C_YELLOW" ;; MISS|ERROR) color="$C_RED" ;;
    esac
    printf '  %b[%s]%b %s\n' "$color" "$level" "$C_NC" "$*"
    { printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE"; } 2>/dev/null
}

step() {
    printf '\n%b== %s ==%b\n' "$C_BLUE" "$*" "$C_NC"
    { printf '[%s] == %s ==\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; } 2>/dev/null
}

die() {
    local code="$1"; shift
    log ERROR "$*"
    log ERROR "前置作業中止 (結束碼 $code)。日誌: $LOG_FILE"
    exit "$code"
}

# ---------- 參數 ----------
need_value() { [ $# -ge 2 ] || { echo "[ERROR] 選項 $1 需要一個值。" >&2; exit "$EX_USAGE"; }; }

while [ $# -gt 0 ]; do
    case "$1" in
        --cert-file) need_value "$@"; CERT_FILE="$2"; shift 2 ;;
        --log-file)  need_value "$@"; LOG_FILE="$2"; shift 2 ;;
        --strict)    STRICT=1; shift ;;
        -h|--help)   usage; exit "$EX_OK" ;;
        *) echo "[ERROR] 不認得的選項: $1" >&2; usage >&2; exit "$EX_USAGE" ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] 需要 root 權限。請以 root 或 sudo 執行。" >&2
    exit "$EX_PRIV"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
umask 022

# ---------- Step 1: 偵測 OS ----------
step "Step 1/3: 偵測作業系統"

OS_ID=""; OS_LIKE=""; OS_VERSION=""
if [ -r /etc/os-release ]; then
    OS_ID=$(. /etc/os-release; echo "${ID:-}")
    OS_LIKE=$(. /etc/os-release; echo "${ID_LIKE:-}")
    OS_VERSION=$(. /etc/os-release; echo "${VERSION_ID:-}")
elif [ -r /etc/redhat-release ]; then
    OS_ID="rhel"; OS_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
fi

OS_FAMILY=""
case "$OS_ID" in
    rhel|centos|rocky|almalinux|ol) OS_FAMILY="rhel" ;;
    ubuntu|debian)                  OS_FAMILY="debian" ;;
    *)
        case " $OS_LIKE " in
            *" rhel "*)   OS_FAMILY="rhel" ;;
            *" debian "*) OS_FAMILY="debian" ;;
        esac ;;
esac
[ -n "$OS_FAMILY" ] || die "$EX_OS" "不支援的作業系統: ${OS_ID:-未知} ${OS_VERSION}"

OS_MAJOR="${OS_VERSION%%.*}"
log INFO "作業系統: $OS_ID $OS_VERSION ($OS_FAMILY 系)"

# ---------- Step 2: 相依套件 ----------
step "Step 2/3: 檢查相依套件"

# 以 | 分隔的名稱視為同一項需求的替代套件，任一已安裝即可
if [ "$OS_FAMILY" = "rhel" ]; then
    if [[ "$OS_MAJOR" =~ ^[0-9]+$ ]] && [ "$OS_MAJOR" -le 7 ]; then
        REQUIRED_PKGS=(bind-utils curl gmp ipset iptables libcap libmnl libnfnetlink net-tools sed)
        PKG_INSTALL_CMD="yum install -y"
    else
        REQUIRED_PKGS=(bind-utils diffutils curl gawk gmp gzip libcap libnfnetlink net-tools nftables sed shadow-utils tar util-linux)
        PKG_INSTALL_CMD="dnf install -y"
    fi
else
    REQUIRED_PKGS=("dnsutils|bind9-dnsutils" curl libgmp10 ipset iptables "libcap2" libmnl0 libnfnetlink0 net-tools sed uuid-runtime)
    PKG_INSTALL_CMD="apt-get install -y"
fi

pkg_installed() {
    if [ "$OS_FAMILY" = "rhel" ]; then
        rpm -q "$1" > /dev/null 2>&1
    else
        dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'
    fi
}

MISSING_PKGS=()
for spec in "${REQUIRED_PKGS[@]}"; do
    found=""
    IFS='|' read -r -a alternatives <<< "$spec"
    for pkg in "${alternatives[@]}"; do
        if pkg_installed "$pkg"; then found="$pkg"; break; fi
    done
    if [ -n "$found" ]; then
        log OK "$found"
    else
        log MISS "${alternatives[0]} (未安裝)"
        MISSING_PKGS+=("${alternatives[0]}")
    fi
done

if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
    log WARN "缺少 ${#MISSING_PKGS[@]} 個相依套件，請在配對前安裝:"
    log WARN "  $PKG_INSTALL_CMD ${MISSING_PKGS[*]}"
    [ "$STRICT" = "1" ] && die "$EX_DEPS" "缺少相依套件 (--strict)。"
else
    log OK "相依套件齊全。"
fi

# ---------- Step 3: CA 憑證 ----------
step "Step 3/3: 匯入 CA 憑證"

CERT_CONTENT=""; CERT_SOURCE=""
if [ -n "$CERT_FILE" ]; then
    [ -r "$CERT_FILE" ] || die "$EX_CERT" "指定的憑證檔不存在或無法讀取: $CERT_FILE"
    CERT_CONTENT=$(cat "$CERT_FILE"); CERT_SOURCE="$CERT_FILE"
elif [ -r "$SCRIPT_DIR/illumio-ca.crt" ]; then
    CERT_CONTENT=$(cat "$SCRIPT_DIR/illumio-ca.crt"); CERT_SOURCE="$SCRIPT_DIR/illumio-ca.crt"
elif [[ "$EMBEDDED_CERT" != *PLACEHOLDER_CERTIFICATE_CONTENT* ]]; then
    CERT_CONTENT="$EMBEDDED_CERT"; CERT_SOURCE="腳本內嵌憑證"
fi

[ -n "$CERT_SOURCE" ] || die "$EX_CERT" "未提供 CA 憑證。請用 --cert-file 指定，或將 illumio-ca.crt 放在腳本同目錄。"

log INFO "憑證來源: $CERT_SOURCE"
if [[ "$CERT_CONTENT" != *"-----BEGIN CERTIFICATE-----"* ]] || [[ "$CERT_CONTENT" == *PLACEHOLDER_CERTIFICATE_CONTENT* ]]; then
    die "$EX_CERT" "憑證內容不是 PEM 格式 (缺少 BEGIN CERTIFICATE，或仍為佔位符)。"
fi
if command -v openssl > /dev/null 2>&1 && ! printf '%s\n' "$CERT_CONTENT" | openssl x509 -noout 2>/dev/null; then
    die "$EX_CERT" "憑證內容無法解析為有效的 X.509 憑證。"
fi

if [ "$OS_FAMILY" = "rhel" ]; then
    TRUST_DIR="/etc/pki/ca-trust/source/anchors"; TRUST_UPDATE="update-ca-trust"
else
    TRUST_DIR="/usr/local/share/ca-certificates"; TRUST_UPDATE="update-ca-certificates"
fi
TRUST_FILE="$TRUST_DIR/illumio-ca.crt"
command -v "$TRUST_UPDATE" > /dev/null 2>&1 || die "$EX_CERT" "找不到 $TRUST_UPDATE (請確認已安裝 ca-certificates 套件)。"

if [ -f "$TRUST_FILE" ] && [ "$(cat "$TRUST_FILE")" = "$CERT_CONTENT" ]; then
    log SKIP "憑證已存在且內容相同: $TRUST_FILE"
else
    mkdir -p "$TRUST_DIR" || die "$EX_CERT" "無法建立目錄: $TRUST_DIR"
    printf '%s\n' "$CERT_CONTENT" > "$TRUST_FILE" || die "$EX_CERT" "無法寫入: $TRUST_FILE"
    chmod 644 "$TRUST_FILE"
    command -v restorecon > /dev/null 2>&1 && restorecon "$TRUST_FILE" 2>/dev/null
    if [ "$OS_FAMILY" = "rhel" ]; then
        update-ca-trust extract >> "$LOG_FILE" 2>&1 || die "$EX_CERT" "update-ca-trust 執行失敗。"
    else
        update-ca-certificates >> "$LOG_FILE" 2>&1 || die "$EX_CERT" "update-ca-certificates 執行失敗。"
    fi
    log OK "憑證已匯入: $TRUST_FILE"
fi

step "前置作業完成"
log OK "接著請至 PCE Web Console 的 Pairing Profile 複製配對指令，在本機執行。"
exit "$EX_OK"
