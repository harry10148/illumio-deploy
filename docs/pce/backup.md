> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/illumio_backup_v4.txt`

# Illumio PCE 備份程序

## 1. 目的與適用情境

定期備份 Illumio PCE 的政策資料庫（Policy DB）與流量資料庫（Traffic DB），支援本機、SMB 網路共享及 SCP 遠端傳輸三種模式，並自動偵測 Leader 節點確保備份從正確節點執行；亦包含 SMB 掛載設定與 SSH 免密碼金鑰配置步驟。

## 2. 前置條件

- PCE 服務正常運行（runlevel 5）
- 本機備份目錄 `/opt/illumio-backup` 已建立或可由腳本自動建立
- （若使用 SMB）`cifs-utils` 已安裝，SMB 伺服器可連通，credential 檔案已設定
- （若使用 SCP）SSH 免密碼金鑰已設定完成
- 具備 root 或 ilo-pce 執行權限

## 3. 操作步驟

### SMB 掛載設定（選擇性）

安裝 SMB 工具並掛載共享資料夾：

```bash
dnf install cifs-utils -y

mount -t cifs -o username=harry //dc.lab.local/share /mnt/smb
umount /mnt/smb/
vi /root/smb.cred
```

credential 檔案範本（`/root/smb.cred`）：

```
username=harry
password=<SMB_PASSWORD>
domain=lab.local
```

設定 credential 檔案安全權限，並加入 fstab 自動掛載：

```bash
chmod 600 /root/smb.cred

vi /etc/fstab
```

fstab 範本：

```
//dc.lab.local/share /mnt/smb  cifs  credentials=/root/smb.cred  0 0
//192.168.1.200/win_share  /mnt/smb_data  cifs  credentials=/root/.smbcreds,_netdev,vers=3.0  0 0
```

```bash
sudo mount -a
systemctl daemon-reload
```

### SSH 金鑰設定（選擇性，用於 SCP 備份）

```bash
# 產生金鑰 (一路按 Enter 即可，不要設密碼)
ssh-keygen -t rsa -b 4096

# 將公鑰傳送到備份機
# 替換 user 和 IP
ssh-copy-id root@192.168.1.100

# 測試連線 (必須不需要輸入密碼即可登入)
ssh root@192.168.1.100 "ls -l"
# 如果成功列出檔案且沒問密碼，代表設定成功
```

在備份機上建立目錄：

```bash
ssh root@192.168.1.100 "mkdir -p /opt/illumio-backup"

mkdir /opt/illumio-backup
chown ilo-pce:ilo-pce -R illumio-backup/
cd /opt/illumio-backup
vi illumio_backup.sh
```

### 備份腳本內容（`/opt/illumio-backup/illumio_backup.sh`）

```bash
#!/bin/bash

# ==============================================================================
# Illumio PCE Cluster Smart Backup Script
# Features: Leader detection, Local/SMB/SCP transfer, Retention policy
# Language: English
# ==============================================================================

# --- [CRITICAL] Set PATH to ensure commands like ip, awk, grep are found ---
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# --- [CONFIGURATION] ---

# 1. Local Backup Settings
LOCAL_BACKUP_DIR="/opt/illumio-backup"
RETENTION_DB_DAYS=7
RETENTION_TRAFFIC_DAYS=14

# 2. SMB Settings
# Target directory on the SMB share (can be a subdirectory)
SMB_MOUNT_POINT="/mnt/smb/illumio-backup"

# 3. SCP (DR Site) Settings
DR_USER="root"
DR_HOST="172.16.15.131"
DR_DEST_DIR="/opt/illumio-backup"

# --- [DEFAULT SWITCHES] ---
ENABLE_SMB=false
ENABLE_SCP=false

# --- Parse Arguments ---
# Usage: ./script.sh --smb --scp
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --smb) ENABLE_SMB=true ;;
        --scp) ENABLE_SCP=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# --- System Variables ---
TODAY=$(date +%Y%m%d)
DAY_OF_WEEK=$(date +%u)
HOSTNAME=$(hostname)

# Ensure local directory exists with correct permissions
mkdir -p $LOCAL_BACKUP_DIR
chown ilo-pce:ilo-pce $LOCAL_BACKUP_DIR

# ==============================================================================
# PHASE 1: Cluster Role Detection
# ==============================================================================

echo "Checking cluster status on $HOSTNAME..."

# 1. Get the IP address of the node running 'agent_traffic_redis_server'
# Using awk to ensure we get a clean IP string
LEADER_IP=$(sudo -u ilo-pce illumio-pce-ctl cluster-status | grep "agent_traffic_redis_server" | awk '{print $2}')

if [ -z "$LEADER_IP" ]; then
    echo "[ERROR] Could not detect 'agent_traffic_redis_server' IP. Check PCE service status."
    exit 1
fi

echo "[DEBUG] Detected Leader IP: $LEADER_IP"

# 2. Check if the local machine owns this IP
# Using absolute path for 'ip' command and precise grep
if /usr/sbin/ip addr show | grep -q "$LEADER_IP"; then
    echo "[ROLE] This node ($LEADER_IP) IS the Leader node."
    echo ">>> Starting backup tasks..."
else
    echo "[ROLE] This node is NOT the Leader (Leader is $LEADER_IP)."
    echo ">>> Skipping backup tasks."
    exit 0
fi

# ==============================================================================
# PHASE 2: Backup Execution (Leader Only)
# ==============================================================================

echo "========================================="
echo "Backup Process Started: $(date)"

# --- Function: File Transfer ---
process_file() {
    local FILE_PATH=$1
    local FILE_NAME=$(basename "$FILE_PATH")

    # 1. Process SMB Transfer
    if [ "$ENABLE_SMB" = true ]; then
        # CHECK: Verify directory exists AND filesystem type is cifs (Robust check)
        if [ -d "$SMB_MOUNT_POINT" ] && df -T "$SMB_MOUNT_POINT" | tail -n +2 | grep -q "cifs"; then
            cp -p "$FILE_PATH" "$SMB_MOUNT_POINT/" && echo "[SMB] Copy Success: $FILE_NAME" || echo "[SMB] Failed: $FILE_NAME"
        else
            echo "[SMB] Warning: Target is not a valid CIFS mount or directory missing. Skipping."
        fi
    fi

    # 2. Process SCP Transfer
    if [ "$ENABLE_SCP" = true ]; then
        # Try to create remote dir (ignore error if exists)
        ssh -o ConnectTimeout=5 $DR_USER@$DR_HOST "mkdir -p $DR_DEST_DIR" 2>/dev/null
        # Perform SCP
        scp -o ConnectTimeout=20 -p "$FILE_PATH" "$DR_USER@$DR_HOST:$DR_DEST_DIR/" && echo "[SCP] Transfer Success: $FILE_NAME" || echo "[SCP] Failed: $FILE_NAME"
    fi
}

# --- 1. Backup Runtime Env ---
echo "-----------------------------------------"
echo "[TASK] Backing up runtime_env.yml"
RUNTIME_FILE="runtime_env_${TODAY}.yml"
cp /etc/illumio-pce/runtime_env.yml "$LOCAL_BACKUP_DIR/$RUNTIME_FILE"
process_file "$LOCAL_BACKUP_DIR/$RUNTIME_FILE"

# --- 2. Daily Policy Database Backup ---
echo "-----------------------------------------"
echo "[TASK] Backing up Policy Database"
DB_FILE="ilo-db-bak-${TODAY}.dump"
FULL_DB_PATH="$LOCAL_BACKUP_DIR/$DB_FILE"

sudo -u ilo-pce illumio-pce-db-management dump --file "$FULL_DB_PATH"

if [ -f "$FULL_DB_PATH" ]; then
    echo "[LOCAL] Policy DB generated: $DB_FILE"
    process_file "$FULL_DB_PATH"
else
    echo "[ERROR] Policy DB generation failed!"
fi

# --- 3. Weekly Traffic Database Backup (Sundays Only) ---
echo "-----------------------------------------"
if [ "$DAY_OF_WEEK" -eq 7 ]; then
    echo "[TASK] Backing up Traffic Database (Sunday Task)"
    TRAFFIC_FILE="ilo-traffic-bak-${TODAY}.tar.gz"
    FULL_TRAFFIC_PATH="$LOCAL_BACKUP_DIR/$TRAFFIC_FILE"

    sudo -u ilo-pce illumio-pce-db-management traffic dump --file "$FULL_TRAFFIC_PATH"

    if [ -f "$FULL_TRAFFIC_PATH" ]; then
        echo "[LOCAL] Traffic DB generated: $TRAFFIC_FILE"
        process_file "$FULL_TRAFFIC_PATH"
    else
        echo "[ERROR] Traffic DB generation failed!"
    fi
else
    echo "[INFO] Not Sunday. Skipping Traffic DB backup."
fi

# ==============================================================================
# PHASE 3: Cleanup (Retention Policy)
# ==============================================================================
echo "-----------------------------------------"
echo "[CLEANUP] Removing expired files (DB: $RETENTION_DB_DAYS days, Traffic: $RETENTION_TRAFFIC_DAYS days)"

# Define cleanup commands
CMD_CLEAN_DB="find . -maxdepth 1 -name 'ilo-db-bak-*.dump' -mtime +$RETENTION_DB_DAYS -delete"
CMD_CLEAN_TRAFFIC="find . -maxdepth 1 -name 'ilo-traffic-bak-*.tar.gz' -mtime +$RETENTION_TRAFFIC_DAYS -delete"
CMD_CLEAN_ENV="find . -maxdepth 1 -name 'runtime_env_*.yml' -mtime +$RETENTION_DB_DAYS -delete"

# 1. Local Cleanup
echo ">>> Cleaning Local Directory..."
cd $LOCAL_BACKUP_DIR && eval $CMD_CLEAN_DB && eval $CMD_CLEAN_TRAFFIC && eval $CMD_CLEAN_ENV

# 2. SMB Cleanup
# Check logic: Exists + Is CIFS
if [ "$ENABLE_SMB" = true ] && [ -d "$SMB_MOUNT_POINT" ] && df -T "$SMB_MOUNT_POINT" | tail -n +2 | grep -q "cifs"; then
    echo ">>> Cleaning SMB Directory..."
    cd $SMB_MOUNT_POINT && eval $CMD_CLEAN_DB && eval $CMD_CLEAN_TRAFFIC && eval $CMD_CLEAN_ENV
fi

# 3. SCP (Remote) Cleanup
if [ "$ENABLE_SCP" = true ]; then
    echo ">>> Cleaning Remote SCP Host..."
    REMOTE_CMD="cd $DR_DEST_DIR && $CMD_CLEAN_DB && $CMD_CLEAN_TRAFFIC && $CMD_CLEAN_ENV"
    ssh -o ConnectTimeout=10 $DR_USER@$DR_HOST "$REMOTE_CMD"
fi

echo "========================================="
echo "Backup Process Completed: $(date)"
exit 0
```

## 4. 驗證

腳本執行後，確認備份檔案已產生：

```bash
ls -lh /opt/illumio-backup/
```

預期看到 `ilo-db-bak-YYYYMMDD.dump` 與 `runtime_env_YYYYMMDD.yml` 等備份檔案。

## 5. 失敗回滾 / 救援

若需從備份還原，執行以下回滾指令：

```bash
#restore 指令
sudo -u ilo-pce illumio-pce-ctl stop
sudo -u ilo-pce illumio-pce-ctl start --runlevel 1
sudo -u ilo-pce illumio-pce-ctl cluster-status -w
sudo -u ilo-pce illumio-pce-db-management restore --file /mnt/smb/ilo-db-bak-xxxxxxxx.dump
sudo -u ilo-pce illumio-pce-db-management traffic restore --file /mnt/smb/ilo-traffic-bak-xxxxxxxx.dump
sudo -u ilo-pce illumio-pce-db-management migrate
sudo -u ilo-pce illumio-pce-ctl set-runlevel 5
sudo -u ilo-pce illumio-pce-ctl listen-only-mode disable
```

## 6. 原廠文件參照

- [NotebookLM] Illumio_PCE操作手冊_20251128.pdf §2.2.2 備份作業 > 備份 Policy 資料庫 — illumio-pce-db-management dump 指令與 Leader 節點識別（agent_traffic_redis_server）
- [NotebookLM] Illumio_PCE操作手冊_20251128.pdf §2.2.2 備份作業 > 備份 Traffic 資料庫 — illumio-pce-db-management traffic dump 指令
- [NotebookLM] Illumio_PCE操作手冊_20251128.pdf §2.2.2 備份作業 > 何時進行備份 — 版本升級前後、大量 VEN 配對後、重大政策變更後建議備份；建議存放於 PCE 叢集以外的系統
- [NotebookLM] Illumio_PCE操作手冊_20251128.pdf §2.1 指令說明 — restore 子指令可在任何 Data 節點執行

## 7. 與原廠差異（若有）

- **Leader 節點偵測方式**：SOP 以自動化腳本解析 cluster-status 輸出偵測 agent_traffic_redis_server IP，與原廠（PCE操作手冊 §2.2.2）描述的手動確認方式功能一致，SOP 自動化補強合理。
- **SMB/SCP 傳輸模式**：原廠文件建議備份存放於叢集外系統，SOP 實作 SMB 與 SCP 兩種傳輸模式符合此建議。
- **保留政策（7日 DB / 14日 Traffic）**：原廠未規定具體保留天數，SOP 自行訂定，合理。
- **runtime_env.yml 備份**：原廠（Core Admin §PCE Database Backup）明確指出 runtime_env.yml 不含於資料庫備份中，需手動另行備份；SOP 已包含此步驟，與原廠一致。
