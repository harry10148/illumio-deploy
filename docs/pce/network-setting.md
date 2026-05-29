> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/illumio_snc_network_setting.txt`

# Illumio PCE SNC 網路設定

## 1. 目的與適用情境

使用 NetworkManager CLI（nmcli）為 Illumio PCE SNC 節點設定靜態或動態 IP，包含清理 CentOS 9 舊版 ifcfg 衝突設定檔、三種設定方案（靜態 IP 重建、DHCP 重建、既有修改），以及驗證步驟；適用於初次部署或 IP 變更情境。

## 2. 前置條件

- 確認網卡名稱：`nmcli device`（本文件範例使用 `ens192`，若不同請替換）
- 確認設定檔名稱（針對修改情境）：`nmcli connection show`
- 具備 root 或 sudo 權限

## 3. 操作步驟

### 第一階段：清理衝突設定（Ghost Profiles）

CentOS 9 若偵測到舊版 `/etc/sysconfig/network-scripts/ifcfg-*` 檔案，會自動在記憶體中產生名為 "System `<網卡名>`" 的設定檔，導致設定衝突。無論選擇哪種設定方式，建議先執行此步驟確保環境單純。

```bash
# 1. 備份並移走舊的 ifcfg 檔案 (關鍵步驟，防止重開機後衝突再現)
mv /etc/sysconfig/network-scripts/ifcfg-ens192 /etc/sysconfig/network-scripts/ifcfg-ens192.bak

# 2. 移除記憶體中的 "System" 衝突設定檔
nmcli connection delete "System ens192"

# 3. 重載 NetworkManager
nmcli connection reload
```

（檢查點）執行 `nmcli connection show`，確認列表中已無 "System ens192"。

### 第二階段：設定網路（三選一）

**方案 A：徹底重建 → 設定固定 IP（Static IP）— 推薦**

適用：希望刪除現有混亂設定，建立一個全新、乾淨的設定檔。

```bash
# (選用) 刪除現有同名設定檔 (確保唯一)
nmcli connection delete "ens192"

# 建立新設定 (請修改 IP 數值，複製整段包含反斜線)
nmcli connection add con-name "ens192" ifname "ens192" type ethernet \
ipv4.method manual \
ipv4.addresses "172.16.15.131/24" \
ipv4.gateway "172.16.15.254" \
ipv4.dns "172.16.15.100" \
connection.autoconnect yes
```

**方案 B：徹底重建 → 設定 DHCP**

適用：希望刪除現有混亂設定，建立一個全新自動取得 IP 的設定檔。

```bash
# (選用) 刪除現有同名設定檔
nmcli connection delete "ens192"

# 建立新設定
nmcli connection add con-name "ens192" ifname "ens192" type ethernet \
ipv4.method auto \
connection.autoconnect yes
```

**方案 C：保留現狀 → 修改既有設定檔（Modify）**

適用：`nmcli` 列表中已有正常的 "ens192" 設定檔，只想將其修改為固定 IP。

```bash
# 修改設定 (請修改 IP 數值，複製整段包含反斜線)
nmcli connection modify "ens192" \
ipv4.method manual \
ipv4.addresses "172.16.15.131/24" \
ipv4.gateway "172.16.15.254" \
ipv4.dns "172.16.15.100" \
connection.autoconnect yes

# (備用：單行版本，若上方貼上失敗可改用此行)
nmcli connection modify "ens192" ipv4.method manual ipv4.addresses "172.16.15.131/24" ipv4.gateway "172.16.15.254" ipv4.dns "172.16.15.100" connection.autoconnect yes
```

### 第三階段：啟用與驗證（必須執行）

```bash
# 1. 啟用連線 (套用變更)
nmcli connection up "ens192"

# 2. 驗證設定檔狀態
# (正確狀態：NAME欄位應只有一個 ens192 呈現綠色/粗體，且無 System 開頭項目)
nmcli connection show --active

# 3. 檢查 IP 位址
ip a show ens192

# 4. 測試連線 (Ping Gateway 或 Google DNS)
ping -c 4 8.8.8.8
```

## 4. 驗證

```bash
nmcli connection show --active
ip a show ens192
ping -c 4 8.8.8.8
```

## 5. 失敗回滾 / 救援

**Q1：執行 modify 時出現 "Error: unknown connection 'ens192'"？**
設定檔名稱可能不是 `ens192`。請用 `nmcli connection show` 查看 NAME 欄位，並將指令中的 "ens192" 替換為實際名稱（如 "Wired connection 1"）。

**Q2：設定後 IP 沒變，或 nmcli show 還是看到 System ens192？**
代表 `/etc/sysconfig/network-scripts/` 目錄下仍有殘留檔案。請執行 `ls /etc/sysconfig/network-scripts/`，刪除任何以 `ifcfg-ens192` 開頭的檔案，並再次執行 `nmcli connection reload`。

## 6. 原廠文件參照

- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §System Requirements — OS 網路設定（nmcli、靜態 IP）被視為安裝前提條件，由管理員依組織標準自行處理，原廠未提供具體 nmcli 步驟
- [Web] https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_networking/configuring-an-ethernet-connection_configuring-and-managing-networking — RHEL 9 nmcli 靜態 IP 設定官方參考

## 7. 與原廠差異（若有）

- **原廠文件未涵蓋**：Illumio 官方文件不包含 OS 層網路設定（nmcli 靜態 IP、ifcfg 衝突清理）；此 SOP 為環境準備補強，內容基於 RHEL/NetworkManager 標準操作，非 Illumio 特有步驟。
