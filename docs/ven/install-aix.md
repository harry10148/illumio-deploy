> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/illumio_ven_aix_install.txt`

# Illumio VEN — AIX 手動安裝

## 1. 目的與適用情境

在 IBM AIX 主機上手動安裝 Illumio VEN，涵蓋安裝前 IPFilter 狀態確認、移除舊版 IPFilter、安裝 Illumio 提供的更新版 IPFilter 與 CA 憑證部署、安裝 VEN 套件，以及啟用 VEN 與 PCE 配對等完整步驟。

目前 aix/ 僅有 README.md 說明，無自動腳本。

## 2. 前置條件

- IBM AIX 系統，具備 root 權限
- 主機能解析 PCE FQDN 且防火牆允許連線至 TCP 8443
- 已取得有效的 Activation Code
- 安裝套件（IPFilter 與 VEN）已備妥於 `/tmp` 目錄
- 已確認現有 IPFilter 版本（是否為 Illumio 版或 OS 原生版）

## 3. 操作步驟

### 第 1 章：檢查是否已安裝 IPFilter

```bash
# 1. 列出 32 位元與 64 位元 IPFilter 的設定/狀態 
# (若未安裝或未定義，可能無輸出或報錯)
/usr/lib/methods/cfg_ipf -la
/lib/methods/cfg_ipf64 -l

# 2. 檢查 AIX 已安裝的 LPP 套件清單中是否有 ipfl (ipfl.rte)
# (可依據供應商與版本判斷是 Illumio 版或原生版)
lslpp -l | grep -i ipfl
    
# 3. 列出系統已套用的 Emergency Fix (臨時修補) 清單
emgr -l

# 4. 查找特定的 efix/APAR 識別碼 (例如: IV89793)
emgr -l | grep IV89793
```

### 第 2 章：移除既有 IPFilter（非 Illumio 版本）

注意：執行移除前，請務必確認目標為「非 Illumio」版本的 IPFilter。若已是 Illumio 更新版則無須移除。以下指令的減號皆為標準 ASCII `-u`，請勿輸入成全形符號。

```bash
# 1. 卸載/取消定義 32 位元與 64 位元 IPFilter
# (若報錯可先確認是否存在該方法檔與對應裝置狀態)
/lib/methods/cfg_ipf -u
/lib/methods/cfg_ipf64 -u

# 2. 移除 ipfl.rte 軟體本體
installp -u ipfl.rte

# 3. 移除指定的 efix 套件檔 (請確保檔案在當前目錄或提供完整路徑)
emgr -r -L IV89793s5a.161102.epkg.Z
```

### 第 3 章：安裝更新後的 IPFilter 與憑證部署

假設以下操作皆於 `/tmp` 目錄下進行。

安裝 IPFilter：

```bash
# 更新目錄索引並安裝 IPFilter (-a: 安裝, -c: 清理暫存, -Y: 接受授權, -d: 指定來源目錄)
inutoc . && installp -acYd . ipfl
```

部署憑證：

```bash
# 1. 確保憑證存放目錄存在
mkdir -p /var/ssl/certs

# 2. 將新憑證內容以「追加」方式寫入 (避免覆蓋既有信任鏈)
cat new.crt >> /var/ssl/certs/ca-bundle.crt

# 3. 設定檔案權限為所有人可讀 (非常重要，避免 VEN 啟動失敗)
chmod 644 /var/ssl/certs/ca-bundle.crt
```

補充驗證（確認信任鏈完整）：

```bash
openssl s_client -connect <pce_fqdn>:8443 -CAfile /var/ssl/certs/ca-bundle.crt -servername <pce_fqdn>
```

### 第 4 章：安裝 Illumio VEN 套件

```bash
# 更新目錄索引並安裝 VEN 套件 (-X: 允許擴充分割區, -g: 嘗試解決相依)
inutoc . && installp -acXgd . illumio-ven

# 安裝完成後驗證 (擇一執行即可)
lslpp -L | grep -i illumio
/opt/illumio_ven/illumio-ven-ctl status
```

### 第 5 章：啟用 Illumio VEN（Activate）

啟用前確認：主機是否能解析 PCE FQDN 且防火牆允許連線至 TCP 8443；Activation Code 是否為最新有效值。

```bash
# 1. 切換至 VEN 安裝目錄
cd /opt/illumio_ven

# 2. 替換設定檔中的 PCE 佔位符 (請將 <pce_fqdn> 替換為實際網域)
perl -pi -e "s/{pce_fqdn_value}/<pce_fqdn>/g" runtime_env.yml

# 3. 替換設定檔中的 Port 佔位符 (若使用自訂埠請修改 8443)
perl -pi -e "s/{pce_port_value}/8443/g" runtime_env.yml

# 4. 啟動 VEN 並與 PCE 配對 (請將 <pce_fqdn> 替換為實際網域)
./illumio-ven-ctl activate \
--activation-code 1bf7754047275ef530e8f8fadd33bb1020b1a8c07a0b748004e6aa145ad8d3fa3710542f41b3e8f8e \
--management-server <pce_fqdn>:8443
```

狀態檢查與排錯：

```bash
# 檢查 VEN 運行狀態
/opt/illumio_ven/illumio-ven-ctl status

# 若啟用失敗，請查閱日誌檔案
# 目錄位置：/opt/illumio_ven/log/
```

## 4. 驗證

```bash
# 確認 VEN 套件已安裝
lslpp -L | grep -i illumio

# 確認 VEN 運行狀態
/opt/illumio_ven/illumio-ven-ctl status

# 確認憑證信任鏈正確
openssl s_client -connect <pce_fqdn>:8443 -CAfile /var/ssl/certs/ca-bundle.crt -servername <pce_fqdn>
```

若驗證成功，openssl 應顯示 `Verify return code: 0 (ok)`。

## 5. 失敗回滾 / 救援

- — 無 —

若啟用失敗，確認 `/opt/illumio_ven/log/` 日誌，並確保 `ca-bundle.crt` 包含完整的信任鏈（包含中繼憑證）。若系統 Perl 不可用，可改用 `sed` 替換 `runtime_env.yml` 中的佔位符。

## 6. 原廠文件參照

- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §AIX: Install and Upgrade with CLI and VEN CTL — 必須使用 Illumio 提供的 IPFilter（非 IBM 原生版），禁止使用 genfilt/mkfilt；installp -u ipfl.rte 移除舊版、inutoc . && installp -acYd . ipfl 安裝新版
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §AIX: Install and Upgrade — inutoc . && installp -acXgd . illumio-ven 安裝 VEN 套件
- [NotebookLM] Illumio Agent部署手冊_20250815.pdf §7.2 AIX 查核清單 — AIX 安裝前置確認項目，含 IPFilter 版本驗證

## 7. 與原廠差異（若有）

- **IPFilter 處理流程**：SOP 的移除（installp -u ipfl.rte + emgr -r）與安裝（inutoc + installp -acYd . ipfl）流程與原廠（Install_Upgrade §AIX）一致。
- **CA 憑證路徑**：SOP 使用 /var/ssl/certs/ca-bundle.crt（追加方式 >>），原廠文件中 AIX CA 路徑同此，chmod 644 要求亦一致。
- **VEN activate 方式**：SOP 使用 perl -pi -e 替換 runtime_env.yml 佔位符後再執行 activate，原廠未記錄此兩段式方式，但功能等同直接傳入參數，SOP 補強合理（針對 runtime_env.yml 預設佔位符設計）。
