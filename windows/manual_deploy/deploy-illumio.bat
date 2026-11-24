@echo off
REM 本檔以 UTF-8 儲存；切換主控台代碼頁避免中文亂碼
chcp 65001 >nul
REM ===========================================================================
REM  Illumio VEN 完整部署 (Windows / Batch)
REM
REM  流程: CA 憑證匯入 -> PCE 連線檢查 -> 靜默安裝 -> 啟用
REM  本機沒有安裝檔時，向 PCE 下載符合本機的版本並驗證 SHA256 (需要 curl.exe)。
REM  可重複執行、全程不需互動。只使用 cmd 內建指令與 certutil / whoami /
REM  findstr，不呼叫 PowerShell，適用於封鎖 PowerShell 的環境。
REM
REM  設定方式 (擇一): 修改下方設定區，或由派送工具設定環境變數
REM    ILLUMIO_MANAGEMENT_SERVER / ILLUMIO_ACTIVATION_CODE
REM
REM  結束碼:
REM    0    成功 (含已安裝、已啟用而跳過)      6  憑證無效或匯入失敗
REM    3010 成功，但需要重新開機               7  無法連線或無法驗證 PCE
REM    2    參數錯誤                           8  安裝失敗
REM    3    權限不足                           9  啟用失敗
REM    (8 也包含找不到安裝檔與下載失敗)
REM ===========================================================================

setlocal enabledelayedexpansion

REM ==========================================
REM 設定區 (可改這裡，也可用環境變數覆蓋)
REM ==========================================
set "MANAGEMENT_SERVER=<YOUR_PCE_FQDN:PORT>"
set "ACTIVATION_CODE=<YOUR_ACTIVATION_CODE>"
REM 安裝檔所在目錄；留空 = 腳本所在目錄
set "SOURCE_DIR="
REM 安裝檔檔名；留空 = 自動尋找 *illumio-ven*.exe，找不到則向 PCE 下載
set "EXE_FILE="
REM 設為 1 = 本機沒有安裝檔時不向 PCE 下載，直接失敗
set "NO_DOWNLOAD=0"
REM 下載安裝檔使用的 PCE API 版本 (較新的 PCE 仍接受較舊的版本)
set "API_VERSION=v25"
set "INSTALL_DIR=C:\Program Files\Illumio"
set "DATA_DIR=C:\ProgramData\Illumio"
set "LOG_FILE=%TEMP%\IllumioDeploy.log"
REM 設為 1 = 略過安裝前的 PCE 連線檢查
set "SKIP_TLS_CHECK=0"
REM ==========================================

if defined ILLUMIO_MANAGEMENT_SERVER set "MANAGEMENT_SERVER=%ILLUMIO_MANAGEMENT_SERVER%"
if defined ILLUMIO_ACTIVATION_CODE set "ACTIVATION_CODE=%ILLUMIO_ACTIVATION_CODE%"

set "DEFAULT_INSTALL_DIR=C:\Program Files\Illumio"
set "DEFAULT_DATA_DIR=C:\ProgramData\Illumio"
set "REBOOT_REQUIRED="
set "CURL=%SystemRoot%\System32\curl.exe"

call :Log ==== Illumio VEN 部署 (Batch) ====

REM 權限檢查：High (S-1-16-12288) 或 System (S-1-16-16384) 完整性等級
whoami /groups | findstr /C:"S-1-16-12288" /C:"S-1-16-16384" >nul 2>&1
if errorlevel 1 (
    call :Log [ERROR] 需要以系統管理員身分執行。
    exit /b 3
)

REM 必填參數先驗證，避免安裝完才發現無法啟用
if "!ACTIVATION_CODE:~0,1!"=="<" (
    call :Log [ERROR] 未設定啟用碼。請修改設定區或設定環境變數 ILLUMIO_ACTIVATION_CODE。
    exit /b 2
)
if "!MANAGEMENT_SERVER:~0,1!"=="<" (
    call :Log [ERROR] 未設定 PCE 位址。請修改設定區或設定環境變數 ILLUMIO_MANAGEMENT_SERVER。
    exit /b 2
)

REM 私有工作目錄：只有 SYSTEM 與 Administrators 可存取，避免暫存的憑證或安裝檔
REM 在驗證後、使用前被其他本機帳號置換。目錄已存在時 mkdir 會失敗，不沿用既有目錄。
set "WORK_DIR=%TEMP%\illumio-deploy-%RANDOM%-%RANDOM%-%RANDOM%"
mkdir "%WORK_DIR%" 2>nul
if errorlevel 1 (
    call :Log [ERROR] 無法建立工作目錄: %WORK_DIR%
    exit /b 1
)
icacls "%WORK_DIR%" /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" >nul 2>&1
if errorlevel 1 (
    rd /s /q "%WORK_DIR%" 2>nul
    call :Log [ERROR] 無法設定工作目錄的存取權限: %WORK_DIR%
    exit /b 1
)

REM === Step 1: CA 憑證 ===
call :Log [Step 1/4] 匯入 CA 憑證

set "CERT_PATH="
set "TEMP_CERT=%WORK_DIR%\illumio-ca-embedded.crt"
if exist "%~dp0illumio-ca.crt" (
    set "CERT_PATH=%~dp0illumio-ca.crt"
) else (
    REM 內嵌憑證 (選用)：每一行 base64 都要以 echo 為前綴。保留佔位符 = 不使用。
    > "%TEMP_CERT%" (
        echo -----BEGIN CERTIFICATE-----
        echo PLACEHOLDER_CERTIFICATE_CONTENT_REPLACE_WITH_YOUR_ACTUAL_CERTIFICATE
        echo -----END CERTIFICATE-----
    )
    findstr /C:"PLACEHOLDER_CERTIFICATE_CONTENT" "%TEMP_CERT%" >nul 2>&1
    if errorlevel 1 (
        set "CERT_PATH=%TEMP_CERT%"
    ) else (
        del "%TEMP_CERT%" 2>nul
    )
)

if not defined CERT_PATH (
    call :Log [SKIP]   未提供 CA 憑證，跳過匯入。將以系統既有的信任憑證驗證 PCE。
    goto :step2
)

call :Log [INFO]   憑證來源: !CERT_PATH!
findstr /C:"PLACEHOLDER_CERTIFICATE_CONTENT" "!CERT_PATH!" >nul 2>&1
if not errorlevel 1 (
    call :Log [ERROR] 憑證檔內容仍為佔位符。
    set "RC=6" & goto :end
)
REM 指紋 = DER 編碼的 SHA1：先把 PEM 轉成 DER 再取雜湊 (certutil 輸出第二行，不受語系影響)
set "CERT_DER=%WORK_DIR%\illumio-ca.der"
del "%CERT_DER%" 2>nul
set "HASH_SRC=%CERT_DER%"
certutil -decode "!CERT_PATH!" "%CERT_DER%" >nul 2>&1
if errorlevel 1 set "HASH_SRC=!CERT_PATH!"
set "THUMB="
for /f "skip=1 delims=" %%H in ('certutil -hashfile "!HASH_SRC!" SHA1 2^>nul') do if not defined THUMB set "THUMB=%%H"
if defined THUMB set "THUMB=!THUMB: =!"
del "%CERT_DER%" 2>nul

REM 已存在就不再匯入 (含群組原則派發的憑證)。certutil -verifystore 對不存在的憑證也回 0，故直接查登錄機碼
set "CERT_EXISTS="
if defined THUMB (
    for %%K in ("HKLM\SOFTWARE\Microsoft\SystemCertificates\ROOT\Certificates" "HKLM\SOFTWARE\Policies\Microsoft\SystemCertificates\ROOT\Certificates" "HKLM\SOFTWARE\Microsoft\EnterpriseCertificates\ROOT\Certificates") do (
        reg query "%%~K\!THUMB!" >nul 2>&1 && set "CERT_EXISTS=1"
    )
)
if defined CERT_EXISTS (
    call :Log [SKIP]   憑證已存在於受信任的根憑證授權單位 ^(Thumbprint: !THUMB!^)。
    del "%TEMP_CERT%" 2>nul
    goto :step2
)

certutil -addstore Root "!CERT_PATH!" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :Log [ERROR] 憑證匯入失敗 ^(憑證無效或權限不足^)。詳見: %LOG_FILE%
    del "%TEMP_CERT%" 2>nul
    set "RC=6" & goto :end
)
call :Log [OK]     憑證已匯入 ^(Thumbprint: !THUMB!^)。
del "%TEMP_CERT%" 2>nul

:step2
REM === Step 2: 安裝前連線檢查 ===
call :Log [Step 2/4] 檢查 PCE 連線

if "%SKIP_TLS_CHECK%"=="1" (
    call :Log [SKIP]   已指定略過連線檢查。
    goto :step3
)
if not exist "%CURL%" (
    call :Log [SKIP]   此系統無 curl.exe ^(Windows 10 1803 / Server 2019 以前^)，略過連線檢查。
    goto :step3
)
REM curl.exe 走 Schannel 與系統憑證存放區，可同時驗證信任鏈
REM --ssl-no-revoke：私有 CA 通常沒有可連線的撤銷清單，Schannel 預設會因此拒絕連線
"%CURL%" -sS --ssl-no-revoke -o NUL --connect-timeout 10 --max-time 30 "https://%MANAGEMENT_SERVER%/" >> "%LOG_FILE%" 2>&1
set "CURL_RC=!errorlevel!"
if "!CURL_RC!"=="0" (
    call :Log [OK]     已與 %MANAGEMENT_SERVER% 完成 TLS 握手，憑證受信任。
    goto :step3
)
set "TLS_ERR="
for %%C in (35 51 53 54 58 59 60 77 83 90 91) do if "!CURL_RC!"=="%%C" set "TLS_ERR=1"
if defined TLS_ERR (
    call :Log [ERROR] 無法驗證 PCE 憑證 ^(curl 結束碼 !CURL_RC!^)。請提供簽發 PCE 憑證的 CA，並確認路徑上沒有 TLS 攔截。
) else (
    call :Log [ERROR] 無法連線至 %MANAGEMENT_SERVER% ^(curl 結束碼 !CURL_RC!^)。請檢查 DNS、防火牆與 Proxy 設定。
)
set "RC=7" & goto :end

:step3
REM === Step 3: 安裝 VEN ===
call :Log [Step 3/4] 安裝 VEN

call :FindCtl
if defined VEN_CTL (
    call :Log [SKIP]   VEN 已安裝 ^(!VEN_CTL!^)，跳過安裝。
    goto :step4
)

if "%SOURCE_DIR%"=="" (
    set "PKG_DIR=%~dp0"
) else (
    set "PKG_DIR=%SOURCE_DIR%"
)
REM 統一補上結尾反斜線，SOURCE_DIR 有沒有帶都可以
if not "!PKG_DIR:~-1!"=="\" set "PKG_DIR=!PKG_DIR!\"

if "%EXE_FILE%"=="" (
    set "EXE_COUNT=0"
    for %%F in ("!PKG_DIR!*illumio-ven*.exe") do (
        set /a EXE_COUNT+=1
        set "EXE_FILE=%%~nxF"
    )
    if !EXE_COUNT! GTR 1 (
        call :Log [ERROR] 在 !PKG_DIR! 找到 !EXE_COUNT! 個安裝檔，無法判斷要裝哪一個。請設定 EXE_FILE。
        set "RC=8" & goto :end
    )
)

if not "!EXE_FILE!"=="" (
    set "INSTALLER=!PKG_DIR!!EXE_FILE!"
    if not exist "!INSTALLER!" (
        call :Log [ERROR] 找不到安裝檔: !INSTALLER!
        set "RC=8" & goto :end
    )
    goto :install
)

REM --- 本機沒有安裝檔：向 PCE 下載 (與官方 pair.ps1 相同的機制) ---
if "%NO_DOWNLOAD%"=="1" (
    call :Log [ERROR] 在 !PKG_DIR! 找不到 *illumio-ven*.exe ^(已設定 NO_DOWNLOAD^)。
    set "RC=8" & goto :end
)
if not exist "%CURL%" (
    call :Log [ERROR] 在 !PKG_DIR! 找不到 *illumio-ven*.exe，且此系統沒有 curl.exe 可向 PCE 下載。請自行提供安裝檔。
    set "RC=8" & goto :end
)

set "DL_ARCH=%PROCESSOR_ARCHITECTURE%"
if /i "%DL_ARCH%"=="AMD64" set "DL_ARCH=x64"
REM ver 的輸出為「... [Version 10.0.20348.1]」；方括號內最後一個字是版本，文字部分會隨語系改變
set "OS_FULLVER="
for /f "tokens=2 delims=[]" %%A in ('ver') do for %%B in (%%A) do set "OS_FULLVER=%%B"
for /f "tokens=1,2 delims=." %%M in ("!OS_FULLVER!") do set "DL_OSVER=%%M.%%N"

set "DL_FILE=%WORK_DIR%\illumio-ven-download.tmp"
set "DL_HEADERS=%WORK_DIR%\illumio-ven-download.headers"
call :Log [INFO]   本機沒有安裝檔，向 PCE 下載 [!DL_ARCH!][Windows][!DL_OSVER!]

REM 網址含 ^& 字元，先放進變數再以延遲展開帶入；HTTP 狀態碼寫入檔案後讀回
set "DL_URL=https://%MANAGEMENT_SERVER%/api/%API_VERSION%/software/ven/image?architecture=!DL_ARCH!&distribution=Windows&version=!DL_OSVER!"
set "HTTP_CODE="
"%CURL%" -sS --ssl-no-revoke --user "agent_0:%ACTIVATION_CODE%" --connect-timeout 10 --max-time 900 -D "%DL_HEADERS%" -o "%DL_FILE%" -w "%%{http_code}" "!DL_URL!" > "%WORK_DIR%\http_code" 2>> "%LOG_FILE%"
set /p HTTP_CODE=<"%WORK_DIR%\http_code"
if not "!HTTP_CODE!"=="200" (
    del "%DL_FILE%" "%DL_HEADERS%" 2>nul
    if "!HTTP_CODE!"=="401" call :Log [ERROR] PCE 拒絕下載 ^(HTTP 401^)。請確認啟用碼有效且未過期。
    if "!HTTP_CODE!"=="406" call :Log [ERROR] PCE 沒有符合 [!DL_ARCH!][Windows][!DL_OSVER!] 的安裝檔，或啟用碼無效。
    call :Log [ERROR] 安裝檔下載失敗 ^(HTTP !HTTP_CODE!^)。
    set "RC=8" & goto :end
)

set "EXPECTED_SHA="
set "DL_NAME="
for /f "tokens=2 delims=: " %%H in ('findstr /i /b "x-sha256:" "%DL_HEADERS%"') do set "EXPECTED_SHA=%%H"
for /f "tokens=2 delims==" %%H in ('findstr /i /b "content-disposition:" "%DL_HEADERS%"') do set "DL_NAME=%%~nxH"
del "%DL_HEADERS%" 2>nul
if not defined EXPECTED_SHA set "DL_NAME="
if not defined DL_NAME (
    call :Log [ERROR] PCE 回應缺少檔名或 SHA256 標頭，無法驗證安裝檔。
    goto :fail8
)

REM 先改成最終檔名再驗證，執行的就是剛驗證過的那個檔案
set "INSTALLER=%WORK_DIR%\!DL_NAME!"
move /y "%DL_FILE%" "!INSTALLER!" >nul
REM certutil -hashfile 的第二行是雜湊值
set "ACTUAL_SHA="
for /f "skip=1 delims=" %%H in ('certutil -hashfile "!INSTALLER!" SHA256') do if not defined ACTUAL_SHA set "ACTUAL_SHA=%%H"
if defined ACTUAL_SHA set "ACTUAL_SHA=!ACTUAL_SHA: =!"
if /i not "!ACTUAL_SHA!"=="!EXPECTED_SHA!" (
    call :Log [ERROR] 安裝檔 SHA256 不符 ^(預期 !EXPECTED_SHA!，實際 !ACTUAL_SHA!^)。
    goto :fail8
)
call :Log [OK]     已下載並通過 SHA256 驗證: !DL_NAME!
goto :install

:install
set "VEN_INSTALL_LOG=%TEMP%\IllumioVENInstall.log"
REM INSTALLFOLDER 與 DATAFOLDER 是獨立的安裝屬性，各自非預設值時才傳入
set "EXTRA_ARGS="
if /i not "%INSTALL_DIR%"=="%DEFAULT_INSTALL_DIR%" set "EXTRA_ARGS=INSTALLFOLDER="%INSTALL_DIR%""
if /i not "%DATA_DIR%"=="%DEFAULT_DATA_DIR%" set "EXTRA_ARGS=!EXTRA_ARGS! DATAFOLDER="%DATA_DIR%""

call :Log [INFO]   安裝: !INSTALLER!
"!INSTALLER!" /install /quiet /norestart /log "%VEN_INSTALL_LOG%" !EXTRA_ARGS! >> "%LOG_FILE%" 2>&1
set "INSTALL_RC=!errorlevel!"

if "!INSTALL_RC!"=="3010" (
    set "REBOOT_REQUIRED=1"
    call :Log [OK]     VEN 安裝完成 ^(安裝程式回報需要重新開機^)。
) else if not "!INSTALL_RC!"=="0" (
    call :Log [ERROR] 安裝失敗 ^(安裝程式結束碼 !INSTALL_RC!^)。詳見: %VEN_INSTALL_LOG%
    set "RC=8" & goto :end
) else (
    call :Log [OK]     VEN 安裝完成。
)

call :FindCtl
if not defined VEN_CTL (
    call :Log [ERROR] 安裝後仍找不到 illumio-ven-ctl.exe。詳見: %VEN_INSTALL_LOG%
    set "RC=8" & goto :end
)

:step4
REM === Step 4: 啟用 ===
call :Log [Step 4/4] 向 PCE 啟用

REM 已配對的 VEN 會在資料目錄留下 agent_id.cfg；再次 activate 會失敗，故直接跳過
set "ACTIVATED="
if exist "%DATA_DIR%\etc\agent_id.cfg" set "ACTIVATED=1"
if exist "%DEFAULT_DATA_DIR%\etc\agent_id.cfg" set "ACTIVATED=1"
if defined REG_DATA if exist "!REG_DATA!etc\agent_id.cfg" set "ACTIVATED=1"
if defined ACTIVATED (
    call :Log [SKIP]   VEN 已啟用，跳過啟用。
    goto :done
)

call :Log [INFO]   PCE: %MANAGEMENT_SERVER%
"!VEN_CTL!" activate -activation-code %ACTIVATION_CODE% -management-server %MANAGEMENT_SERVER% >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :Log [ERROR] 啟用失敗。請確認啟用碼有效且未超過使用次數。詳見: %LOG_FILE%
    set "RC=9" & goto :end
)
call :Log [OK]     啟用完成。

:done
if defined REBOOT_REQUIRED (
    call :Log [OK]     部署完成，需要重新開機 ^(結束碼 3010^)。
    set "RC=3010" & goto :end
)
call :Log [OK]     部署完成。
set "RC=0" & goto :end

REM 統一出口：清除工作目錄後以 RC 結束
:fail8
set "RC=8"
:end
rd /s /q "%WORK_DIR%" 2>nul
exit /b %RC%

REM ==========================================
REM 副程式
REM ==========================================
:Log
echo %*
echo [%DATE% %TIME%] %* >> "%LOG_FILE%"
exit /b 0

REM 尋找 illumio-ven-ctl.exe (VEN 24.2.10 起提供)。
REM 23.5 以前的 VEN 只有 illumio-ven-ctl.ps1，請改用 Deploy-Illumio.ps1。
:FindCtl
set "VEN_CTL="
set "REG_INSTALL="
set "REG_DATA="
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\Illumio" /v InstallPath 2^>nul ^| findstr /i "InstallPath"') do set "REG_INSTALL=%%B"
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\Illumio" /v DataPath 2^>nul ^| findstr /i "DataPath"') do set "REG_DATA=%%B"
if exist "%DEFAULT_INSTALL_DIR%\illumio-ven-ctl.exe" set "VEN_CTL=%DEFAULT_INSTALL_DIR%\illumio-ven-ctl.exe"
if exist "%INSTALL_DIR%\illumio-ven-ctl.exe" set "VEN_CTL=%INSTALL_DIR%\illumio-ven-ctl.exe"
REM VEN 安裝後會把實際路徑寫入 HKLM\SOFTWARE\Illumio，重跑時不必再設定自訂目錄
if defined REG_INSTALL if exist "!REG_INSTALL!illumio-ven-ctl.exe" set "VEN_CTL=!REG_INSTALL!illumio-ven-ctl.exe"
exit /b 0
