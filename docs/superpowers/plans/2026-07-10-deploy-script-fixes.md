# Illumio 部署腳本 Code Review 修正計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正 2026-07-10 code review 找到的全部問題：3 個確定邏輯錯誤（bat Thumbprint 計算、bat `call :Log.`、DataDir 靜默忽略）、5 個中等問題（fail-fast、佔位符憑證、3010、-CertFile fallback、冪等性）、4 個低度問題，以及後續發現的檔案編碼/換行問題。

**Architecture:** 全部為既有腳本的外科手術式修改，不新增檔案（除 `.gitattributes`）、不重構未壞的部分。bash 腳本可在本機驗證；PowerShell 與 batch 無法在本機執行（無 pwsh/wine），改以精確的靜態斷言驗證，並在計劃末尾附 Windows 實機驗證清單。

**Tech Stack:** bash、Windows PowerShell（需相容 3.0+）、cmd batch、git。

## Global Constraints

- 所有使用者可見訊息一律繁體中文，任何輸出（含 commit message）不得使用 emoji。
- 維持既有設計原則：缺套件不自動安裝、缺件清單附安裝指令、憑證防重複匯入。
- 外科手術式修改：只修本計劃列出的問題，不動相鄰程式碼、不改既有排版風格。
- 每次修改 `.sh` 後必須執行 `bash -n <file>` 且通過（本機無 shellcheck，不要嘗試安裝）。
- PowerShell 語法需相容 Windows PowerShell 3.0+：**禁用** `#Requires -RunAsAdministrator`（PS 4.0 才支援），權限檢查用 runtime 判斷。
- batch 檔內若需輸出 ASCII 括號 `(` `)`，在 `call :Log` 訊息中必須以 `^(` `^)` 跳脫；全形（）不需跳脫。
- Commit 訊息採 Conventional Commits（同 repo 歷史，如 `fix:`、`feat(docs):`），主旨用英文；每個 Task 一個 commit，並附上 harness 規定的 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` 與 `Claude-Session` trailer。
- Task 1–10 期間**不得**改變檔案換行格式與編碼（Task 11 才統一處理，避免 grep 斷言與編輯 anchor 失效）。
- 工作目錄：`/home/harry/rd/illumio-deploy`，目前在 `main` 分支且工作樹乾淨。開工前先建立分支 `git checkout -b fix/deploy-script-review`。

## 背景：review 發現對照表

| # | 嚴重度 | 問題 | 對應 Task |
|---|--------|------|-----------|
| 1 | 高 | bat 用 `certutil -hashfile`（PEM 檔案雜湊）當 Thumbprint，防重複永遠不生效 | Task 2 |
| 2 | 高 | bat `call :Log.` 找不到標籤，腳本會中止 | Task 1 |
| 3 | 高 | ps1/bat 只自訂 DataDir 時被靜默忽略 | Task 4 |
| 4 | 中 | 三支部署腳本安裝完才驗證必填參數 | Task 3 |
| 5 | 中 | Linux 兩支腳本把 PLACEHOLDER 假憑證寫入信任區並回報成功 | Task 8 |
| 6 | 中 | ps1/bat 把安裝器 exit code 3010（需重開機）當失敗 | Task 5 |
| 7 | 中 | Import-RootCA.ps1 的 -CertFile 不存在時 fallback 到內嵌憑證 | Task 7 |
| 8 | 中 | ps1/bat 缺「VEN 已安裝」檢查（Linux 版有） | Task 6 |
| 9 | 低 | deploy-illumio.sh 的 `A && B || C` 模式與絕對路徑前綴問題 | Task 9 |
| 10 | 低 | Import-RootCA.ps1 以英文字串比對 Access denied，中文 Windows 不命中 | Task 7 |
| 11 | 低 | 「請確保留在」錯字 | Task 9 |
| 12 | 低 | check-sop-template.sh 在 docs 目錄不存在時誤報 OK | Task 10 |
| 13 | 新發現 | bat 為 LF 換行 + UTF-8 無 BOM；ps1 無 BOM（cmd/PS 5.1 中文亂碼、LF batch 標籤解析風險） | Task 11 |

**明確不處理的項目**（review 中提及但決定不改，執行者不要順手修）：

- 自動偵測抓「第一個 .exe」可能抓錯：README 已記載此行為，且腳本會印出偵測到的檔名。
- `%TEMP%\illumio-ca.crt` 固定檔名的並發衝突：部署情境為單工執行。
- Activation code 出現在 process list：Illumio 官方 pair 腳本亦同，屬可接受風險（SOP 層面建議配對碼設定使用上限，非程式碼問題）。
- `prepare-and-pair.sh` 缺件時仍 exit 0：該腳本設計即為「僅報告」。
- Import-RootCA.ps1 catch 內的 `*Access is denied*` 字串比對：Task 7 的前置權限檢查已涵蓋，該行成為無害殘留，保留不動。

---

### Task 0: 建立工作分支

**Files:** 無（git 操作）

- [ ] **Step 1: 確認工作樹乾淨並建立分支**

```bash
cd /home/harry/rd/illumio-deploy
git status --short          # 預期：無輸出（docs/superpowers/plans/ 下的本計劃檔除外，先一併 commit）
git add docs/superpowers/plans/2026-07-10-deploy-script-fixes.md
git commit -m "docs(plan): add deploy script review fix plan"
git checkout -b fix/deploy-script-review
```

預期：`Switched to a new branch 'fix/deploy-script-review'`

---

### Task 1: deploy-illumio.bat — 修復 `call :Log.` 空行呼叫（阻斷性錯誤）

cmd 的標籤解析中 `.` 不是標籤分隔字元，`call :Log.` 會尋找不存在的 `:Log.` 標籤，導致「The system cannot find the batch label specified」且腳本中止——第 27 行就會掛，此腳本目前無法完整執行。即使部分環境能解析到 `:Log`，`echo %*` 在無參數時也會印出 "ECHO is off." 而非空行。

**Files:**
- Modify: `windows/manual_deploy/deploy-illumio.bat`（第 27、76、119、145 行的 `call :Log.`；檔尾 `:Log` 函式之後）

**Interfaces:**
- Produces: `:LogBlank` 標籤（無參數，輸出空行到螢幕與 `%LOG_FILE%`）。Task 3 會以「橫幅後的 `call :LogBlank`」作為插入 anchor。

- [ ] **Step 1: 確認目前的錯誤呼叫共 4 處**

```bash
grep -n 'call :Log\.$' windows/manual_deploy/deploy-illumio.bat
```

預期輸出（行號為原始檔）：

```
27:call :Log.
76:call :Log.
119:call :Log.
145:call :Log.
```

- [ ] **Step 2: 將 4 處 `call :Log.` 全部改為 `call :LogBlank`**

用 Edit 工具逐一替換（`old_string` 為 `call :Log.`，`replace_all` 可用，因為 4 處內容完全相同）：

```bat
call :LogBlank
```

- [ ] **Step 3: 在檔尾 `:Log` 函式之後新增 `:LogBlank` 函式**

找到檔尾這段：

```bat
:Log
echo %*
echo [%DATE% %TIME%] %* >> "%LOG_FILE%"
exit /b 0
```

在其後新增：

```bat

:LogBlank
echo.
>> "%LOG_FILE%" echo.
exit /b 0
```

- [ ] **Step 4: 驗證**

```bash
grep -c 'call :Log\.$' windows/manual_deploy/deploy-illumio.bat || echo "0 處殘留（預期）"
grep -c 'call :LogBlank' windows/manual_deploy/deploy-illumio.bat    # 預期：4
grep -c '^:LogBlank' windows/manual_deploy/deploy-illumio.bat        # 預期：1
```

- [ ] **Step 5: Commit**

```bash
git add windows/manual_deploy/deploy-illumio.bat
git commit -m "fix(bat): replace broken 'call :Log.' blank-line calls with :LogBlank"
```

---

### Task 2: deploy-illumio.bat — 修正憑證 Thumbprint 計算

`certutil -hashfile` 算的是 PEM 檔案位元組的 SHA1；憑證 Thumbprint 是 DER 編碼的 SHA1，兩者永遠不同（已用 openssl 實證），因此 `certutil -verifystore` 永遠找不到、`[SKIP]` 分支永遠走不到。改用 PowerShell 計算真正的 Thumbprint（`certutil -dump` 的輸出會被系統語系在地化、不可靠；PowerShell 屬性輸出與語系無關）。

**Files:**
- Modify: `windows/manual_deploy/deploy-illumio.bat:47-53`

**Interfaces:**
- Consumes: `%TEMP_CERT%`（既有變數，暫存憑證路徑）
- Produces: `THUMBPRINT` 變數語意不變（40 字元十六進位或未定義），下游 `if defined THUMBPRINT (...)` 區塊**不需修改**。

- [ ] **Step 1: 確認要替換的區塊**

```bash
sed -n '47,53p' windows/manual_deploy/deploy-illumio.bat
```

預期輸出：

```
REM 從內嵌憑證動態計算 SHA1 Thumbprint (適用於任何環境更換憑證)
set "THUMBPRINT="
for /f "skip=1 delims=" %%A in ('certutil -hashfile "%TEMP_CERT%" SHA1') do (
    if not defined THUMBPRINT set "THUMBPRINT=%%A"
)
REM 去除空白字元
set "THUMBPRINT=!THUMBPRINT: =!"
```

- [ ] **Step 2: 整段替換為 PowerShell 計算**

```bat
REM 憑證 Thumbprint 是 DER 編碼的 SHA1；certutil -hashfile 算的是 PEM 檔案位元組雜湊，兩者不同
REM 改用 PowerShell 計算（certutil -dump 輸出會被語系在地化，不可解析）；憑證無效時 THUMBPRINT 為空
set "THUMBPRINT="
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(New-Object System.Security.Cryptography.X509Certificates.X509Certificate2('%TEMP_CERT%')).Thumbprint" 2^>nul`) do set "THUMBPRINT=%%A"
```

注意：
- 必須用 `usebackq` + 反引號包住指令，因為 PowerShell 指令內含單引號（`'%TEMP_CERT%'`），與 for /f 預設的單引號分隔衝突。
- `2^>nul` 的 `^` 跳脫必須保留。
- 憑證無效（例如佔位符）時 PowerShell 丟例外、無輸出，`THUMBPRINT` 未定義，既有流程會直接走 `certutil -addstore` 並在該處以錯誤結束——這是正確的失敗路徑。

- [ ] **Step 3: 驗證**

```bash
grep -n 'certutil -hashfile' windows/manual_deploy/deploy-illumio.bat   # 預期：無輸出
grep -c 'usebackq' windows/manual_deploy/deploy-illumio.bat             # 預期：1
grep -n 'if defined THUMBPRINT' windows/manual_deploy/deploy-illumio.bat  # 預期：仍存在（下游未動）
```

- [ ] **Step 4: Commit**

```bash
git add windows/manual_deploy/deploy-illumio.bat
git commit -m "fix(bat): compute real certificate thumbprint (DER SHA1) instead of PEM file hash"
```

---

### Task 3: 三支部署腳本 — 必填參數 fail-fast 前移

三支腳本都在「安裝完成後」才檢查 ACTIVATION_CODE / MANAGEMENT_SERVER 是否仍為佔位符，忘記設定會留下「已安裝未啟用」的半套狀態。將檢查移到腳本開頭，並刪除原位置的重複檢查。

**Files:**
- Modify: `linux/manual_deploy/deploy-illumio.sh`（插入於 `SCRIPT_DIR=` 之後；刪除原第 170–172 行）
- Modify: `windows/manual_deploy/Deploy-Illumio.ps1`（插入於橫幅之後；刪除原第 150–152 行）
- Modify: `windows/manual_deploy/deploy-illumio.bat`（插入於橫幅之後；刪除原第 129–136 行）

**Interfaces:**
- Consumes: Task 1 產出的 `call :LogBlank`（bat 的插入 anchor 是橫幅後的那一行 `call :LogBlank`）。

- [ ] **Step 1: deploy-illumio.sh — 在 `SCRIPT_DIR=` 行之後插入**

在這一行之後：

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
```

插入：

```bash

# 必填參數 fail-fast：避免安裝完成後才發現未設定，留下已安裝未啟用的狀態
if [ "$ACTIVATION_CODE" = "<YOUR_ACTIVATION_CODE>" ] || [ "$MANAGEMENT_SERVER" = "<YOUR_PCE_FQDN:PORT>" ]; then
    print_error "請先修改腳本設定區的 ACTIVATION_CODE 和 MANAGEMENT_SERVER。"
    exit 1
fi
```

- [ ] **Step 2: deploy-illumio.sh — 刪除 Step 5 內的原檢查**

刪除這段（位於 `if [ ! -f "$VEN_CTL" ]...` 之後）：

```bash
if [ "$ACTIVATION_CODE" = "<YOUR_ACTIVATION_CODE>" ] || [ "$MANAGEMENT_SERVER" = "<YOUR_PCE_FQDN:PORT>" ]; then
    print_error "請先設定 ACTIVATION_CODE 和 MANAGEMENT_SERVER。"; exit 1
fi
```

- [ ] **Step 3: 驗證 sh**

```bash
bash -n linux/manual_deploy/deploy-illumio.sh && echo SYNTAX-OK
# fail-fast 檢查必須出現在 Step 1 之前：
awk '/請先修改腳本設定區/{p=NR} /Step 1\/5/{s=NR} END{ if (p && s && p<s) print "ORDER-OK"; else print "ORDER-FAIL" }' linux/manual_deploy/deploy-illumio.sh
grep -c '請先設定 ACTIVATION_CODE 和 MANAGEMENT_SERVER' linux/manual_deploy/deploy-illumio.sh || echo "0 處殘留（預期）"
```

預期：`SYNTAX-OK`、`ORDER-OK`、殘留 0。

- [ ] **Step 4: Deploy-Illumio.ps1 — 移動檢查**

刪除 Step 3 區塊內的：

```powershell
    if ($ActivationCode -eq "<YOUR_ACTIVATION_CODE>" -or $ManagementServer -eq "<YOUR_PCE_FQDN:PORT>") {
        Throw "請先設定 ActivationCode 和 ManagementServer 參數。"
    }
```

在這一行之後：

```powershell
    Write-Log "INFO" "資料目錄: $DataDir"
```

插入：

```powershell

    # 必填參數 fail-fast：避免安裝完成後才發現未設定
    if ($ActivationCode -eq "<YOUR_ACTIVATION_CODE>" -or $ManagementServer -eq "<YOUR_PCE_FQDN:PORT>") {
        Throw "請先設定 ActivationCode 和 ManagementServer 參數。"
    }
```

- [ ] **Step 5: deploy-illumio.bat — 移動檢查**

刪除 Step 3 區塊內的：

```bat
if "%ACTIVATION_CODE%"=="<YOUR_ACTIVATION_CODE>" (
    call :Log [ERROR] 請先設定 ACTIVATION_CODE。
    exit /b 1
)
if "%MANAGEMENT_SERVER%"=="<YOUR_PCE_FQDN:PORT>" (
    call :Log [ERROR] 請先設定 MANAGEMENT_SERVER。
    exit /b 1
)
```

在橫幅結尾的 `call :LogBlank`（原第 27 行，`REM === Step 1` 之前）之後插入：

```bat

REM 必填參數 fail-fast：避免安裝完成後才發現未設定
if "%ACTIVATION_CODE%"=="<YOUR_ACTIVATION_CODE>" (
    call :Log [ERROR] 請先設定 ACTIVATION_CODE。
    exit /b 1
)
if "%MANAGEMENT_SERVER%"=="<YOUR_PCE_FQDN:PORT>" (
    call :Log [ERROR] 請先設定 MANAGEMENT_SERVER。
    exit /b 1
)
```

- [ ] **Step 6: 驗證 ps1 與 bat（靜態斷言：檢查必須在安裝步驟之前）**

```bash
awk '/必填參數 fail-fast/{p=NR} /Step 2\/3/{if(!s) s=NR} END{ if (p && s && p<s) print "PS1-ORDER-OK"; else print "PS1-ORDER-FAIL" }' windows/manual_deploy/Deploy-Illumio.ps1
awk '/必填參數 fail-fast/{p=NR} /Step 1\/3/{if(!s) s=NR} END{ if (p && s && p<s) print "BAT-ORDER-OK"; else print "BAT-ORDER-FAIL" }' windows/manual_deploy/deploy-illumio.bat
# 各檔案佔位符檢查只剩一處：
grep -c 'YOUR_ACTIVATION_CODE>" -or' windows/manual_deploy/Deploy-Illumio.ps1   # 預期：1
grep -c '=="<YOUR_ACTIVATION_CODE>"' windows/manual_deploy/deploy-illumio.bat   # 預期：1
```

- [ ] **Step 7: Commit**

```bash
git add linux/manual_deploy/deploy-illumio.sh windows/manual_deploy/Deploy-Illumio.ps1 windows/manual_deploy/deploy-illumio.bat
git commit -m "fix: validate required parameters before installation (fail-fast)"
```

---

### Task 4: ps1 + bat — 修正只自訂 DataDir 時被靜默忽略

兩支腳本都只以「InstallDir 是否為預設值」決定要不要帶 `INSTALLFOLDER`/`DATAFOLDER`，只傳自訂 DataDir 時會被無聲丟棄，與 README 記載的獨立選填參數矛盾。改為兩個屬性各自判斷。

**Files:**
- Modify: `windows/manual_deploy/Deploy-Illumio.ps1`（原第 129–135 行）
- Modify: `windows/manual_deploy/deploy-illumio.bat`（原第 105–110 行）

- [ ] **Step 1: Deploy-Illumio.ps1 — 替換安裝參數組裝**

舊：

```powershell
    $defaultDir = "C:\Program Files\Illumio"
    $installerLog = "$env:TEMP\IllumioVENInstall.log"
    if ($InstallDir -eq $defaultDir) {
        $installArgs = @("/install", "/quiet", "/norestart", "/log", "`"$installerLog`"")
    } else {
        $installArgs = @("/install", "/quiet", "/norestart", "/log", "`"$installerLog`"", "INSTALLFOLDER=`"$InstallDir`"", "DATAFOLDER=`"$DataDir`"")
    }
```

新：

```powershell
    $installerLog = "$env:TEMP\IllumioVENInstall.log"
    $installArgs = @("/install", "/quiet", "/norestart", "/log", "`"$installerLog`"")
    # INSTALLFOLDER 與 DATAFOLDER 是獨立的安裝屬性，各自非預設值時才需要傳入
    if ($InstallDir -ne "C:\Program Files\Illumio") { $installArgs += "INSTALLFOLDER=`"$InstallDir`"" }
    if ($DataDir -ne "C:\ProgramData\Illumio") { $installArgs += "DATAFOLDER=`"$DataDir`"" }
```

- [ ] **Step 2: deploy-illumio.bat — 替換安裝呼叫**

舊：

```bat
set "VEN_INSTALL_LOG=%TEMP%\IllumioVENInstall.log"
if "%INSTALL_DIR%"=="C:\Program Files\Illumio" (
    "%INSTALLER%" /install /quiet /norestart /log "%VEN_INSTALL_LOG%" >> "%LOG_FILE%" 2>&1
) else (
    "%INSTALLER%" /install /quiet /norestart /log "%VEN_INSTALL_LOG%" INSTALLFOLDER="%INSTALL_DIR%" DATAFOLDER="%DATA_DIR%" >> "%LOG_FILE%" 2>&1
)
```

新：

```bat
set "VEN_INSTALL_LOG=%TEMP%\IllumioVENInstall.log"
REM INSTALLFOLDER 與 DATAFOLDER 是獨立的安裝屬性，各自非預設值時才需要傳入
set "EXTRA_ARGS="
if not "%INSTALL_DIR%"=="C:\Program Files\Illumio" set "EXTRA_ARGS=INSTALLFOLDER="%INSTALL_DIR%""
if not "%DATA_DIR%"=="C:\ProgramData\Illumio" set "EXTRA_ARGS=%EXTRA_ARGS% DATAFOLDER="%DATA_DIR%""
"%INSTALLER%" /install /quiet /norestart /log "%VEN_INSTALL_LOG%" %EXTRA_ARGS% >> "%LOG_FILE%" 2>&1
```

注意：`set "EXTRA_ARGS=INSTALLFOLDER="%INSTALL_DIR%""` 的引號是刻意的——cmd 的 `set "..."` 取第一個與最後一個引號之間的內容，結果值為 `INSTALLFOLDER="C:\..."`（內含引號，路徑含空格時必要）。

- [ ] **Step 3: 驗證**

```bash
grep -c 'DATAFOLDER' windows/manual_deploy/Deploy-Illumio.ps1    # 預期：1
grep -c 'defaultDir' windows/manual_deploy/Deploy-Illumio.ps1    # 預期：0（變數已移除）
grep -c 'EXTRA_ARGS' windows/manual_deploy/deploy-illumio.bat    # 預期：4（set 空值、兩個 if、一次使用）
```

- [ ] **Step 4: Commit**

```bash
git add windows/manual_deploy/Deploy-Illumio.ps1 windows/manual_deploy/deploy-illumio.bat
git commit -m "fix(windows): honor custom DataDir independently of InstallDir"
```

---

### Task 5: ps1 + bat — 安裝器 Exit Code 3010 視為成功

`/norestart` 下安裝成功但需要重開機時，安裝器常回 3010；目前被當失敗中止，啟用步驟不會執行。

**Files:**
- Modify: `windows/manual_deploy/Deploy-Illumio.ps1`（原第 138–140 行）
- Modify: `windows/manual_deploy/deploy-illumio.bat`（原第 112–116 行）

**Interfaces:**
- Produces: bat 的 `:step3` 標籤（Step 3 啟用區塊入口），Task 6 依賴它。

- [ ] **Step 1: Deploy-Illumio.ps1 — 替換結束碼判斷**

舊：

```powershell
    $proc = Start-Process -FilePath $InstallerPath -ArgumentList $installArgs -Wait -PassThru
    if ($proc.ExitCode -ne 0) { Throw "安裝失敗。Exit Code: $($proc.ExitCode)" }
    Write-Log "OK" "VEN Agent 安裝完成。"
```

新：

```powershell
    $proc = Start-Process -FilePath $InstallerPath -ArgumentList $installArgs -Wait -PassThru
    if ($proc.ExitCode -eq 3010) {
        Write-Log "OK" "VEN Agent 安裝完成 (Exit Code 3010: 需要重新開機)。"
    } elseif ($proc.ExitCode -ne 0) {
        Throw "安裝失敗。Exit Code: $($proc.ExitCode)"
    } else {
        Write-Log "OK" "VEN Agent 安裝完成。"
    }
```

- [ ] **Step 2: deploy-illumio.bat — 替換結束碼判斷並新增 `:step3` 標籤**

舊（緊接在安裝呼叫之後、`REM === Step 3: 啟用 ===` 之前）：

```bat
if %errorlevel% neq 0 (
    call :Log [ERROR] 安裝失敗。Exit Code: %errorlevel%. 詳見日誌: %LOG_FILE%
    exit /b %errorlevel%
)
call :Log [OK]     VEN Agent 安裝完成。
```

新：

```bat
if %errorlevel% equ 3010 (
    call :Log [OK]     VEN Agent 安裝完成 ^(Exit Code 3010: 需要重新開機^)。
    goto :step3
)
if %errorlevel% neq 0 (
    call :Log [ERROR] 安裝失敗。Exit Code: %errorlevel%. 詳見日誌: %LOG_FILE%
    exit /b %errorlevel%
)
call :Log [OK]     VEN Agent 安裝完成。

:step3
```

（`:step3` 之後緊接既有的 `REM === Step 3: 啟用 ===`。）

- [ ] **Step 3: 驗證**

```bash
grep -c '3010' windows/manual_deploy/Deploy-Illumio.ps1     # 預期：2（判斷 + 訊息）
grep -c '^:step3' windows/manual_deploy/deploy-illumio.bat  # 預期：1
grep -c 'goto :step3' windows/manual_deploy/deploy-illumio.bat  # 預期：1（Task 6 完成後會變 2）
```

- [ ] **Step 4: Commit**

```bash
git add windows/manual_deploy/Deploy-Illumio.ps1 windows/manual_deploy/deploy-illumio.bat
git commit -m "fix(windows): treat installer exit code 3010 (reboot required) as success"
```

---

### Task 6: ps1 + bat — VEN 已安裝時跳過安裝步驟（冪等性，與 Linux 版一致）

**Files:**
- Modify: `windows/manual_deploy/Deploy-Illumio.ps1`（Step 2 區塊）
- Modify: `windows/manual_deploy/deploy-illumio.bat`（Step 2 區塊開頭）

**Interfaces:**
- Consumes: Task 5 產出的 bat `:step3` 標籤。**必須在 Task 5 之後執行。**
- 判斷依據：`illumio-ven-ctl.exe` 是否存在於 `$InstallDir` 或預設安裝目錄（與 Step 3 定位 ctl 的邏輯相同）。

- [ ] **Step 1: Deploy-Illumio.ps1 — 以 if/else 包住安裝區塊**

在這一行之後：

```powershell
    Write-Log "INFO" "[Step 2/3] 安裝 Illumio VEN Agent..."
```

插入：

```powershell

    # 冪等性：VEN 已安裝時跳過安裝步驟（與 Linux 版行為一致）
    $preCtl = Join-Path $InstallDir "illumio-ven-ctl.exe"
    if (-not (Test-Path $preCtl)) { $preCtl = "C:\Program Files\Illumio\illumio-ven-ctl.exe" }
    if (Test-Path $preCtl) {
        Write-Log "SKIP" "偵測到 VEN 已安裝 ($preCtl)，跳過安裝步驟。"
    } else {
```

然後在 Task 5 改寫後的結束碼判斷區塊之後（即 `        Write-Log "OK" "VEN Agent 安裝完成。"` 所在的 `}` 之後、`    # === Step 3: 啟用 ===` 之前）補上結尾大括號：

```powershell
    }
```

PowerShell 不依賴縮排，**不要**為了美觀重新縮排 else 內的既有程式碼（維持最小 diff）。完成後 Step 2 的結構為：

```powershell
    if (Test-Path $preCtl) {
        Write-Log "SKIP" "偵測到 VEN 已安裝 ($preCtl)，跳過安裝步驟。"
    } else {
    if (-not [string]::IsNullOrEmpty($SourceDir)) {
    ...（既有安裝程式碼，縮排不變）...
    if ($proc.ExitCode -eq 3010) {
        Write-Log "OK" "VEN Agent 安裝完成 (Exit Code 3010: 需要重新開機)。"
    } elseif ($proc.ExitCode -ne 0) {
        Throw "安裝失敗。Exit Code: $($proc.ExitCode)"
    } else {
        Write-Log "OK" "VEN Agent 安裝完成。"
    }
    }
```

- [ ] **Step 2: deploy-illumio.bat — 在 Step 2 開頭插入檢查**

在這一行之後（Step 2 橫幅）：

```bat
call :Log [Step 2/3] 安裝 Illumio VEN Agent...
```

插入：

```bat

REM 冪等性：VEN 已安裝時跳過安裝步驟（與 Linux 版行為一致）
set "VEN_INSTALLED="
if exist "%INSTALL_DIR%\illumio-ven-ctl.exe" set "VEN_INSTALLED=1"
if exist "C:\Program Files\Illumio\illumio-ven-ctl.exe" set "VEN_INSTALLED=1"
if defined VEN_INSTALLED (
    call :Log [SKIP]   偵測到 VEN 已安裝，跳過安裝步驟。
    goto :step3
)
```

- [ ] **Step 3: 驗證（大括號平衡與標籤引用）**

```bash
# ps1 大括號必須平衡：
awk '{ for(i=1;i<=length($0);i++){ c=substr($0,i,1); if(c=="{")o++; if(c=="}")o-- } } END{ print (o==0 ? "BRACES-OK" : "BRACES-FAIL " o) }' windows/manual_deploy/Deploy-Illumio.ps1
grep -c 'goto :step3' windows/manual_deploy/deploy-illumio.bat   # 預期：2
grep -c '^:step3' windows/manual_deploy/deploy-illumio.bat       # 預期：1
```

（awk 括號計數是粗略檢查——本檔字串內無單獨大括號，足夠用。）

- [ ] **Step 4: Commit**

```bash
git add windows/manual_deploy/Deploy-Illumio.ps1 windows/manual_deploy/deploy-illumio.bat
git commit -m "feat(windows): skip VEN installation when already installed"
```

---

### Task 7: 兩支 ps1 — 憑證處理強化

三項修正：(a) `-CertFile` 指定但不存在時改為直接失敗（原本 fallback 到內嵌憑證，路徑打錯會裝到錯的憑證）；(b) 前置管理員權限檢查（原本靠 catch 內比對英文 "Access is denied"，中文 Windows 不命中）；(c) 佔位符憑證偵測（原本 X509Certificate2 建構失敗的訊息難懂）。

**Files:**
- Modify: `windows/pairing_prereq/Import-RootCA.ps1`
- Modify: `windows/manual_deploy/Deploy-Illumio.ps1`

**Interfaces:**
- 權限檢查用 `WindowsPrincipal.IsInRole`（PS 2.0+ 可用）；**不得**使用 `#Requires -RunAsAdministrator`（PS 4.0 才支援）。

- [ ] **Step 1: Import-RootCA.ps1 — 在 `try {` 之後插入權限檢查**

```powershell
    # 前置權限檢查：catch 內的英文錯誤字串比對在非英文 Windows 不可靠
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Throw "此腳本需要以系統管理員身分執行 PowerShell。"
    }

```

- [ ] **Step 2: Import-RootCA.ps1 — 替換憑證來源選擇區塊**

舊：

```powershell
    $localCertPath = Join-Path $PSScriptRoot "illumio-ca.crt"
    if ($CertFile -ne "" -and (Test-Path $CertFile)) {
        Write-Output "[INFO] 使用外部憑證檔案 (-CertFile): $CertFile"
        $certContent = Get-Content -Path $CertFile -Raw
    } elseif ($CertFile -eq "" -and (Test-Path $localCertPath)) {
        Write-Output "[INFO] 使用同目錄憑證檔案: $localCertPath"
        $certContent = Get-Content -Path $localCertPath -Raw
    } else {
        if ($CertFile -ne "") {
            Write-Warning "指定的憑證檔案不存在: $CertFile，改用內嵌憑證。"
        }
        Write-Output "[INFO] 使用內嵌憑證。"
        $certContent = $EmbeddedCertContent
    }
```

新：

```powershell
    $localCertPath = Join-Path $PSScriptRoot "illumio-ca.crt"
    if ($CertFile -ne "") {
        if (-not (Test-Path $CertFile)) {
            Throw "指定的憑證檔案不存在: $CertFile"
        }
        Write-Output "[INFO] 使用外部憑證檔案 (-CertFile): $CertFile"
        $certContent = Get-Content -Path $CertFile -Raw
    } elseif (Test-Path $localCertPath) {
        Write-Output "[INFO] 使用同目錄憑證檔案: $localCertPath"
        $certContent = Get-Content -Path $localCertPath -Raw
    } else {
        Write-Output "[INFO] 使用內嵌憑證。"
        $certContent = $EmbeddedCertContent
    }

    if ($certContent -like "*PLACEHOLDER_CERTIFICATE_CONTENT*") {
        Throw "內嵌憑證仍為佔位符。請以 -CertFile 指定憑證、放置同目錄 illumio-ca.crt，或替換腳本內嵌憑證。"
    }
```

（catch 內既有的 `*Access is denied*` 提示保留不動——前置檢查已涵蓋，該行成為無害殘留。）

- [ ] **Step 3: Deploy-Illumio.ps1 — 在 `try {` 之後插入相同的權限檢查**

```powershell
    # 前置權限檢查：憑證匯入與安裝皆需管理員權限
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Throw "此腳本需要以系統管理員身分執行 PowerShell。"
    }

```

- [ ] **Step 4: Deploy-Illumio.ps1 — 佔位符偵測**

在 Step 1 區塊中，這段之後：

```powershell
    $localCertPath = Join-Path $PSScriptRoot "illumio-ca.crt"
    if (Test-Path $localCertPath) {
        Write-Log "INFO" "使用同目錄憑證檔案: $localCertPath"
        $EmbeddedCertContent = Get-Content -Path $localCertPath -Raw
    }
```

插入：

```powershell

    if ($EmbeddedCertContent -like "*PLACEHOLDER_CERTIFICATE_CONTENT*") {
        Throw "內嵌憑證仍為佔位符。請放置同目錄 illumio-ca.crt 或替換腳本內嵌憑證。"
    }
```

- [ ] **Step 5: 驗證**

```bash
grep -c 'IsInRole' windows/pairing_prereq/Import-RootCA.ps1 windows/manual_deploy/Deploy-Illumio.ps1
# 預期各 1
grep -c '改用內嵌憑證' windows/pairing_prereq/Import-RootCA.ps1 || echo "0 處殘留（預期）"
grep -c 'PLACEHOLDER_CERTIFICATE_CONTENT\*' windows/pairing_prereq/Import-RootCA.ps1   # 預期：1
grep -c 'PLACEHOLDER_CERTIFICATE_CONTENT\*' windows/manual_deploy/Deploy-Illumio.ps1   # 預期：1
awk '{ for(i=1;i<=length($0);i++){ c=substr($0,i,1); if(c=="{")o++; if(c=="}")o-- } } END{ print (o==0 ? "BRACES-OK" : "BRACES-FAIL " o) }' windows/pairing_prereq/Import-RootCA.ps1
```

- [ ] **Step 6: Commit**

```bash
git add windows/pairing_prereq/Import-RootCA.ps1 windows/manual_deploy/Deploy-Illumio.ps1
git commit -m "fix(ps1): admin precheck, fail on missing -CertFile, detect placeholder certificate"
```

---

### Task 8: Linux 兩支腳本 — 佔位符與 PEM 格式防呆

Linux 版是唯一會把 PLACEHOLDER 假憑證「靜默寫入系統信任區並回報成功」的平台（ps1 會在 X509Certificate2 建構時丟例外、bat 的 certutil 會失敗）。在 CERT_CONTENT 決定之後、寫入之前加入兩道檢查。

**Files:**
- Modify: `linux/pairing_prereq/prepare-and-pair.sh`（CERT_CONTENT 選擇區塊之後）
- Modify: `linux/manual_deploy/deploy-illumio.sh`（CERT_CONTENT 選擇區塊之後）

- [ ] **Step 1: 先寫驗證用測試腳本並確認「目前邏輯會放行佔位符」**

```bash
SCRATCH=/tmp/claude-1000/-home-harry-rd-illumio-deploy/8b02703b-9012-42d3-9a5b-b588cfc20622/scratchpad
mkdir -p "$SCRATCH"
# 產生一張真憑證供正向測試
openssl req -x509 -newkey rsa:2048 -keyout "$SCRATCH/k.pem" -out "$SCRATCH/test-ca.crt" -days 1 -nodes -subj "/CN=test" 2>/dev/null

cat > "$SCRATCH/test-cert-guard.sh" <<'EOF'
#!/bin/bash
# 模擬插入腳本的防呆邏輯；$1=憑證檔路徑
CERT_CONTENT="$(cat "$1")"
if [[ "$CERT_CONTENT" == *PLACEHOLDER_CERTIFICATE_CONTENT* ]]; then
    echo "REJECT-PLACEHOLDER"; exit 1
fi
if command -v openssl &>/dev/null && ! echo "$CERT_CONTENT" | openssl x509 -noout 2>/dev/null; then
    echo "REJECT-INVALID"; exit 1
fi
echo "ACCEPT"
EOF

printf -- '-----BEGIN CERTIFICATE-----\nPLACEHOLDER_CERTIFICATE_CONTENT_REPLACE_WITH_YOUR_ACTUAL_CERTIFICATE\n-----END CERTIFICATE-----\n' > "$SCRATCH/placeholder.crt"
printf 'garbage not a cert\n' > "$SCRATCH/garbage.crt"

bash "$SCRATCH/test-cert-guard.sh" "$SCRATCH/placeholder.crt"   # 預期：REJECT-PLACEHOLDER，exit 1
bash "$SCRATCH/test-cert-guard.sh" "$SCRATCH/garbage.crt"       # 預期：REJECT-INVALID，exit 1
bash "$SCRATCH/test-cert-guard.sh" "$SCRATCH/test-ca.crt"       # 預期：ACCEPT，exit 0
```

三個案例都符合預期後才進行下一步（這一步驗證的是「將要插入的邏輯」本身正確）。

- [ ] **Step 2: prepare-and-pair.sh — 插入防呆**

在憑證來源選擇區塊之後（即這段的 `fi` 之後）：

```bash
if [ -f "$SCRIPT_DIR/illumio-ca.crt" ]; then
    print_info "使用外部憑證: $SCRIPT_DIR/illumio-ca.crt"
    CERT_CONTENT=$(cat "$SCRIPT_DIR/illumio-ca.crt")
else
    print_info "使用腳本內嵌憑證"
fi
```

插入：

```bash

# 佔位符與格式防呆：避免把無效內容寫入系統信任區後仍回報成功
if [[ "$CERT_CONTENT" == *PLACEHOLDER_CERTIFICATE_CONTENT* ]]; then
    echo -e "${RED}[ERROR] 內嵌憑證仍為佔位符，且 $SCRIPT_DIR/illumio-ca.crt 不存在。${NC}"
    echo -e "${RED}        請將實際 CA 憑證命名為 illumio-ca.crt 放在腳本同目錄，或替換腳本內嵌憑證。${NC}"
    exit 1
fi
if command -v openssl &>/dev/null && ! echo "$CERT_CONTENT" | openssl x509 -noout 2>/dev/null; then
    echo -e "${RED}[ERROR] 憑證內容不是有效的 PEM 憑證。${NC}"
    exit 1
fi
```

（此腳本沒有 `print_error` 函式，用 `echo -e "${RED}...${NC}"`，與檔內既有錯誤輸出風格一致。openssl 檢查設計為「有 openssl 才檢查」——它不在必要套件清單內。）

- [ ] **Step 3: deploy-illumio.sh — 插入相同防呆（改用 print_error）**

在對應的憑證來源選擇區塊 `fi` 之後插入：

```bash

# 佔位符與格式防呆：避免把無效內容寫入系統信任區後仍回報成功
if [[ "$CERT_CONTENT" == *PLACEHOLDER_CERTIFICATE_CONTENT* ]]; then
    print_error "內嵌憑證仍為佔位符，且 $SCRIPT_DIR/illumio-ca.crt 不存在。"
    print_error "請將實際 CA 憑證命名為 illumio-ca.crt 放在腳本同目錄，或替換腳本內嵌憑證。"
    exit 1
fi
if command -v openssl &>/dev/null && ! echo "$CERT_CONTENT" | openssl x509 -noout 2>/dev/null; then
    print_error "憑證內容不是有效的 PEM 憑證。"
    exit 1
fi
```

- [ ] **Step 4: 驗證**

```bash
bash -n linux/pairing_prereq/prepare-and-pair.sh && bash -n linux/manual_deploy/deploy-illumio.sh && echo SYNTAX-OK
# 防呆必須位於「寫入信任區」之前：
awk '/佔位符與格式防呆/{g=NR} /mkdir -p "\$CERT_DIR"/{if(!w) w=NR} END{ if (g && w && g<w) print "ORDER-OK"; else print "ORDER-FAIL" }' linux/pairing_prereq/prepare-and-pair.sh
awk '/佔位符與格式防呆/{g=NR} /mkdir -p "\$CERT_DIR"/{if(!w) w=NR} END{ if (g && w && g<w) print "ORDER-OK"; else print "ORDER-FAIL" }' linux/manual_deploy/deploy-illumio.sh
```

預期：`SYNTAX-OK` 與兩個 `ORDER-OK`。

- [ ] **Step 5: Commit**

```bash
git add linux/pairing_prereq/prepare-and-pair.sh linux/manual_deploy/deploy-illumio.sh
git commit -m "fix(linux): abort certificate import on placeholder or invalid PEM content"
```

---

### Task 9: deploy-illumio.sh — 安裝包偵測改寫 + 設定註解 + 錯字

三項：(a) 把脆弱的 `A && B || C` 單行模式改為明確 if/else；(b) 設定區註解說明 `VEN_RPM_FILE`/`VEN_DEB_FILE` 只能填檔名（目前填絕對路徑會被前綴成 `$TARGET_DIR//abs/path`）；(c) 修正「請確保留在」錯字為「請確保放在」。

**Files:**
- Modify: `linux/manual_deploy/deploy-illumio.sh`（設定區第 27–29 行；Step 4 的 else 分支）

- [ ] **Step 1: 更新設定區註解**

舊：

```bash
SOURCE_DIR=""      # 留空=自動尋找腳本所在目錄，可指定絕對路徑例如 "/tmp/installers"
VEN_RPM_FILE=""    # 留空=自動偵測 SOURCE_DIR 內的 .rpm
VEN_DEB_FILE=""    # 留空=自動偵測 SOURCE_DIR 內的 .deb
```

新：

```bash
SOURCE_DIR=""      # 留空=自動尋找腳本所在目錄，可指定絕對路徑例如 "/tmp/installers"
VEN_RPM_FILE=""    # 留空=自動偵測 SOURCE_DIR 內的 .rpm；指定時請填檔名（相對於 SOURCE_DIR），勿填絕對路徑
VEN_DEB_FILE=""    # 留空=自動偵測 SOURCE_DIR 內的 .deb；指定時請填檔名（相對於 SOURCE_DIR），勿填絕對路徑
```

- [ ] **Step 2: 改寫 Step 4 的安裝包偵測（else 分支整段替換）**

舊（`if [ "$VEN_ALREADY_INSTALLED" = true ]` 的 else 分支內容）：

```bash
    [ -z "$SOURCE_DIR" ] && TARGET_DIR="$SCRIPT_DIR" || TARGET_DIR="$SOURCE_DIR"

    case "$OS_TYPE" in
        rhel|centos|rocky|almalinux|ol)
            [ -z "$VEN_RPM_FILE" ] && VEN_RPM_FILE=$(ls "$TARGET_DIR"/*.rpm 2>/dev/null | head -1) || VEN_RPM_FILE="$TARGET_DIR/$VEN_RPM_FILE"
            if [ -z "$VEN_RPM_FILE" ] || [ ! -f "$VEN_RPM_FILE" ]; then
                print_error "找不到 VEN RPM 安裝包。請確保留在: $TARGET_DIR"; exit 1
            fi
            print_info "安裝: $(basename "$VEN_RPM_FILE")"
            rpm -ivh "$VEN_RPM_FILE"
            print_ok "VEN 安裝完成。" ;;
        ubuntu|debian)
            [ -z "$VEN_DEB_FILE" ] && VEN_DEB_FILE=$(ls "$TARGET_DIR"/*.deb 2>/dev/null | head -1) || VEN_DEB_FILE="$TARGET_DIR/$VEN_DEB_FILE"
            if [ -z "$VEN_DEB_FILE" ] || [ ! -f "$VEN_DEB_FILE" ]; then
                print_error "找不到 VEN DEB 安裝包。請確保留在: $TARGET_DIR"; exit 1
            fi
            print_info "安裝: $(basename "$VEN_DEB_FILE")"
            dpkg -i "$VEN_DEB_FILE"
            print_ok "VEN 安裝完成。" ;;
    esac
```

新：

```bash
    if [ -z "$SOURCE_DIR" ]; then
        TARGET_DIR="$SCRIPT_DIR"
    else
        TARGET_DIR="$SOURCE_DIR"
    fi

    case "$OS_TYPE" in
        rhel|centos|rocky|almalinux|ol)
            if [ -z "$VEN_RPM_FILE" ]; then
                VEN_RPM_FILE=$(ls "$TARGET_DIR"/*.rpm 2>/dev/null | head -1)
            else
                VEN_RPM_FILE="$TARGET_DIR/$VEN_RPM_FILE"
            fi
            if [ -z "$VEN_RPM_FILE" ] || [ ! -f "$VEN_RPM_FILE" ]; then
                print_error "找不到 VEN RPM 安裝包。請確保放在: $TARGET_DIR"; exit 1
            fi
            print_info "安裝: $(basename "$VEN_RPM_FILE")"
            rpm -ivh "$VEN_RPM_FILE"
            print_ok "VEN 安裝完成。" ;;
        ubuntu|debian)
            if [ -z "$VEN_DEB_FILE" ]; then
                VEN_DEB_FILE=$(ls "$TARGET_DIR"/*.deb 2>/dev/null | head -1)
            else
                VEN_DEB_FILE="$TARGET_DIR/$VEN_DEB_FILE"
            fi
            if [ -z "$VEN_DEB_FILE" ] || [ ! -f "$VEN_DEB_FILE" ]; then
                print_error "找不到 VEN DEB 安裝包。請確保放在: $TARGET_DIR"; exit 1
            fi
            print_info "安裝: $(basename "$VEN_DEB_FILE")"
            dpkg -i "$VEN_DEB_FILE"
            print_ok "VEN 安裝完成。" ;;
    esac
```

- [ ] **Step 3: 驗證**

```bash
bash -n linux/manual_deploy/deploy-illumio.sh && echo SYNTAX-OK
grep -c '確保留在' linux/manual_deploy/deploy-illumio.sh || echo "0 處殘留（預期）"
grep -c '確保放在' linux/manual_deploy/deploy-illumio.sh    # 預期：2
grep -c '&& TARGET_DIR=' linux/manual_deploy/deploy-illumio.sh || echo "0 處殘留（預期）"
```

- [ ] **Step 4: Commit**

```bash
git add linux/manual_deploy/deploy-illumio.sh
git commit -m "fix(linux): explicit if/else for installer detection, document filename-only override, fix typo"
```

---

### Task 10: check-sop-template.sh — docs 目錄不存在時報錯而非誤報 OK

find 的錯誤被 `2>/dev/null` 吞掉，若 docs 子目錄改名，腳本會找不到任何檔案卻回報「OK: all SOPs have §1–§7」。

**Files:**
- Modify: `scripts/check-sop-template.sh`

- [ ] **Step 1: 在 `ROOT=` 行之後插入目錄存在檢查**

在這一行之後：

```bash
ROOT="$(git rev-parse --show-toplevel)" || { echo "ERROR: must run inside a git repo" >&2; exit 1; }
```

插入：

```bash
for d in pce ven cert platform; do
  [[ -d "$ROOT/docs/$d" ]] || { echo "ERROR: missing directory: docs/$d" >&2; exit 1; }
done
```

- [ ] **Step 2: 移除 find 的 `2>/dev/null`**

舊：

```bash
done < <(find "$ROOT/docs/pce" "$ROOT/docs/ven" "$ROOT/docs/cert" "$ROOT/docs/platform" \
            -maxdepth 1 -name '*.md' -print0 2>/dev/null)
```

新：

```bash
done < <(find "$ROOT/docs/pce" "$ROOT/docs/ven" "$ROOT/docs/cert" "$ROOT/docs/platform" \
            -maxdepth 1 -name '*.md' -print0)
```

- [ ] **Step 3: 正向驗證（本 repo 四個目錄齊全，應照常通過）**

```bash
bash -n scripts/check-sop-template.sh && bash scripts/check-sop-template.sh; echo "exit=$?"
```

預期：`OK: all SOPs have §1–§7`、`exit=0`。

- [ ] **Step 4: 負向驗證（缺目錄的假 repo 應報錯）**

```bash
SCRATCH=/tmp/claude-1000/-home-harry-rd-illumio-deploy/8b02703b-9012-42d3-9a5b-b588cfc20622/scratchpad
rm -rf "$SCRATCH/fake-repo" && mkdir -p "$SCRATCH/fake-repo/docs/pce"
git -C "$SCRATCH/fake-repo" init -q
cd "$SCRATCH/fake-repo" && bash /home/harry/rd/illumio-deploy/scripts/check-sop-template.sh; echo "exit=$?"
cd /home/harry/rd/illumio-deploy
```

預期：`ERROR: missing directory: docs/ven`、`exit=1`。

- [ ] **Step 5: Commit**

```bash
git add scripts/check-sop-template.sh
git commit -m "fix(scripts): fail check-sop-template when docs directories are missing"
```

---

### Task 11: 檔案編碼與換行修正（最後執行）

實測發現：`deploy-illumio.bat` 是 **LF 換行 + UTF-8 無 BOM**、兩支 `.ps1` 是 **UTF-8 無 BOM**（檔頭為 `3c 23 0a`）。影響：(a) cmd 對 LF 檔案的標籤解析有已知問題（goto/call 可能找不到標籤）；(b) cmd 預設 OEM 代碼頁（zh-TW 為 CP950）讀 UTF-8 中文必亂碼；(c) Windows PowerShell 5.1 對無 BOM 檔案以 ANSI 解讀，中文字串亂碼。

**此 Task 必須最後執行**：改為 CRLF 後，前面各 Task 使用的 `grep '...$'` 斷言與 Edit anchor 都會受 `\r` 影響。

**Files:**
- Create: `.gitattributes`
- Modify: `windows/manual_deploy/deploy-illumio.bat`（檔頭加 `chcp 65001`）
- Modify: `windows/pairing_prereq/Import-RootCA.ps1`、`windows/manual_deploy/Deploy-Illumio.ps1`（加 UTF-8 BOM）

- [ ] **Step 1: 建立 `.gitattributes`**

```
* text=auto
*.sh text eol=lf
*.md text eol=lf
*.bat text eol=crlf
*.ps1 text eol=crlf
```

- [ ] **Step 2: bat 檔頭加入代碼頁切換**

在第 1 行 `@echo off` 之後插入：

```bat
REM 本檔以 UTF-8 儲存；切換主控台代碼頁避免中文亂碼
chcp 65001 >nul
```

- [ ] **Step 3: 兩支 ps1 加入 UTF-8 BOM（冪等：已有 BOM 則跳過）**

```bash
for f in windows/pairing_prereq/Import-RootCA.ps1 windows/manual_deploy/Deploy-Illumio.ps1; do
  head -c 3 "$f" | od -An -tx1 | grep -q 'ef bb bf' || sed -i '1s/^/\xef\xbb\xbf/' "$f"
done
```

- [ ] **Step 4: 提交並讓工作目錄反映 CRLF**

```bash
git add .gitattributes windows/manual_deploy/deploy-illumio.bat windows/pairing_prereq/Import-RootCA.ps1 windows/manual_deploy/Deploy-Illumio.ps1
git add --renormalize .
git status --short    # 檢視變更範圍，應僅限上述檔案
git commit -m "fix(windows): UTF-8 BOM for ps1, CRLF eol for bat/ps1, chcp 65001 in bat"
# 強制以新屬性重新 checkout，讓本機工作目錄變成 CRLF：
rm windows/manual_deploy/deploy-illumio.bat windows/pairing_prereq/Import-RootCA.ps1 windows/manual_deploy/Deploy-Illumio.ps1
git checkout -- windows/
```

- [ ] **Step 5: 驗證**

```bash
file windows/manual_deploy/deploy-illumio.bat      # 預期：出現 "with CRLF line terminators"
file windows/manual_deploy/Deploy-Illumio.ps1      # 預期：出現 "(with BOM)" 與 "CRLF"
head -c 3 windows/pairing_prereq/Import-RootCA.ps1 | od -An -tx1   # 預期：ef bb bf
git status --short                                 # 預期：無輸出（乾淨）
grep -c 'chcp 65001' windows/manual_deploy/deploy-illumio.bat      # 預期：1
```

---

### Task 12: 最終驗證與收尾

**Files:** 無新修改；全面複驗。

- [ ] **Step 1: 全部 bash 腳本語法與功能複驗**

```bash
bash -n linux/pairing_prereq/prepare-and-pair.sh && \
bash -n linux/manual_deploy/deploy-illumio.sh && \
bash -n scripts/check-sop-template.sh && \
bash scripts/check-sop-template.sh && echo ALL-OK
```

預期：`OK: all SOPs have §1–§7` 與 `ALL-OK`。

- [ ] **Step 2: 確認所有 review 項目都有對應 commit**

```bash
git log --oneline main..HEAD
```

預期：Task 1–11 共 11 個 commit（外加 main 上的計劃檔 commit）。對照本計劃開頭的「review 發現對照表」逐項勾稽。

- [ ] **Step 3: 檢視總 diff 是否有越界修改**

```bash
git diff main..HEAD --stat
```

預期只出現：`.gitattributes`、3 支 Windows 腳本、2 支 Linux 腳本、`scripts/check-sop-template.sh`、計劃檔本身。若出現其他檔案即為越界，需回頭修正。

- [ ] **Step 4: 完成後依 superpowers:finishing-a-development-branch 決定合併方式**

---

## 附錄：Windows 實機驗證清單（合併前人工執行）

本機無 Windows 環境，以下項目需在測試機（建議 Windows Server 2016+；若部署目標含 2012 R2 以前的系統，`chcp 65001` 與 batch 的相容性必須在最舊目標 OS 上驗證）逐項確認。全部通過前，`.bat` 與 `.ps1` 的修改視為未驗收。

1. **bat 冒煙測試**：不改任何設定直接以系統管理員執行 `deploy-illumio.bat` → 預期立即顯示「請先設定 ACTIVATION_CODE」並結束，中文無亂碼，過程無 "The system cannot find the batch label specified"、無 "ECHO is off."。
2. **bat 憑證防重複**：替換為真實 CA 憑證後執行兩次 → 第一次顯示憑證匯入成功；第二次顯示 `[SKIP] 憑證已存在`。並以 PowerShell 確認 store 內 thumbprint 與腳本印出的一致：`Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -like "*<你的CA>*" | Select-Object Thumbprint`。
3. **DataDir 獨立生效**：只設定 `DATA_DIR`（或 ps1 只傳 `-DataDir`）執行安裝 → 從 `%TEMP%\IllumioVENInstall.log` 確認安裝參數含 `DATAFOLDER`，且資料目錄實際落在自訂位置。
4. **3010 路徑**：若測試機安裝回傳 3010 → 預期顯示「安裝完成 (Exit Code 3010: 需要重新開機)」且繼續執行啟用步驟。
5. **冪等性**：已安裝 VEN 的機器重跑 bat 與 ps1 → 預期顯示 `[SKIP] 偵測到 VEN 已安裝`，不重跑安裝器。
6. **ps1 權限檢查**：以非管理員 PowerShell 執行兩支 ps1 → 預期明確顯示「此腳本需要以系統管理員身分執行 PowerShell。」
7. **Import-RootCA.ps1 錯誤路徑**：`-CertFile C:\不存在\x.crt` → 預期 Throw「指定的憑證檔案不存在」，不得改用內嵌憑證。
8. **佔位符防呆（ps1）**：未替換內嵌憑證且無同目錄 illumio-ca.crt 時執行 → 預期顯示「內嵌憑證仍為佔位符」。
9. **中文顯示**：兩支 ps1 在 Windows PowerShell 5.1 下執行，所有中文訊息無亂碼（驗證 BOM 修正）。
10. **Linux 全流程**（如有測試 VM）：RHEL 系與 Debian 系各跑一次 `deploy-illumio.sh` 完整流程（含佔位符憑證應被擋下、真憑證應匯入、重跑應 SKIP）。
