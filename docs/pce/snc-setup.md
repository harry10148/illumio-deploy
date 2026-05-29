> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/illumio_pce_snc_setup_v3.txt`

# Illumio PCE SNC 安裝（單一節點）

## 1. 目的與適用情境

在 Linux（RHEL/CentOS）上以單一節點（SNC）模式完整部署 Illumio PCE，涵蓋系統別名設定、防火牆與憑證準備、PCE 初始化、資料庫初始化、使用者與組織建立，以及 VEN 套件上傳等所有必要步驟。

## 2. 前置條件

- NTP/時鐘已同步
- DNS 可正確解析所有 PCE 節點的 FQDN
- 作業系統版本受支援（RHEL/CentOS）
- 足夠的磁碟空間
- 已開放必要的網路連接埠
- 已準備好伺服器憑證（server.crt、server.key、ca.crt）
- 具備 root 權限

## 3. 操作步驟

### 步驟 1：設定常用命令別名（所有 PCE 節點）

```bash
# 將別名寫入全域設定檔，讓所有使用者皆可使用
echo 'alias illumio-pce-env="sudo -u ilo-pce /opt/illumio-pce/illumio-pce-env" ' | sudo tee /etc/profile.d/global_aliases.sh
echo 'alias illumio-pce-ctl="sudo -u ilo-pce /opt/illumio-pce/illumio-pce-ctl"' | sudo tee -a /etc/profile.d/global_aliases.sh
echo 'alias illumio-pce-db-management="sudo -u ilo-pce /opt/illumio-pce/illumio-pce-db-management"' | sudo tee -a /etc/profile.d/global_aliases.sh

# 讓當前的 shell 會話立即生效
source /etc/profile.d/global_aliases.sh
```

### 步驟 2：系統層設定與憑證信任（所有 PCE 節點）

```bash
# 停用並遮蔽 firewalld (生產環境建議改為精細設定)
systemctl stop firewalld && systemctl mask --now firewalld
firewall-cmd --state

# 複製伺服器憑證與私鑰至 PCE 指定目錄
cp /tmp/server.crt /var/lib/illumio-pce/cert
cp /tmp/server.key /var/lib/illumio-pce/cert

# 設定憑證檔案所有權與權限
chown ilo-pce /var/lib/illumio-pce/cert/*
chmod 400 /var/lib/illumio-pce/cert/*

# 將 CA 根憑證安裝至系統信任區 (RHEL/CentOS)
cp /tmp/ca.crt /etc/pki/ca-trust/source/anchors/

# 更新系統 CA 信任庫
update-ca-trust enable && update-ca-trust extract
```

若需快速建立自簽 Root 憑證（包含 CA、Auth、SAN）：

```bash
# 產生 ssl.conf (包含所有擴充屬性：CA, Auth, SAN)
    cat <<EOF > ssl.conf
[ req ]
prompt = no
default_bits = 4096
distinguished_name = dn
x509_extensions = v3_ext

[ dn ]
C = TW
ST = Taiwan
L = Taipei
O = Illumio
OU = IT
CN = pce.lab.local

[ v3_ext ]
basicConstraints = CA:TRUE
keyUsage = critical, DigitalSignature, KeyEncipherment, CertificateSign
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = pce.lab.local

EOF
# 建立 ssl.conf 後執行：
openssl req -x509 -new -nodes -newkey rsa:4096 \
  -keyout server.key -out server.crt \
  -days 3650 -config ssl.conf -extensions v3_ext

sudo cp server.crt /var/lib/illumio-pce/cert/
sudo cp server.key /var/lib/illumio-pce/cert/
```

### 步驟 3：初始化 PCE（SNC 通常由安裝精靈完成，需以 root 執行）

```bash
# 方法一：互動式設定 (需以 root 執行，避開別名)
/opt/illumio-pce/illumio-pce-env setup

# 方法二：單行指令式設定 (需以 root 執行，並依環境修改參數)
/opt/illumio-pce/illumio-pce-env setup -b node_type=core pce_fqdn=tpce.lab.local service_discovery_fqdn=tpce.lab.local email_address=<EMAIL_ADDRESS> cluster_public_ips:cluster_fqdn=172.16.15.131 cluster_type=snc0

# 設定 runtime_env.yml 的權限
chown root:ilo-pce /etc/illumio-pce/runtime_env.yml
chmod 640 /etc/illumio-pce/runtime_env.yml
ls -l /etc/illumio-pce/runtime_env.yml

# 指定服務IP
echo "internal_service_ip: 172.16.15.131" >> /etc/illumio-pce/runtime_env.yml

# 啟用「使用者邀請連結」功能
echo "expose_user_invitation_link: true" >> /etc/illumio-pce/runtime_env.yml

# 關閉不安全的 TLS 加密套件
echo "insecure_tls_weak_ciphers_enabled: false" >> /etc/illumio-pce/runtime_env.yml

# 增加 HSTS (HTTP Strict Transport Security) 安全參數
echo -e "\nserver_load_balancer:\n  strict_transport_security_max_age_in_seconds: 31536000" >> /etc/illumio-pce/runtime_env.yml
```

### 步驟 4：啟動 PCE 至 Runlevel 1（僅主節點）

```bash
illumio-pce-ctl start --runlevel 1 && illumio-pce-ctl cluster-status -w
```

### 步驟 5：檢視錯誤日誌（所有節點）

```bash
cat /var/log/illumio-pce/pce_error.log
```

### 步驟 6：初始化 PCE 資料庫（僅主節點，需在 runlevel 1 狀態下）

```bash
sudo -u ilo-pce illumio-pce-db-management setup
```

### 步驟 6.5：執行資料庫 migration

原廠要求在 `db-management setup` 後執行 migrate，否則部分後續操作（升級、節點異動）會異常。

```bash
# 仍在 runlevel 1 下執行
sudo -u ilo-pce /opt/illumio-pce/illumio-pce-db-management migrate
```

### 步驟 7：啟動完整 PCE 至 Runlevel 5（僅主節點）

```bash
illumio-pce-ctl start --runlevel 5 && illumio-pce-ctl cluster-status -w
```

### 步驟 8：建立第一個使用者與組織（僅主節點）

```bash
illumio-pce-db-management create-domain --user-name admin@lab.local --full-name 'admin' --org-name 'lab'
```

### 步驟 9：上傳與設定 VEN 軟體版本（僅主節點）

```bash
# 安裝版本相容性矩陣檔
illumio-pce-ctl compatibility-matrix-install /tmp/illumio-release-compatibility-56-361.tar.bz2

# 上傳 VEN 套件至 PCE
illumio-pce-ctl ven-software-install /tmp/illumio-ven-bundle-23.2.24-327.tar.bz2

# 列出目前已上傳的 VEN 版本
sudo -u ilo-pce illumio-pce-ctl ven-software-releases-list

# 設定預設的 VEN 發佈版本
illumio-pce-ctl ven-software-release-set-default release 23.2.24-327
```

### 步驟 10（選擇性）：系統 CA 信任庫設定

```bash
# --- Ubuntu / Debian ---
sudo apt-get install -y ca-certificates
sudo cp local-ca.crt /usr/local/share/ca-certificates
sudo update-ca-certificates

# --- CentOS / RHEL ---
cp ca.crt /etc/pki/ca-trust/source/anchors/
update-ca-trust enable && update-ca-trust extract
```

### 步驟 11：OpenSSL 憑證診斷工具

使用 `openssl s_client` 測試遠端主機的 TLS 連線與憑證鏈，可用於排查 PCE 或外部服務的憑證問題；也可擷取伺服器完整憑證鏈並存為本機檔案。

```bash
# 測試遠端主機的 TLS 連線與憑證
openssl s_client -connect <EXAMPLE_FQDN>:443 -servername <EXAMPLE_FQDN>

# 擷取遠端主機的完整憑證鏈並存檔
openssl s_client -showcerts -servername www.example.com -connect www.example.com:443 </dev/null 2>/dev/null | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' > ca.crt
```

### 步驟 12：離線套件安裝

適用於無法連線外部網路的 PCE 部署環境，將離線套件包解壓縮後使用 `dnf`/`yum` 從本地目錄強制安裝所有 RPM 套件。

```bash
# 解壓縮離線套件包
tar -xzvf offline-packages.tar.gz
cd offline-packages

# 使用 dnf/yum 從本地目錄安裝所有 RPM 套件
dnf install --disablerepo=* --allowerasing ./*.rpm
```

### 步驟 13：PCE 自簽憑證產生（選擇性，不建議用於生產環境）

使用 `illumio-pce-env setup --generate-cert --force` 產生新的自簽 TLS 憑證；此操作會覆蓋現有憑證，執行前請務必備份。

```bash
illumio-pce-env setup --generate-cert --force
```

### 步驟 14：其他維運與診斷工具

提供強制終止 `illumio_ven` 行程、快速掃描連接埠開放狀態，以及啟動臨時 HTTP 檔案伺服器的輔助指令。

```bash
# 強制終止所有 illumio_ven 相關的行程 (請謹慎使用)
ps aux | grep illumio_ven | awk '{print $2}' | xargs kill -9

# 快速掃描指定 IP 的 80-85 連接埠是否開放
for port in $(seq 80 85); do timeout 0.5 bash -c "</dev/tcp/192.168.1.1/$port" 2>/dev/null && echo "Port $port OPEN" || echo "Port $port CLOSED"; done

# 在當前目錄啟動一個簡易的 HTTP 檔案伺服器
python3 -m http.server 8080
```

### 步驟 15：SSH 加密套件調整

基於安全性考量，限制 SSH 服務使用的加密演算法與 MAC 種類，需編輯 `/etc/ssh/sshd_config` 並重啟服務。

```bash
# 編輯 SSH 伺服器設定檔
vi /etc/ssh/sshd_config

# 在 sshd_config 中新增或修改以下兩行
Ciphers aes128-ctr,aes192-ctr,aes256-ctr
MACs hmac-sha1,umac-64@openssh.com,hmac-sha2-256,hmac-sha2-512

# 重新啟動 SSH 服務使設定生效
systemctl restart sshd
```

## 4. 驗證

```bash
# 確認 cluster-status 顯示所有服務正常
illumio-pce-ctl cluster-status -w

# 確認防火牆已停用（預期回傳 not running）
firewall-cmd --state

# 確認 runtime_env.yml 權限正確
ls -l /etc/illumio-pce/runtime_env.yml
```

## 5. 失敗回滾 / 救援

```bash
# 查看錯誤日誌排查問題
cat /var/log/illumio-pce/pce_error.log
```

若資料庫初始化失敗，確認磁碟空間、資料庫連線參數及 `ilo-pce` 使用者權限後重新執行 `illumio-pce-db-management setup`。

## 6. 原廠文件參照

- [NotebookLM] Core 25.4 Administration §PCE Control Interface and Commands — 原廠建議以 softlink 在 /usr/bin 或修改 $HOME/.bashrc PATH 來存取 PCE 指令，非 /etc/profile.d/ 全域別名
- [NotebookLM] Core 25.4 Administration §Database Migration, Failover, and Restore > Migrate PCE Databases — 明確要求新安裝後執行 illumio-pce-db-management migrate（runlevel 1 狀態下），再 set-runlevel 5
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Set Up PCE for VEN Installation > Upload the VEN Upgrade Compatibility Matrix — 相容性矩陣必須在 VEN bundle 之前上傳
- [NotebookLM] Core 25.4 Administration §PCE Runlevels — start --runlevel 1、db-management setup、set-runlevel 5 流程與原廠一致

## 7. 與原廠差異（若有）

- **命令別名方式**：SOP 使用 /etc/profile.d/ 全域別名；原廠（Admin 25.4 §PCE Control Interface）建議 /usr/bin softlink 或個人 $HOME/.bashrc PATH，差異為環境適配選擇，非錯誤。
- **停用 firewalld**：SOP 完全停用並 mask firewalld；原廠文件未提及此步驟（視為 OS 先決條件由管理員自行處理），SOP 補強合理但略激進（生產環境建議精細規則）。
- **憑證權限 chmod 400 / chown ilo-pce**：原廠文件未明確指定此權限設定，SOP 為安全補強，合理。
- **runtime_env.yml 安全參數**（expose_user_invitation_link、insecure_tls_weak_ciphers_enabled、HSTS）：原廠文件無對應說明，SOP 自行補強，需確認當前版本支援性。
- 原廠必要步驟 `illumio-pce-db-management migrate` 已補入 §3 步驟 6.5（2026-05-29 編輯回合）。
