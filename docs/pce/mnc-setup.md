> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/illumio_pce_mnc_setup_v4.txt`

# Illumio PCE MNC 安裝（多節點叢集）

## 1. 目的與適用情境

在 RHEL/CentOS 8.x 或 9.x 上以多節點叢集（MNC）模式部署 Illumio PCE，包含 2 台 Core 節點（Web UI/API/事件服務）與 2 台 Data 節點（資料庫/流量儲存），適用於生產環境高可用架構。

## 2. 前置條件

- 4 台節點（core0、core1、data0、data1）均已安裝 RHEL/CentOS 8.x 或 9.x
- NTP 時鐘精確同步（節點間時差過大會導致資料庫與憑證驗證失敗）
- DNS 可正確解析所有節點 FQDN 及負載平衡器 VIP
- 憑證 CN/SAN 包含 PCE FQDN、負載平衡器 VIP 及所有 Core 節點主機名稱
- 已開放叢集內部通訊連接埠（TCP 3100-6300、8000-8400、9443、11200-11300、24200-25300）
- VEN 至 VIP：TCP 8443、8444；Web UI 至 VIP：TCP 9443
- 具備 root 權限
- 已準備好伺服器憑證（server.crt、server.key）與根 CA 憑證

## 3. 操作步驟

### 第 1 章：系統環境準備（所有 4 台節點）

#### 1.1 時間同步

```bash
# 1. 檢查目前狀態
timedatectl

# 2. 設定 NTP (請依環境修改 IP)
# 編輯設定檔：vi /etc/chrony.conf
# 加入行：server 172.16.15.254 iburst
# 加入行：user ilo-pce

# 3. 設定權限並重啟服務
chown -R ilo-pce:ilo-pce /run/chrony /etc/chrony.keys
sudo systemctl restart chronyd

# 4. 確認同步狀態 (需看到 * 號表示已鎖定)
chronyc sources -v
chronyd -Q -t 3 'server 172.16.15.254 iburst'
```

#### 1.2 安裝相依套件

```bash
# 若為 RHEL/CentOS 8.x
sudo dnf install -y bash bzip2 chkconfig coreutils findutils gawk grep \
initscripts logrotate net-tools procps-ng sed shadow-utils rsyslog tar \
util-linux zlib glibc libgcc libstdc++ ncurses-libs libuuid openssl-libs \
readline libselinux

# 若為 RHEL/CentOS 9.x
sudo dnf install -y bash bzip2 chkconfig coreutils findutils gawk grep \
glibc-langpack-en initscripts logrotate net-tools procps-ng sed shadow-utils \
rsyslog tar util-linux glibc libgcc libstdc++ ncurses-libs libuuid libxml2 \
openssl-libs zlib xz-libs libxcrypt

# 驗證指令 (檢查函式庫連結)
sudo ldconfig -p | egrep 'lib(ssl|crypto|uuid|z|stdc++|gcc|ncurses)'
```

#### 1.3 安裝 Illumio RPM 軟體

```bash
# 情境 A：在 Core Node 上執行 (安裝主程式 + UI)
rpm -Uvh /tmp/illumio-pce-xx.x.x-xx.elx.x86_64.rpm
rpm -Uvh /tmp/illumio-pce-ui-xx.x.xx.UIx-xx.x86_64.rpm

# 情境 B：在 Data Node 上執行 (僅安裝主程式)
rpm -Uvh /tmp/illumio-pce-xx.x.x-xx.elx.x86_64.rpm
```

### 第 2 章：系統核心參數調優

#### 2.1 Systemd 資源限制（所有節點）

```bash
sudo mkdir -p /etc/systemd/system/illumio-pce.service.d/
echo -e "[Service]\nLimitCORE=0\nLimitNOFILE=65535\nLimitNPROC=65535" | \
sudo tee /etc/systemd/system/illumio-pce.service.d/override.conf

sudo systemctl daemon-reload

#檢查參數有沒有生效，如未生效需手動加入，在少數案例有遇到在ilo-pce使用者kernel參數未生效
sudo -u ilo-pce ulimit -n
echo -e "ilo-pce soft core unlimited\nilo-pce hard core unlimited\nilo-pce hard nproc 65535\nilo-pce soft nproc 65535\nilo-pce hard nofile 65535\nilo-pce soft nofile 65535" | \
sudo tee /etc/security/limits.conf
```

#### 2.2 核心網路參數（僅限 Core 節點）

```bash
echo -e "fs.file-max = 2000000\nnet.core.somaxconn = 16384" | sudo tee /etc/sysctl.d/99-illumio.conf
sudo modprobe nf_conntrack
echo "options nf_conntrack hashsize=262144" | sudo tee /etc/modprobe.d/illumio.conf
sudo sysctl -p /etc/sysctl.d/99-illumio.conf
```

#### 2.3 核心記憶體參數（僅限 Data 節點）

```bash
echo -e "fs.file-max = 2000000\nvm.overcommit_memory = 1" | sudo tee /etc/sysctl.d/99-illumio.conf
sudo sysctl -p /etc/sysctl.d/99-illumio.conf
```

### 第 3 章：環境變數與憑證部署（所有節點）

#### 3.1 設定命令別名

```bash
echo 'alias illumio-pce-env="sudo -u ilo-pce /opt/illumio-pce/illumio-pce-env"' | sudo tee /etc/profile.d/global_aliases.sh
echo 'alias illumio-pce-ctl="sudo -u ilo-pce /opt/illumio-pce/illumio-pce-ctl"' | sudo tee -a /etc/profile.d/global_aliases.sh
echo 'alias illumio-pce-db-management="sudo -u ilo-pce /opt/illumio-pce/illumio-pce-db-management"' | sudo tee -a /etc/profile.d/global_aliases.sh

source /etc/profile.d/global_aliases.sh
```

#### 3.2 憑證準備（擇一情境）

```bash
# 情境 A：使用既有的憑證檔案
sudo cp /tmp/server.crt /var/lib/illumio-pce/cert
sudo cp /tmp/server.key /var/lib/illumio-pce/cert

# 情境 B：快速建立自簽 Root 憑證 (包含 CA, Auth, SAN)
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
    DNS.2 = core0.lab.local
    DNS.3 = core1.lab.local
    DNS.4 = data0.lab.local
    DNS.5 = data1.lab.local
    EOF
# 建立 ssl.conf 後執行：
openssl req -x509 -new -nodes -newkey rsa:4096 \
  -keyout server.key -out server.crt \
  -days 3650 -config ssl.conf -extensions v3_ext

sudo cp server.crt /var/lib/illumio-pce/cert/
sudo cp server.key /var/lib/illumio-pce/cert/
```

#### 3.3 憑證權限與 CA 信任設定（所有節點必做）

```bash
sudo chown ilo-pce /var/lib/illumio-pce/cert/*
sudo chmod 400 /var/lib/illumio-pce/cert/*

sudo cp /var/lib/illumio-pce/cert/server.crt /etc/pki/ca-trust/source/anchors/illumio-ca.crt
sudo update-ca-trust enable && sudo update-ca-trust extract
```

### 第 4 章：叢集初始化（僅限第 1 台 Core 節點）

#### 4.1 執行安裝精靈

```bash
# 使用互動式精靈產生 runtime_env.yml (需以 root 執行完整路徑)
sudo /opt/illumio-pce/illumio-pce-env setup

# --- 以下為互動式精靈的主要參數說明 ---
# pce_fqdn: pce.lab.local                  (PCE 對外 FQDN)
# service_discovery_fqdn: <core0_IP>       (第一個 Core 節點的 IP 或 FQDN)
# cluster_public_ips:
#   cluster_fqdn:
#   - <SLB_VIP>                            (負載平衡器的 VIP)
#   - <core0_IP>                           (Core 0 節點的 IP)
#   - <core1_IP>                           (Core 1 節點的 IP)
# node_type: core                          (此節點的角色)
# front_end_https_port: 8443               (VEN 連線用的 Port)
# front_end_management_https_port: 9443    (Web UI 和 API 用的 Port)
# front_end_event_service_port: 8444       (事件服務用的 Port)
# web_service_private_key: /var/lib/illumio-pce/cert/server.key
# web_service_certificate: /var/lib/illumio-pce/cert/server.crt
# service_discovery_encryption_key: ****** (叢集加密金鑰，可用 openssl rand -base64 16 產生)
# smtp_relay_address: 172.16.15.103:25     (SMTP 伺服器)
```

#### 4.2 追加進階設定

```bash
echo -e 'traffic_datastore:\n  data_dir: "/database/explorer"\n  max_disk_usage_gb: 100\n  partition_fraction: 0.5' | \
sudo tee -a /etc/illumio-pce/runtime_env.yml > /dev/null

echo -e '\nserver_load_balancer:\n  strict_transport_security_max_age_in_seconds: 31536000' | \
sudo tee -a /etc/illumio-pce/runtime_env.yml > /dev/null

echo "expose_user_invitation_link: true" | sudo tee -a /etc/illumio-pce/runtime_env.yml
```

### 第 5 章：設定檔分發與 IP 綁定

#### 5.1 複製檔案並修改角色（從第 1 台 Core 執行）

```bash
cat /etc/illumio-pce/runtime_env.yml | ssh root@172.16.15.132 "cat > /etc/illumio-pce/runtime_env.yml"

# 傳送並修改 node_type 為 data0 與 data1
cat /etc/illumio-pce/runtime_env.yml | ssh root@172.16.15.133 "sed 's/^node_type: core$/node_type: data0/' > /etc/illumio-pce/runtime_env.yml"
cat /etc/illumio-pce/runtime_env.yml | ssh root@172.16.15.134 "sed 's/^node_type: core$/node_type: data1/' > /etc/illumio-pce/runtime_env.yml"
```

#### 5.2 綁定各節點 IP（在各節點分別執行）

```bash
# Core 1
echo "internal_service_ip: 172.16.15.131" >> /etc/illumio-pce/runtime_env.yml
# Core 2
echo "internal_service_ip: 172.16.15.132" >> /etc/illumio-pce/runtime_env.yml
# Data 1
echo "internal_service_ip: 172.16.15.133" >> /etc/illumio-pce/runtime_env.yml
# Data 2
echo "internal_service_ip: 172.16.15.134" >> /etc/illumio-pce/runtime_env.yml
```

#### 5.3 修正檔案權限與環境驗證（所有節點）

```bash
sudo chown root:ilo-pce /etc/illumio-pce/runtime_env.yml
sudo chmod 640 /etc/illumio-pce/runtime_env.yml

# 執行環境檢查
sudo -u ilo-pce illumio-pce-env check
```

### 第 6 章：服務啟動與資料庫初始化

#### 6.1 啟動至 Runlevel 1（所有 4 台節點同時執行）

```bash
illumio-pce-ctl start --runlevel 1

# 檢查狀態 (需等待顯示 RUNNING)
illumio-pce-ctl cluster-status -w 300
```

#### 6.2 初始化資料庫（僅限 1 台 Data 節點執行即可）

```bash
sudo -u ilo-pce illumio-pce-db-management setup
```

#### 6.2.5 執行資料庫 migration（仍限同一台 Data 節點）

原廠要求在 `db-management setup` 後執行 migrate，否則部分後續操作（升級、節點異動）會異常。

```bash
# 仍在 runlevel 1 下執行
sudo -u ilo-pce /opt/illumio-pce/illumio-pce-db-management migrate
```

#### 6.3 全面啟動（任意一台節點執行即可）

```bash
illumio-pce-ctl set-runlevel 5

# 最終檢查
illumio-pce-ctl status -sv
```

### 第 7 章：後續開通作業（僅限 Core 節點）

#### 7.1 建立管理員帳號

```bash
illumio-pce-db-management create-domain \
--user-name admin@example.com \
--full-name 'Administrator' \
--org-name 'My_Organization'
```

#### 7.2 上傳 VEN 安裝包

```bash
# 1. 安裝相容性矩陣 (必須先於 Bundle 上傳)
illumio-pce-ctl compatibility-matrix-install /tmp/illumio-release-compatibility-xx.tar.bz2

# 2. 上傳 VEN 軟體 bundle
illumio-pce-ctl ven-software-install /tmp/illumio-ven-bundle-xx.tar.bz2

# 3. 設定預設版本
illumio-pce-ctl ven-software-releases-list
illumio-pce-ctl ven-software-release-set-default release xx.x.xx-xxx
```

## 4. 驗證

```bash
# 最終叢集狀態檢查（所有服務應正常）
illumio-pce-ctl status -sv

# 確認 cluster-status 顯示 RUNNING
illumio-pce-ctl cluster-status -w 300

# 確認函式庫連結正確
sudo ldconfig -p | egrep 'lib(ssl|crypto|uuid|z|stdc++|gcc|ncurses)'
```

## 5. 失敗回滾 / 救援

若資料庫初始化失敗或服務異常，停止所有節點並查閱日誌：

```bash
illumio-pce-ctl stop
cat /var/log/illumio-pce/pce_error.log
```

確認各節點的 `runtime_env.yml` 中 `node_type` 設定正確（core0 為 core，data 節點分別為 data0/data1），以及憑證權限設定正確後重新啟動。

## 6. 原廠文件參照

- [NotebookLM] Core 25.4 Administration §Database Migration, Failover, and Restore > Migrate PCE Databases — db-management setup 後需執行 migrate，runlevel 1 → migrate → set-runlevel 5 流程
- [NotebookLM] Core 25.4 Administration §Manage Multi-Node Traffic Database > Expand the Existing Traffic Database — 提及各節點需更新 runtime_env.yml，但未指定傳輸方式
- [NotebookLM] Core 25.4 Administration §Site Failure (Split Clusters) > Revert Standalone Cluster — 明確要求節點逐一啟動，非同時啟動（MNC 啟動順序參考）
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Set Up PCE for VEN Installation — compatibility-matrix 需先於 VEN bundle 上傳

## 7. 與原廠差異（若有）

- **OS 相依套件與 sysctl 調優**：NotebookLM 資料庫中 MNC 安裝章節不完整（PCE Installation Guide 25.4 未收錄），sysctl 參數（fs.file-max、net.core.somaxconn、vm.overcommit_memory）及 systemd LimitNOFILE=65535 均為 SOP 自行補強，合理性高但需對照 25.2.x 安裝指南確認。
- **runtime_env.yml 分發方式**：SOP 以 ssh + cat pipe 分發，原廠未規定方式，SOP 補強合理。
- 原廠必要步驟 `illumio-pce-db-management migrate` 已補入 §3 步驟 6.2.5（2026-05-29 編輯回合）。
- **命令別名**：同 snc-setup，原廠建議 /usr/bin softlink，SOP 使用 /etc/profile.d/，差異為環境選擇。
