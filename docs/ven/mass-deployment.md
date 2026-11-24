# Illumio VEN — 大規模派送

> **適用版本**：Illumio PCE 25.x / 26.x，VEN 25.x / 26.x  
> **最後更新**：2026-11-24

## 1. 目的與適用情境

用軟體派送工具（SCCM、Intune、群組原則、Ansible 等）把 VEN 裝到大量主機。本文說明部署腳本為派送設計的特性、各工具的接法，以及在管制較嚴的環境要注意的事。單機的安裝步驟見 [Linux 安裝](./install-linux.md) 與 [Windows 安裝](./install-windows.md)。

## 2. 前置條件

- 已在少量主機上手動驗證過安裝流程。
- 已建立派送專用的 Pairing Profile，並決定初始的 Enforcement 模式。大量派送建議先用 Idle 或 Visibility Only。
- 已決定憑證與安裝檔的來源（見 §3 的兩個決策）。
- 派送工具以 root（Linux）或 SYSTEM（Windows）執行。

## 3. 操作步驟

### 腳本為派送提供的特性

| 特性 | 說明 |
|---|---|
| 不需互動 | 沒有任何提示；所有設定由參數、環境變數或檔案開頭的設定區提供 |
| 可重複執行 | 憑證已存在、VEN 已安裝、已啟用時各自跳過，重跑的結束碼是 0 |
| 先檢查再安裝 | 參數、權限、憑證、PCE 連線都通過才安裝，不會留下裝了卻啟用不了的主機 |
| 固定結束碼 | 各平台一致，見下表 |
| 固定日誌位置 | Linux：`/var/log/illumio-deploy.log`；Windows：`%TEMP%\IllumioDeploy.log`（SYSTEM 為 `C:\Windows\Temp`） |
| 只用內建工具 | Linux：bash、coreutils、rpm/dpkg、curl。Windows：PowerShell 5.1 內建 cmdlet 或純 cmd，加上 certutil、whoami、icacls、reg、curl.exe |
| 不連外部網路 | 除了 PCE 以外不連任何位址 |
| 不自行安裝套件 | 缺少相依套件時只列出缺件與建議的安裝指令，以結束碼 5 中止。官方 `pair.sh` 則會自動安裝，見 [Linux 安裝 §做法 B](./install-linux.md#做法-b官方配對指令) |
| 啟用碼不落地 | 不寫入日誌 |

### 結束碼

| 結束碼 | 意義 | 派送工具建議的判定 |
|---|---|---|
| 0 | 成功，包含已安裝、已啟用而跳過 | 成功 |
| 3010 | 成功，但需要重新開機（僅 Windows） | 成功，待重新開機 |
| 1 | 未預期的錯誤 | 失敗 |
| 2 | 參數錯誤 | 失敗，修正派送設定 |
| 3 | 權限不足 | 失敗，修正執行身分 |
| 4 | 不支援的作業系統（僅 Linux） | 失敗，排除該主機 |
| 5 | 相依套件缺失（僅 Linux） | 失敗，先派送相依套件 |
| 6 | 憑證無效或匯入失敗 | 失敗 |
| 7 | 無法連線或無法驗證 PCE | 失敗，可重試 |
| 8 | 找不到安裝檔、下載失敗或安裝失敗 | 失敗 |
| 9 | 啟用失敗 | 失敗，確認啟用碼 |

### 決策一：CA 憑證怎麼給

| 做法 | 適用情境 |
|---|---|
| 不給 | PCE 使用公開 CA 的憑證，或 SaaS |
| 由既有機制派發 | 網域環境用群組原則；Linux 用組態管理工具。腳本偵測到已信任就不再處理 |
| 跟腳本一起派送 | 把 `illumio-ca.crt` 放在腳本同目錄，或用 `--cert-file` / `-CertFile` 指定 |
| 內嵌在腳本裡 | 只能派送單一檔案時。把腳本中的佔位符換成憑證內容 |

### 決策二：安裝檔怎麼給

| 做法 | 適用情境 | 注意事項 |
|---|---|---|
| 由腳本向 PCE 下載 | 主機種類多，不想自己對應版本 | PCE 的 VEN Library 要有對應的安裝檔；每台主機各自下載 |
| 跟腳本一起派送 | 頻寬有限，或要鎖定特定版本 | 套件目錄裡只能有一個 `*illumio-ven*` 安裝檔，否則用參數指定；加上 `--no-download` / `-NoDownload` 可確保只用派送的版本 |

### 啟用碼的管理

- 為這次派送產生專用的 Pairing Key，設定有效期限與使用次數上限，派送完成後撤銷。
- 優先用環境變數（`ILLUMIO_ACTIVATION_CODE`）傳入，避免啟用碼出現在派送工具的命令列紀錄。
- 啟用碼在啟用的瞬間仍會出現在 `illumio-ven-ctl` 的命令列，這是 VEN 本身的介面，官方配對腳本也是如此。
- 不要把啟用碼寫進版本控制的檔案。

### SCCM / MECM

建立「應用程式」或「套件」，內容包含腳本與（選用的）`illumio-ca.crt`、安裝檔。

```cmd
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File Deploy-Illumio.ps1 -ManagementServer <PCE_FQDN>:<PORT> -ActivationCode <ACTIVATION_CODE>
```

- 回傳碼：0 設為成功，3010 設為軟性重新開機。
- 偵測規則：登錄機碼 `HKLM\SOFTWARE\Illumio` 存在，或檔案 `%ProgramFiles%\Illumio\illumio-ven-ctl.exe` 存在。使用自訂目錄時用登錄機碼。
- 安裝行為選「為系統安裝」。

### Intune

封裝成 Win32 應用程式（`.intunewin`），安裝命令同上。回傳碼與偵測規則同 SCCM。

不需要匯入憑證時，也可以不用腳本，直接派送原廠安裝程式並在安裝時啟用：

```cmd
illumio-ven-<VERSION>.win.x64.exe /install /quiet /norestart /log C:\Windows\Temp\IllumioVENInstall.log MANAGEMENT_SERVER=<PCE_FQDN>:<PORT> ACTIVATION_CODE=<ACTIVATION_CODE>
```

### 群組原則

- 憑證：用 **電腦設定 > 原則 > Windows 設定 > 安全性設定 > 公開金鑰原則 > 受信任的根憑證授權單位** 派發。
- 安裝：用「電腦 > 啟動指令碼」執行 `deploy-illumio.bat` 或 `Deploy-Illumio.ps1`。啟動指令碼每次開機都會執行，腳本可重複執行的特性讓這種用法安全。

### Ansible 與其他 Linux 工具

```yaml
- name: Deploy Illumio VEN
  ansible.builtin.script: deploy-illumio.sh --management-server {{ pce_host }}:{{ pce_port }}
  environment:
    ILLUMIO_ACTIVATION_CODE: "{{ illumio_activation_code }}"
  become: true
  register: ven_deploy
  failed_when: ven_deploy.rc != 0
  no_log: true
```

- 啟用碼放在 Ansible Vault 或同等的機密管理機制。
- 結束碼 5 時，先用套件模組安裝日誌列出的相依套件再重跑。
- 其他工具（Satellite、Puppet、Chef、自製 SSH 迴圈）同理：把腳本送到主機，以 root 執行，依結束碼判定。

### 嚴格環境的注意事項

| 管制措施 | 影響與做法 |
|---|---|
| PowerShell 執行原則由群組原則強制為 AllSigned | `-ExecutionPolicy Bypass` 無效。以組織的程式碼簽署憑證簽署 `.ps1` 後派送；腳本存成 UTF-8（含 BOM），簽署後不可再修改 |
| 受限語言模式（WDAC、AppLocker 指令碼規則） | `Deploy-Illumio.ps1` 與 `Import-RootCA.ps1` 可在受限語言模式執行。唯一的例外：沒有 `curl.exe` 的舊版 Windows 無法在此模式下自動下載安裝檔，需自備 |
| PowerShell 被封鎖 | 改用 `deploy-illumio.bat`，它不呼叫 PowerShell |
| AppLocker 可執行檔規則 | 需允許 Illumio 的安裝程式與安裝後的程式（依發行者規則） |
| SELinux Enforcing | 預設目錄不受影響。自訂目錄需要調整標籤，腳本會處理，見 [Linux 安裝 §自訂安裝目錄](./install-linux.md#自訂安裝目錄) |
| `/tmp` 掛載為 noexec | 以 `bash deploy-illumio.sh` 執行不受影響。下載的安裝包放在 `mktemp -d` 建立的目錄，只有 root 可存取 |
| 對外連線需經 Proxy | Linux 的 `curl` 會讀取 `https_proxy` 環境變數。VEN 本身的 Proxy 設定見 [Proxy 與 Pairing Profile](./proxy-pairprofile.md) |
| TLS 攔截 | VEN 到 PCE 的流量必須排除在攔截之外，否則憑證鏈驗證會失敗 |
| 防毒與 EDR | 依原廠建議把 VEN 的安裝與資料目錄加入排除清單 |

## 4. 驗證

- 派送工具的回報：結束碼 0 或 3010 的主機數等於目標主機數。
- PCE Web Console 的 Workloads 清單：主機數量相符，狀態為 Online，Enforcement 模式與 Pairing Profile 一致。
- 抽查主機上的 `illumio-ven-ctl status`。

## 5. 失敗回滾 / 救援

- 依結束碼分類處理（見 §3 的表），多數情況修正後重新派送即可，腳本會從中斷的地方接續。
- 取回失敗主機上的日誌檔判斷原因。
- 要整批退回時，從 PCE Web Console 選取 workload 後 Unpair，或在主機上執行 `illumio-ven-ctl unpair saved`。
- 派送完成後撤銷這次使用的 Pairing Key。

## 6. 原廠文件參照

- [NotebookLM] Install, Configure, and Upgrade Guide 25.2 / 26.1 §Windows: Install and Upgrade with CLI and VEN CTL — 安裝程式的 `MANAGEMENT_SERVER`、`ACTIVATION_CODE` 屬性與 Intune 派送範例
- [NotebookLM] Install, Configure, and Upgrade Guide 25.2 / 26.1 §Linux: Install and Upgrade with CLI and VEN CTL
- [現場] 2026-11-24 於 Windows Server 2022、CentOS Stream 8、Ubuntu 24.04 對 lab PCE 實機驗證腳本的結束碼與重複執行行為

## 7. 與原廠差異（若有）

- 結束碼、可重複執行、安裝前檢查是本專案腳本的設計，原廠安裝程式與配對腳本沒有對應的行為。
- SCCM、群組原則、Ansible 的接法是依各工具的一般用法撰寫，原廠文件只提供 Intune 的範例。這三種工具的派送流程本身沒有在 lab 實測，實測的是腳本以非互動方式執行的行為。
