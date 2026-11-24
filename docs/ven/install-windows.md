# Illumio VEN — Windows 安裝

> **適用版本**：Illumio PCE 25.x / 26.x，VEN 25.x / 26.x（腳本於 Windows Server 2022、VEN 26.2.20 實機驗證）  
> **最後更新**：2026-11-24

## 1. 目的與適用情境

在 Windows Server 與 Windows 用戶端上安裝 VEN 並向 PCE 配對。本文是 Windows 安裝的唯一完整說明，涵蓋三種做法：

| 做法 | 適用情境 | 使用的檔案 |
|---|---|---|
| A. 部署腳本 | 大量派送、封閉環境、要自訂目錄 | [`Deploy-Illumio.ps1`](../../windows/manual_deploy/Deploy-Illumio.ps1) 或 [`deploy-illumio.bat`](../../windows/manual_deploy/deploy-illumio.bat) |
| B. 官方配對指令 | 少量主機、直接用 PCE 產生的指令 | [`Import-RootCA.ps1`](../../windows/pairing_prereq/Import-RootCA.ps1)（只做憑證匯入） |
| C. 全手動 | 逐步驗證、排除問題 | 無 |

搭配 SCCM、Intune、GPO 的做法見 [大規模派送](./mass-deployment.md)。

## 2. 前置條件

- **權限**：系統管理員（提升權限的工作階段），或 SYSTEM。
- **作業系統**：見 [VEN 作業系統支援與相依套件](../reference/ven-os-support.md)。安裝前先套用最新的 Service Pack。
- **網路**：主機能解析 PCE 的 FQDN，並可連到 TCP 8443、8444（地端 PCE）或 TCP 443（SaaS）。
- **憑證**：PCE 憑證若由私有 CA 簽發，主機必須信任該 CA。網域環境建議用群組原則派發，腳本偵測到已存在就不會重複匯入。路徑上若有 TLS 攔截設備，必須對 VEN 到 PCE 的流量停用攔截。
- **其他**：Windows Time 服務正常；至少保留 10 GB 磁碟空間。
- **配對資訊**：PCE 位址（`FQDN:PORT`）與 Pairing Profile 產生的啟用碼。

## 3. 操作步驟

### 做法 A：部署腳本

兩支腳本的流程相同：匯入 CA 憑證 → 檢查 PCE 連線 → 靜默安裝 → 啟用。全程不需互動，可重複執行。

| | `Deploy-Illumio.ps1` | `deploy-illumio.bat` |
|---|---|---|
| 設定方式 | 參數或環境變數 | 修改檔案開頭的設定區，或環境變數 |
| 需要 PowerShell | 是（5.1 即可，支援受限語言模式） | 否，純 cmd |
| 沒有 `curl.exe` 時下載安裝檔 | 可以（完整語言模式下） | 不行，需自備安裝檔 |
| VEN 23.5 以前（只有 `illumio-ven-ctl.ps1`） | 支援 | 不支援 |

#### PowerShell

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Deploy-Illumio.ps1 `
    -ManagementServer <PCE_FQDN>:<PORT> -ActivationCode <ACTIVATION_CODE>
```

| 參數 | 說明 | 預設 |
|---|---|---|
| `-ManagementServer` | PCE 位址。也可用環境變數 `ILLUMIO_MANAGEMENT_SERVER` | 必填 |
| `-ActivationCode` | 啟用碼。也可用環境變數 `ILLUMIO_ACTIVATION_CODE` | 必填 |
| `-CertFile` | CA 憑證（PEM） | 腳本同目錄的 `illumio-ca.crt`，其次腳本內嵌憑證 |
| `-SourceDir` | 安裝檔所在目錄 | 腳本所在目錄 |
| `-ExeFile` | 安裝檔檔名 | 自動尋找 `*illumio-ven*.exe` |
| `-NoDownload` | 本機沒有安裝檔時不向 PCE 下載 | 會下載 |
| `-InstallDir` | VEN 安裝目錄 | `C:\Program Files\Illumio` |
| `-DataDir` | VEN 資料目錄 | `C:\ProgramData\Illumio` |
| `-SkipTlsCheck` | 略過安裝前的 PCE 連線檢查 | 會檢查 |
| `-ApiVersion` | 下載安裝檔使用的 PCE API 版本 | `v25` |
| `-LogFile` | 日誌檔 | `%TEMP%\IllumioDeploy.log` |

#### Batch

修改 `deploy-illumio.bat` 開頭的設定區，或由派送工具設定環境變數後直接執行：

```cmd
set ILLUMIO_MANAGEMENT_SERVER=<PCE_FQDN>:<PORT>
set ILLUMIO_ACTIVATION_CODE=<ACTIVATION_CODE>
cmd.exe /c deploy-illumio.bat
```

設定區另有 `SOURCE_DIR`、`EXE_FILE`、`INSTALL_DIR`、`DATA_DIR`、`NO_DOWNLOAD`、`SKIP_TLS_CHECK`、`API_VERSION`、`LOG_FILE`，意義與 PowerShell 參數相同。CA 憑證放在腳本同目錄並命名為 `illumio-ca.crt`。

#### 各步驟的行為

- **CA 憑證**：有提供憑證且受信任的根憑證存放區還沒有它，才會匯入；群組原則派發的憑證也算已存在。沒有提供就跳過，改用系統既有的信任憑證。
- **PCE 連線檢查**：有 `curl.exe` 時做完整的 TLS 握手並驗證信任鏈；沒有時 PowerShell 版只檢查 TCP 埠可達，Batch 版略過。檢查不通過就在安裝前中止。
- **安裝檔**：先找本機的安裝檔；找不到時以啟用碼向 PCE 的 VEN Library 下載並驗證 SHA256，這與官方 `pair.ps1` 是同一套機制。找到多個安裝檔時會中止。
- **既有安裝**：腳本從登錄機碼 `HKLM\SOFTWARE\Illumio` 讀取實際的安裝與資料路徑，所以用過自訂目錄的主機，重跑時不必再給目錄參數。
- **啟用**：資料目錄下已有 `etc\agent_id.cfg` 時視為已啟用，直接跳過。
- **重新開機**：安裝程式回報需要重新開機時，腳本仍會完成啟用，最後以結束碼 3010 結束。

啟用碼不會寫入日誌。暫存的憑證與下載的安裝檔放在每次執行新建的工作目錄，只有 SYSTEM 與 Administrators 可以存取，結束時刪除。

結束碼見 [大規模派送 §結束碼](./mass-deployment.md#結束碼)。

#### 自訂安裝目錄

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Deploy-Illumio.ps1 `
    -ManagementServer <PCE_FQDN>:<PORT> -ActivationCode <ACTIVATION_CODE> `
    -InstallDir "D:\Illumio\VEN" -DataDir "D:\Illumio\VEN_Data"
```

安裝目錄與資料目錄可各自獨立指定，對應安裝程式的 `INSTALLFOLDER` 與 `DATAFOLDER` 屬性。

#### 各 Windows 版本的差異

| 功能 | Server 2019 以上、Windows 10 1803 以上 | Server 2012 R2、2016 |
|---|---|---|
| 憑證匯入、安裝、啟用、重跑跳過 | 支援 | 支援 |
| 安裝前連線檢查 | 驗證 TLS 信任鏈 | 只檢查 TCP 埠（PowerShell 版） |
| 自動下載安裝檔 | 支援 | 僅 PowerShell 版、完整語言模式 |

差異來自 Server 2016 以前沒有內建 `curl.exe`。

### 做法 B：官方配對指令

官方配對指令會自行下載並安裝 VEN。PCE 使用私有 CA 時，先匯入憑證：

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Import-RootCA.ps1 -CertFile C:\certs\illumio-ca.crt
```

未指定 `-CertFile` 時使用腳本同目錄的 `illumio-ca.crt`，其次腳本內嵌憑證。已存在相同憑證時跳過。

接著到 PCE Web Console 的 **Servers & Endpoints > Pairing Profiles**，選定 Pairing Profile 後產生 Pairing Key，複製 Windows OS Pairing Script，在提升權限的命令提示字元執行。

### 做法 C：全手動

```powershell
# 1. 匯入 CA 憑證 (PCE 使用私有 CA 時)
certutil -addstore Root C:\certs\illumio-ca.crt

# 2. 確認 PCE 憑證受信任 (私有 CA 通常沒有可連線的撤銷清單，需加 --ssl-no-revoke)
curl.exe -sS --ssl-no-revoke -o NUL https://<PCE_FQDN>:<PORT>/

# 3. 安裝
.\illumio-ven-<VERSION>.win.x64.exe /install /quiet /norestart /log "$env:TEMP\IllumioVENInstall.log"
#    自訂目錄時加上: INSTALLFOLDER="D:\Illumio\VEN" DATAFOLDER="D:\Illumio\VEN_Data"

# 4. 啟用 (Windows 的選項前面是單一連字號)
& "C:\Program Files\Illumio\illumio-ven-ctl.exe" activate `
    -activation-code <ACTIVATION_CODE> -management-server <PCE_FQDN>:<PORT>
```

VEN 23.5 以前沒有 `illumio-ven-ctl.exe`，改用同目錄的 `illumio-ven-ctl.ps1`，參數相同。

安裝程式也可以在安裝時一併啟用，不需要另外執行 `activate`：

```cmd
illumio-ven-<VERSION>.win.x64.exe /install /quiet /norestart /log C:\Windows\Temp\IllumioVENInstall.log MANAGEMENT_SERVER=<PCE_FQDN>:<PORT> ACTIVATION_CODE=<ACTIVATION_CODE>
```

### 解除安裝

```powershell
& "C:\Program Files\Illumio\illumio-ven-ctl.exe" unpair <recommended | saved | open>
```

| 模式 | 解除後的防火牆狀態 |
|---|---|
| `recommended` | 只允許 RDP (3389) 與 WinRM (5985/5986)，直到重新開機 |
| `saved` | 還原成安裝 VEN 之前的 Windows 防火牆設定 |
| `open` | 全部開放 |

`unpair` 會在背景解除安裝（約 30 秒）並從 PCE 刪除該 workload。也可以從 PCE Web Console 的 **Servers & Endpoints > Workloads > VENs** 選取主機後按 Unpair，或從「程式和功能」移除（等同 `saved`）。

## 4. 驗證

```powershell
& "C:\Program Files\Illumio\illumio-ven-ctl.exe" status
```

- 四個服務（venAgentMgrSvc、venPlatformHandlerSvc、venVtapServerSvc、venAgentMonitorSvc）都是 Running 與 Enabled。
- `Agent State` 為 Pairing Profile 指定的模式，不是 `unpaired`。
- PCE Web Console 的 Workloads 清單出現該主機，狀態為 Online。

## 5. 失敗回滾 / 救援

| 現象 | 處理方式 |
|---|---|
| 結束碼 3 | 以系統管理員身分執行 |
| 結束碼 6，憑證匯入失敗 | 確認檔案是 PEM 格式，內容完整 |
| 結束碼 7，無法驗證 PCE 憑證 | 提供簽發 PCE 憑證的 CA；確認路徑上沒有 TLS 攔截 |
| 結束碼 7，無法連線 | 檢查 DNS、防火牆、Proxy |
| 結束碼 8，PCE 沒有符合的安裝檔或啟用碼無效 | 確認啟用碼；或自備安裝檔 |
| 結束碼 8，安裝失敗 | 查看 `%TEMP%\IllumioVENInstall.log`；確認沒有被防毒軟體攔截 |
| 結束碼 9，啟用失敗 | 確認啟用碼有效且未超過使用次數 |
| 腳本無法執行 | 執行原則由群組原則強制時 `-ExecutionPolicy Bypass` 無效，需先簽署腳本，見 [大規模派送](./mass-deployment.md#嚴格環境的注意事項) |
| 安裝後要整個退回 | `illumio-ven-ctl.exe unpair saved` |

腳本的日誌在 `%TEMP%\IllumioDeploy.log`；以 SYSTEM 執行時是 `C:\Windows\Temp\IllumioDeploy.log`。

## 6. 原廠文件參照

- [NotebookLM] Install, Configure, and Upgrade Guide 25.2 / 26.1 §Windows: Install and Upgrade with CLI and VEN CTL — `/install /quiet /norestart /log`、`INSTALLFOLDER`、`DATAFOLDER`、`MANAGEMENT_SERVER`、`ACTIVATION_CODE`；`illumio-ven-ctl.exe activate -activation-code ... -management-server ...`
- [NotebookLM] Admin Guide 25.2 / 26.1 §Commonly Used VEN Commands — VEN 23.5 以前為 `illumio-ven-ctl.ps1`，24.2.10 起為 `illumio-ven-ctl.exe`
- [Web] https://support.illumio.com/shared/software/os-support-package-dependencies/ven.html — 作業系統支援
- [現場] 官方 `pair.ps1`（PCE 26.2）— 以 `agent_0` 加啟用碼向 `/api/vNN/software/ven/image` 下載安裝檔
- [現場] 2026-11-24 於 Windows Server 2022（PowerShell 5.1）對 lab PCE 實機驗證

## 7. 與原廠差異（若有）

- **憑證撤銷檢查**：`curl.exe` 使用 Schannel，預設會檢查撤銷清單；私有 CA 的清單通常連不到而導致連線被拒，腳本因此加上 `--ssl-no-revoke`。原廠文件未提及。
- **已啟用的判斷**：以資料目錄下的 `etc\agent_id.cfg` 判斷，原廠文件未明載重複執行 `activate` 的行為。
- **既有安裝的定位**：讀取 `HKLM\SOFTWARE\Illumio` 的 `InstallPath` 與 `DataPath`。此機碼為現場觀察，原廠文件未記載。
- **未實機驗證的部分**：
  - Windows Server 2012 R2 與 2016 沒有測試機。沒有 `curl.exe` 的下載路徑只在 Server 2022 上以模擬方式（把 `curl.exe` 的路徑改成不存在）驗證過。
  - 結束碼 3010：測試中安裝程式從未回報需要重新開機，這條路徑沒有實際走過。
  - 憑證「成功匯入」：測試機的 CA 已由群組原則派發，實測到的只有「已存在而跳過」與「無效憑證而失敗」兩種結果。
  - 受限語言模式：以設定工作階段的語言模式模擬，不是由 WDAC 或 AppLocker 強制的環境。
  - VEN 23.5 以前：沒有舊版 VEN 的測試機。只驗證過以相同方式呼叫 VEN 26.2 內附的 `illumio-ven-ctl.ps1`（`status` 與 `activate`）參數與結束碼正確。
- **重複啟用**：在 Windows 上對已配對的 VEN 再執行 `activate`，VEN 26.2 會回報「already installed, and is currently paired」並以結束碼 0 結束（現場實測）。腳本仍會先判斷並跳過。
- **內容改寫**（2026-11-24）：本文取代原 SOP 與 `windows/` 下兩份 README 的重複內容。原 SOP 內嵌的 lab CA 憑證已移除，改為佔位符。
