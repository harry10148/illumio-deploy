#!/bin/bash
###############################################################################
# Illumio VEN — 方式二：完整部署 (Linux)
#
# 流程:
#   1. 偵測 OS (RHEL 系 / Debian 系)
#   2. 匯入 PCE 的 CA 憑證 (未提供憑證則跳過，改用系統既有信任)
#   3. 安裝前檢查到 PCE 的 TLS 連線 (信任鏈不通即停止，不留下半套安裝)
#   4. 安裝 VEN 套件 (已安裝則跳過)
#        - 本機沒有安裝包時，向 PCE 下載符合本機的版本並驗證 SHA256
#        - 以 rpm/dpkg 試裝檢查相依套件，缺件即停止 (不自動安裝)
#   5. 向 PCE 啟用 (已啟用則跳過)
#
# 用法:
#   sudo bash deploy-illumio.sh --management-server pce.example.com:8443 \
#        --activation-code <CODE>
#
#   參數未指定時依序取用: 環境變數 → 下方設定區。
#   完整選項見 --help。可重複執行；全程不需互動。
#
# 只使用系統內建工具 (bash、coreutils、rpm/dpkg、curl)。除了 PCE 以外不連任何外部位址。
###############################################################################

set -u
set -o pipefail

# ==========================================
# 設定區 (可改這裡，也可用參數或環境變數覆蓋)
# ==========================================
ACTIVATION_CODE="<YOUR_ACTIVATION_CODE>"
MANAGEMENT_SERVER="<YOUR_PCE_FQDN:PORT>"
SOURCE_DIR=""       # 安裝包所在目錄；留空 = 腳本所在目錄
VEN_PACKAGE=""      # 安裝包檔名或絕對路徑；留空 = 自動尋找 *illumio-ven*.rpm / .deb
CERT_FILE=""        # CA 憑證路徑；留空 = 腳本同目錄 illumio-ca.crt，其次內嵌憑證
LOG_FILE="/var/log/illumio-deploy.log"
SKIP_TLS_CHECK=0    # 1 = 略過安裝前的 PCE 連線檢查
NO_DOWNLOAD=0       # 1 = 本機沒有安裝包時不向 PCE 下載，直接失敗
INSTALL_PREFIX=""   # 程式的上層目錄 (僅 RPM)；留空 = /opt，VEN 會裝在 <目錄>/illumio_ven
DATA_PREFIX=""      # 資料的上層目錄；留空 = /opt，資料會放在 <目錄>/illumio_ven_data
API_VERSION="v25"   # 下載安裝包使用的 PCE API 版本 (較新的 PCE 仍接受較舊的版本)
# ==========================================

# 內嵌憑證 (選用)。保留佔位符 = 不使用內嵌憑證。
EMBEDDED_CERT=$(cat << 'CERT_EOF'
-----BEGIN CERTIFICATE-----
PLACEHOLDER_CERTIFICATE_CONTENT_REPLACE_WITH_YOUR_ACTUAL_CERTIFICATE
-----END CERTIFICATE-----
CERT_EOF
)

# 結束碼 (各平台腳本一致，供派送工具判讀)
EX_OK=0; EX_USAGE=2; EX_PRIV=3; EX_OS=4; EX_DEPS=5; EX_CERT=6; EX_NET=7; EX_INSTALL=8; EX_ACTIVATE=9

DEFAULT_VEN_CTL="/opt/illumio_ven/illumio-ven-ctl"

usage() {
    cat << 'USAGE_EOF'
用法: sudo bash deploy-illumio.sh [選項]

  --management-server HOST:PORT  PCE 位址 (環境變數 ILLUMIO_MANAGEMENT_SERVER)
  --activation-code CODE         啟用碼 (環境變數 ILLUMIO_ACTIVATION_CODE)
  --cert-file PATH               CA 憑證 (PEM)。預設: 腳本同目錄 illumio-ca.crt
  --source-dir DIR               安裝包所在目錄。預設: 腳本所在目錄
  --package FILE                 安裝包檔名或絕對路徑。預設: 自動尋找；找不到則向 PCE 下載
  --no-download                  本機沒有安裝包時不向 PCE 下載，直接失敗
  --install-prefix DIR           程式的上層目錄 (僅 RPM；DEB 不支援)。預設: /opt
  --data-prefix DIR              資料的上層目錄。預設: /opt
                                 (自訂目錄只在初次安裝時生效；DEB 的資料目錄之後無法搬移)
  --api-version vNN              下載安裝包使用的 PCE API 版本。預設: v25
  --log-file PATH                日誌檔。預設: /var/log/illumio-deploy.log
  --skip-tls-check               略過安裝前的 PCE TLS 連線檢查
  -h, --help                     顯示本說明

結束碼:
  0 成功 (含已安裝、已啟用而跳過)   2 參數錯誤        3 權限不足
  4 不支援的作業系統                5 相依套件缺失    6 憑證無效或匯入失敗
  7 無法連線或無法驗證 PCE          8 取得安裝包或安裝失敗            9 啟用失敗
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
        OK) color="$C_GREEN" ;; SKIP|WARN) color="$C_YELLOW" ;; FAIL|ERROR) color="$C_RED" ;;
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
    log ERROR "部署中止 (結束碼 $code)。日誌: $LOG_FILE"
    exit "$code"
}

# ---------- 參數 ----------
ACTIVATION_CODE="${ILLUMIO_ACTIVATION_CODE:-$ACTIVATION_CODE}"
MANAGEMENT_SERVER="${ILLUMIO_MANAGEMENT_SERVER:-$MANAGEMENT_SERVER}"

need_value() { [ $# -ge 2 ] || { echo "[ERROR] 選項 $1 需要一個值。" >&2; exit "$EX_USAGE"; }; }

while [ $# -gt 0 ]; do
    case "$1" in
        --management-server) need_value "$@"; MANAGEMENT_SERVER="$2"; shift 2 ;;
        --activation-code)   need_value "$@"; ACTIVATION_CODE="$2"; shift 2 ;;
        --cert-file)         need_value "$@"; CERT_FILE="$2"; shift 2 ;;
        --source-dir)        need_value "$@"; SOURCE_DIR="$2"; shift 2 ;;
        --package)           need_value "$@"; VEN_PACKAGE="$2"; shift 2 ;;
        --log-file)          need_value "$@"; LOG_FILE="$2"; shift 2 ;;
        --skip-tls-check)    SKIP_TLS_CHECK=1; shift ;;
        --no-download)       NO_DOWNLOAD=1; shift ;;
        --install-prefix)    need_value "$@"; INSTALL_PREFIX="$2"; shift 2 ;;
        --data-prefix)       need_value "$@"; DATA_PREFIX="$2"; shift 2 ;;
        --api-version)       need_value "$@"; API_VERSION="$2"; shift 2 ;;
        -h|--help)           usage; exit "$EX_OK" ;;
        *) echo "[ERROR] 不認得的選項: $1" >&2; usage >&2; exit "$EX_USAGE" ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] 需要 root 權限。請以 root 或 sudo 執行。" >&2
    exit "$EX_PRIV"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
umask 022

# 必填參數先驗證，避免安裝完才發現無法啟用
case "$ACTIVATION_CODE" in ''|'<'*) die "$EX_USAGE" "未設定啟用碼。請用 --activation-code 或環境變數 ILLUMIO_ACTIVATION_CODE。" ;; esac
case "$MANAGEMENT_SERVER" in ''|'<'*) die "$EX_USAGE" "未設定 PCE 位址。請用 --management-server 或環境變數 ILLUMIO_MANAGEMENT_SERVER。" ;; esac
if ! [[ "$MANAGEMENT_SERVER" =~ ^[A-Za-z0-9._-]+:[0-9]+$ ]]; then
    die "$EX_USAGE" "PCE 位址格式應為 主機名稱:埠號 (例如 pce.example.com:8443)，目前為: $MANAGEMENT_SERVER"
fi
for dir_opt in "$INSTALL_PREFIX" "$DATA_PREFIX"; do
    case "$dir_opt" in ''|/*) ;; *) die "$EX_USAGE" "--install-prefix 與 --data-prefix 必須是絕對路徑，目前為: $dir_opt" ;; esac
done
[[ "$API_VERSION" =~ ^v[0-9]+$ ]] || die "$EX_USAGE" "--api-version 格式應為 vNN (例如 v25)，目前為: $API_VERSION"

# ---------- Step 1: 偵測 OS ----------
step "Step 1/5: 偵測作業系統"

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

log INFO "作業系統: $OS_ID $OS_VERSION ($OS_FAMILY 系)"

pkg_installed() {
    if [ "$OS_FAMILY" = "rhel" ]; then
        rpm -q "$1" > /dev/null 2>&1
    else
        dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'
    fi
}

# 原廠「VEN OS Support and Package Dependencies」支援表列出的套件。
# 以 | 分隔的名稱視為同一項需求的替代套件，任一已安裝即可。
vendor_pkg_list() {
    local major="${OS_VERSION%%.*}"
    [[ "$major" =~ ^[0-9]+$ ]] || major=99
    if [ "$OS_FAMILY" = "rhel" ]; then
        if [ "$major" -le 7 ]; then
            echo "bind-utils curl gmp ipset iptables libcap libmnl libnfnetlink net-tools sed"
        else
            echo "bind-utils diffutils curl gawk gmp gzip libcap libnfnetlink net-tools nftables sed shadow-utils tar util-linux"
        fi
    elif [ "$OS_ID" = "debian" ] && [ "$major" -lt 12 ]; then
        echo "apt-transport-https curl dnsutils|bind9-dnsutils libcap2 libgmp10 libmnl0 libnfnetlink0 ipset net-tools sed uuid-runtime"
    else
        # Debian 12+、Ubuntu：apt 1.5 起已內建 HTTPS，不再需要 apt-transport-https
        echo "curl dnsutils|bind9-dnsutils libcap2 libgmp10 libmnl0 libnfnetlink0 ipset net-tools sed uuid-runtime"
    fi
}

# 以套件管理員記錄的檔案清單找出 illumio-ven-ctl，自訂安裝目錄時也找得到
find_ven_ctl() {
    local found=""
    if [ "$OS_FAMILY" = "rhel" ]; then
        found=$(rpm -ql illumio-ven 2>/dev/null | grep -m1 '/illumio-ven-ctl$')
    else
        found=$(dpkg -L illumio-ven 2>/dev/null | grep -m1 '/illumio-ven-ctl$')
    fi
    echo "${found:-$DEFAULT_VEN_CTL}"
}

if [ "$OS_FAMILY" = "debian" ] && [ -n "$INSTALL_PREFIX" ]; then
    die "$EX_USAGE" "DEB 套件不支援自訂程式目錄 (--install-prefix)。只能用 --data-prefix 自訂資料目錄。"
fi

command -v curl > /dev/null 2>&1 || die "$EX_DEPS" "找不到 curl。請先安裝 curl 套件。"

# ---------- Step 2: CA 憑證 ----------
step "Step 2/5: 匯入 CA 憑證"

CERT_CONTENT=""; CERT_SOURCE=""
if [ -n "$CERT_FILE" ]; then
    [ -r "$CERT_FILE" ] || die "$EX_CERT" "指定的憑證檔不存在或無法讀取: $CERT_FILE"
    CERT_CONTENT=$(cat "$CERT_FILE"); CERT_SOURCE="$CERT_FILE"
elif [ -r "$SCRIPT_DIR/illumio-ca.crt" ]; then
    CERT_CONTENT=$(cat "$SCRIPT_DIR/illumio-ca.crt"); CERT_SOURCE="$SCRIPT_DIR/illumio-ca.crt"
elif [[ "$EMBEDDED_CERT" != *PLACEHOLDER_CERTIFICATE_CONTENT* ]]; then
    CERT_CONTENT="$EMBEDDED_CERT"; CERT_SOURCE="腳本內嵌憑證"
fi

if [ -z "$CERT_SOURCE" ]; then
    log SKIP "未提供 CA 憑證，跳過匯入。將以系統既有的信任憑證驗證 PCE。"
else
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
fi

# ---------- Step 3: 安裝前連線檢查 ----------
step "Step 3/5: 檢查 PCE 連線與憑證信任"

if [ "$SKIP_TLS_CHECK" = "1" ]; then
    log SKIP "已指定略過 TLS 連線檢查。"
else
    # 不加 -f：只要 TLS 握手完成即視為通過，HTTP 狀態碼不影響判斷
    curl_err=$(curl -sS -o /dev/null --connect-timeout 10 --max-time 30 "https://$MANAGEMENT_SERVER/" 2>&1)
    curl_rc=$?
    case "$curl_rc" in
        0) log OK "已與 $MANAGEMENT_SERVER 完成 TLS 握手，憑證受信任。" ;;
        35|51|53|54|58|59|60|77|83|90|91)
            log ERROR "curl: $curl_err"
            die "$EX_NET" "無法驗證 PCE 憑證 (curl 結束碼 $curl_rc)。請提供簽發 PCE 憑證的 CA (--cert-file)，並確認路徑上沒有 TLS 攔截。" ;;
        *)
            log ERROR "curl: $curl_err"
            die "$EX_NET" "無法連線至 $MANAGEMENT_SERVER (curl 結束碼 $curl_rc)。請檢查 DNS、防火牆與 Proxy 設定。" ;;
    esac
fi

# ---------- Step 4: 安裝 VEN ----------
step "Step 4/5: 安裝 VEN 套件"

if pkg_installed illumio-ven; then
    log SKIP "VEN 已安裝，跳過安裝。"
else
    PKG_EXT="rpm"; [ "$OS_FAMILY" = "debian" ] && PKG_EXT="deb"
    PKG_DIR="${SOURCE_DIR:-$SCRIPT_DIR}"
    PKG_PATH=""

    if [ -n "$VEN_PACKAGE" ]; then
        case "$VEN_PACKAGE" in /*) PKG_PATH="$VEN_PACKAGE" ;; *) PKG_PATH="$PKG_DIR/$VEN_PACKAGE" ;; esac
        [ -f "$PKG_PATH" ] || die "$EX_INSTALL" "找不到安裝包: $PKG_PATH"
    else
        shopt -s nullglob
        candidates=("$PKG_DIR"/*illumio-ven*."$PKG_EXT")
        shopt -u nullglob
        if [ "${#candidates[@]}" -gt 1 ]; then
            for c in "${candidates[@]}"; do log ERROR "  候選: $c"; done
            die "$EX_INSTALL" "在 $PKG_DIR 找到多個安裝包，無法判斷要裝哪一個。請用 --package 指定。"
        elif [ "${#candidates[@]}" -eq 1 ]; then
            PKG_PATH="${candidates[0]}"
        fi
    fi

    if [ -z "$PKG_PATH" ]; then
        [ "$NO_DOWNLOAD" = "1" ] && die "$EX_INSTALL" "在 $PKG_DIR 找不到 *illumio-ven*.$PKG_EXT (已指定 --no-download)。"

        # 與官方 pair.sh 相同的機制：以啟用碼向 PCE 的 VEN Library 取得符合本機的安裝包
        case "$OS_ID" in
            ubuntu) DL_DIST="Ubuntu"; DL_VER="$OS_VERSION" ;;
            debian) DL_DIST="Debian"; DL_VER="$(cat /etc/debian_version 2>/dev/null)"; DL_VER="${DL_VER:-$OS_VERSION}" ;;
            *)      if [ "$OS_FAMILY" = "rhel" ]; then DL_DIST="CentOS"; else DL_DIST="Debian"; fi; DL_VER="$OS_VERSION" ;;
        esac
        DL_ARCH="$(uname -m)"
        DL_DIR="$(mktemp -d)" || die "$EX_INSTALL" "無法建立暫存目錄。"
        trap 'rm -rf "$DL_DIR"' EXIT
        log INFO "本機沒有安裝包，向 PCE 下載 [$DL_ARCH][$DL_DIST][$DL_VER]"

        # 啟用碼經由 stdin 的 curl 設定傳入，不出現在程序清單
        http_code=$(printf 'user = "agent_0:%s"\n' "$ACTIVATION_CODE" | curl -sS -K - \
            --connect-timeout 10 --max-time 900 -D "$DL_DIR/headers" -o "$DL_DIR/package" -w '%{http_code}' \
            "https://$MANAGEMENT_SERVER/api/$API_VERSION/software/ven/image?architecture=$DL_ARCH&distribution=$DL_DIST&version=$DL_VER" 2>> "$LOG_FILE")
        case "$http_code" in
            200) ;;
            401|403) die "$EX_INSTALL" "PCE 拒絕下載 (HTTP $http_code)。請確認啟用碼有效且未過期。" ;;
            406) die "$EX_INSTALL" "PCE 沒有符合 [$DL_ARCH][$DL_DIST][$DL_VER] 的安裝包，或啟用碼無效。請確認啟用碼，或自行提供安裝包 (--package)。" ;;
            *)   die "$EX_INSTALL" "安裝包下載失敗 (HTTP ${http_code:-無回應})。" ;;
        esac

        dl_sha=$(grep -i '^x-sha256:' "$DL_DIR/headers" | tr -d '\r' | awk '{print $2}')
        dl_name=$(grep -i '^content-disposition:' "$DL_DIR/headers" | tr -d '\r' | sed 's/.*filename=//; s/"//g')
        dl_name="${dl_name##*/}"
        [ -n "$dl_sha" ] && [ -n "$dl_name" ] || die "$EX_INSTALL" "PCE 回應缺少檔名或 SHA256 標頭，無法驗證安裝包。"
        got_sha=$(sha256sum "$DL_DIR/package" | awk '{print $1}')
        [ "$got_sha" = "$dl_sha" ] || die "$EX_INSTALL" "安裝包 SHA256 不符 (預期 $dl_sha，實際 $got_sha)。"
        PKG_PATH="$DL_DIR/$dl_name"
        mv "$DL_DIR/package" "$PKG_PATH"
        log OK "已下載並通過 SHA256 驗證: $dl_name"
    fi

    # 相依套件以安裝包本身的宣告為準：用套件管理員試裝，不實際變更系統
    log INFO "檢查相依套件: $(basename "$PKG_PATH")"
    if [ "$OS_FAMILY" = "rhel" ]; then
        dep_out=$(rpm -i --test --nosignature ${INSTALL_PREFIX:+--prefix "$INSTALL_PREFIX"} "$PKG_PATH" 2>&1); dep_rc=$?
    else
        dep_out=$(dpkg --dry-run -i "$PKG_PATH" 2>&1); dep_rc=$?
    fi
    if [ "$dep_rc" -ne 0 ]; then
        while IFS= read -r line; do [ -n "$line" ] && log ERROR "  $line"; done <<< "$dep_out"
        if [ "$OS_FAMILY" = "debian" ]; then
            log ERROR "安裝包宣告的相依套件: $(dpkg-deb -f "$PKG_PATH" Pre-Depends Depends 2>/dev/null | tr '\n' ' ')"
        fi
        die "$EX_DEPS" "相依套件不足或安裝包不適用於本機。請先安裝上列套件後重新執行。"
    fi
    log OK "安裝包宣告的相依套件齊全。"

    # 原廠支援表另外列出的套件：安裝包未宣告，缺少時只提醒、不中止
    advisory_missing=()
    read -r -a vendor_pkgs <<< "$(vendor_pkg_list)"
    for spec in "${vendor_pkgs[@]}"; do
        found=""
        IFS='|' read -r -a alternatives <<< "$spec"
        for pkg in "${alternatives[@]}"; do pkg_installed "$pkg" && { found=1; break; }; done
        [ -n "$found" ] || advisory_missing+=("${alternatives[0]}")
    done
    if [ "${#advisory_missing[@]}" -gt 0 ]; then
        log WARN "原廠支援表列出、但本機未安裝的套件 (不影響安裝，僅供參考): ${advisory_missing[*]}"
    fi

    log INFO "安裝: $PKG_PATH"
    [ -n "$INSTALL_PREFIX" ] && log INFO "程式上層目錄: $INSTALL_PREFIX"
    [ -n "$DATA_PREFIX" ] && log INFO "資料上層目錄: $DATA_PREFIX"
    # SELinux 啟用時，自訂目錄預設的標籤會讓 systemd 無法執行 VEN 常駐程式。
    # 讓自訂目錄比照 /opt 的標籤規則：有 semanage 就建立永久規則，沒有則安裝後暫時標記。
    SELINUX_DIRS=()
    if command -v getenforce > /dev/null 2>&1 && [ "$(getenforce)" != "Disabled" ]; then
        [ -n "$INSTALL_PREFIX" ] && SELINUX_DIRS+=("$INSTALL_PREFIX")
        [ -n "$DATA_PREFIX" ] && [ "$DATA_PREFIX" != "$INSTALL_PREFIX" ] && SELINUX_DIRS+=("$DATA_PREFIX")
    fi
    SELINUX_PERSISTENT=1
    for d in ${SELINUX_DIRS[@]+"${SELINUX_DIRS[@]}"}; do
        mkdir -p "$d" || die "$EX_INSTALL" "無法建立目錄: $d"
        if command -v semanage > /dev/null 2>&1; then
            semanage fcontext -a -e /opt "$d" >> "$LOG_FILE" 2>&1 || semanage fcontext -m -e /opt "$d" >> "$LOG_FILE" 2>&1 || SELINUX_PERSISTENT=0
        else
            SELINUX_PERSISTENT=0
        fi
    done

    # VEN_DATA_DIR 與 rpm --prefix 是原廠文件記載的自訂目錄方式，兩者可各自獨立指定
    if [ "$OS_FAMILY" = "rhel" ]; then
        env ${DATA_PREFIX:+VEN_DATA_DIR="$DATA_PREFIX"} rpm -ivh ${INSTALL_PREFIX:+--prefix "$INSTALL_PREFIX"} "$PKG_PATH" 2>&1 | tee -a "$LOG_FILE"
    else
        env ${DATA_PREFIX:+VEN_DATA_DIR="$DATA_PREFIX"} DEBIAN_FRONTEND=noninteractive dpkg -i "$PKG_PATH" 2>&1 | tee -a "$LOG_FILE"
    fi
    install_rc="${PIPESTATUS[0]}"
    [ "$install_rc" -eq 0 ] || die "$EX_INSTALL" "套件安裝失敗 (結束碼 $install_rc)。"

    for d in ${SELINUX_DIRS[@]+"${SELINUX_DIRS[@]}"}; do
        if [ "$SELINUX_PERSISTENT" = "1" ]; then
            restorecon -R "$d" >> "$LOG_FILE" 2>&1
            log OK "SELinux: $d 已比照 /opt 設定標籤 (永久規則)。"
        else
            chcon -R --reference=/opt "$d" >> "$LOG_FILE" 2>&1
            log WARN "SELinux: $d 已暫時比照 /opt 標記，但系統沒有 semanage，全系統重新標記後會失效。"
            log WARN "  請安裝 policycoreutils-python-utils 後執行: semanage fcontext -a -e /opt $d && restorecon -R $d"
        fi
    done
    log OK "VEN 安裝完成。"
fi

# ---------- Step 5: 啟用 ----------
step "Step 5/5: 向 PCE 啟用"

VEN_CTL="$(find_ven_ctl)"
[ -x "$VEN_CTL" ] || die "$EX_ACTIVATE" "找不到 $VEN_CTL，VEN 可能未正確安裝。"

# 未配對的 VEN 回報 "Agent state: unpaired"；其他狀態 (idle、illuminated、enforced 等) 代表已配對，
# 再次 activate 會失敗，故直接跳過
AGENT_STATE=$("$VEN_CTL" status 2>/dev/null | sed -n 's/^Agent state: *//p' | head -1)
if [ -n "$AGENT_STATE" ] && [ "$AGENT_STATE" != "unpaired" ]; then
    log SKIP "VEN 已啟用 (Agent state: $AGENT_STATE)，跳過啟用。"
else
    log INFO "PCE: $MANAGEMENT_SERVER"
    "$VEN_CTL" activate --management-server "$MANAGEMENT_SERVER" --activation-code "$ACTIVATION_CODE" 2>&1 | tee -a "$LOG_FILE"
    activate_rc="${PIPESTATUS[0]}"
    [ "$activate_rc" -eq 0 ] || die "$EX_ACTIVATE" "啟用失敗 (結束碼 $activate_rc)。請確認啟用碼有效且未超過使用次數。"
    log OK "啟用完成。"
fi

step "部署完成"
log OK "確認狀態: $VEN_CTL status"
exit "$EX_OK"
