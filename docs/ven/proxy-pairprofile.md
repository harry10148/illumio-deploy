> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/Illumio_ven_proxy_pairprofile.txt`

# Illumio VEN — 透過 Proxy 配對與 Pairing Profile

## 1. 目的與適用情境

在網路出口必須經過 Proxy 的環境中，於 Windows（PowerShell）和 Linux（Bash）平台安裝並啟用 Illumio VEN，同時確保 VEN 安裝後能建立 Proxy 放行規則，避免啟用後因無法直連 PCE 而顯示為 Offline。

## 2. 前置條件

- Proxy 伺服器 IP 與 Port 已知（本文件範例：`172.16.15.106:3128`）
- 主機可透過 Proxy 連線至 PCE FQDN TCP 8443
- 已取得有效的 Activation Code 及 Pairing Profile ID
- Windows：PowerShell 以系統管理員身分執行
- Linux：具備 root 或 sudo 權限

## 3. 操作步驟

### 一、Windows 平台（PowerShell）

修改重點：
1. 前段：注入 `[DefaultWebProxy]` 以解決 `pair.ps1` 下載問題。
2. 後段：新增 `-proxy-server` 參數，確保 VEN 安裝後能透過 Proxy 連線至 PCE。

```powershell
PowerShell -Command "& {Set-ExecutionPolicy -Scope process remotesigned -Force; >>> [NEW] [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy('http://172.16.15.106:3128'); <<< Start-Sleep -s 3; Set-Variable -Name ErrorActionPreference -Value SilentlyContinue; [System.Net.ServicePointManager]::SecurityProtocol=[Enum]::ToObject([System.Net.SecurityProtocolType], 3072); Set-Variable -Name ErrorActionPreference -Value Continue; (New-Object System.Net.WebClient).DownloadFile('https://pce.lab.local:8443/api/v27/software/ven/image?pair_script=pair.ps1&profile_id=7', (echo $env:windir\temp\pair.ps1)); & $env:windir\temp\pair.ps1 -management-server pce.lab.local:8443 -activation-code <ACTIVATION_CODE> >>> [NEW] -proxy-server 172.16.15.106:3128 <<<;}"
```

### 二、Linux 平台（Bash/Shell）

修改重點：
1. 前段：Export `https_proxy` 變數以解決 curl 下載問題。
2. 後段：新增 `--proxy-server` 參數，確保 VEN 安裝後能透過 Proxy 連線至 PCE。

```bash
>>> [NEW] export https_proxy='http://172.16.15.106:3128'; <<< rm -fr /opt/illumio_ven_data/tmp && umask 026 && mkdir -p /opt/illumio_ven_data/tmp && curl --tlsv1 "https://pce.lab.local:8443/api/v27/software/ven/image?pair_script=pair.sh&profile_id=7" -o /opt/illumio_ven_data/tmp/pair.sh && chmod +x /opt/illumio_ven_data/tmp/pair.sh && /opt/illumio_ven_data/tmp/pair.sh --management-server pce.lab.local:8443 --activation-code <ACTIVATION_CODE> >>> [NEW] --proxy-server 172.16.15.106:3128 <<<
```

### 三、技術補充

根據官方指南（Prepare for VEN Installation / Proxy Support），指令末端的參數至關重要：

1. 參數名稱：
   - Windows: `-proxy-server <IP:Port>`
   - Linux: `--proxy-server <IP:Port>`

2. 功能說明（Enforce an allow rule）：

   加上此參數後，VEN 會將指定的 Proxy 用於與 PCE 的通訊。**注意：此參數不會自動在本地防火牆建立 Allow 規則**；若 VEN 處於 Selective Enforcement 或 Full Enforcement 模式，必須在 PCE 安全政策中手動為該 Proxy IP 加入 Allow rule，否則 VEN 無法連線到 PCE 而離線。

3. 風險提示：
   若遺漏此參數，僅在下載階段設定 Proxy（前段），VEN 安裝後可能會因為無法連線至 PCE 而顯示為 Offline，且無法接收新的策略更新。

## 4. 驗證

安裝完成後，在 PCE Web UI 確認 VEN 狀態顯示為 Online，且 Policy Status 正常同步。

## 5. 失敗回滾 / 救援

- — 無 —

若 VEN 安裝後顯示 Offline，確認指令中包含 `-proxy-server`（Windows）或 `--proxy-server`（Linux）參數，並確認已在 PCE 安全政策中手動為 Proxy IP 加入 Allow rule。

## 6. 原廠文件參照

- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §VEN Proxy Support > Linux Pairing Script Activation for Proxy Servers — Linux 端 -x <proxy> 加入 curl、--proxy-server 加入 pair.sh 執行
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Configure a VEN-specific Windows Proxy — Windows 端 -proxy-server 參數加在 activation-code 之後
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §VEN Proxy Support > CAUTION — 原廠明確警告：proxy 放行規則**不會自動建立**，需在安全政策中手動加入 Allow 規則，否則 Selective/Full Enforcement 後 VEN 將無法連線 PCE

## 7. 與原廠差異（若有）

- 原 SOP §3「`--proxy-server` 自動建立防火牆 Allow 規則」說明有誤已修正（2026-05-29 編輯回合）。
- **Proxy 設定位置**：Windows 使用 [System.Net.WebRequest]::DefaultWebProxy（前段）+ -proxy-server（後段）的雙段設定，與原廠指引一致。
