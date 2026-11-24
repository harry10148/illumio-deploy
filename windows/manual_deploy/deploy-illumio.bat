@echo off
REM 本檔以 UTF-8 儲存；切換主控台代碼頁避免中文亂碼
chcp 65001 >nul
REM ===========================================================================
REM  Illumio VEN 完整部署 (Windows / Batch)
REM
REM  流程: CA 憑證匯入 -> PCE 連線檢查 -> 靜默安裝 -> 啟用
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
REM ===========================================================================

setlocal enabledelayedexpansion

REM ==========================================
REM 設定區 (可改這裡，也可用環境變數覆蓋)
REM ==========================================
set "MANAGEMENT_SERVER=<YOUR_PCE_FQDN:PORT>"
set "ACTIVATION_CODE=<YOUR_ACTIVATION_CODE>"
REM 安裝檔所在目錄；留空 = 腳本所在目錄
set "SOURCE_DIR="
REM 安裝檔檔名；留空 = 自動尋找 *illumio-ven*.exe
set "EXE_FILE="
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

REM === Step 1: CA 憑證 ===
call :Log [Step 1/4] 匯入 CA 憑證

set "CERT_PATH="
set "TEMP_CERT=%TEMP%\illumio-ca-embedded.crt"
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
    exit /b 6
)
REM certutil -addstore 對已存在的憑證不會重複加入，本身即可重複執行
certutil -addstore Root "!CERT_PATH!" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :Log [ERROR] 憑證匯入失敗 ^(憑證無效或權限不足^)。詳見: %LOG_FILE%
    del "%TEMP_CERT%" 2>nul
    exit /b 6
)
call :Log [OK]     憑證已在受信任的根憑證授權單位。
del "%TEMP_CERT%" 2>nul

:step2
REM === Step 2: 安裝前連線檢查 ===
call :Log [Step 2/4] 檢查 PCE 連線

if "%SKIP_TLS_CHECK%"=="1" (
    call :Log [SKIP]   已指定略過連線檢查。
    goto :step3
)
if not exist "%SystemRoot%\System32\curl.exe" (
    call :Log [SKIP]   此系統無 curl.exe ^(Windows 10 1803 / Server 2019 以前^)，略過連線檢查。
    goto :step3
)
REM curl.exe 走 Schannel 與系統憑證存放區，可同時驗證信任鏈
"%SystemRoot%\System32\curl.exe" -sS -o NUL --connect-timeout 10 --max-time 30 "https://%MANAGEMENT_SERVER%/" >> "%LOG_FILE%" 2>&1
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
exit /b 7

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
    if "!EXE_COUNT!"=="0" (
        call :Log [ERROR] 在 !PKG_DIR! 找不到 *illumio-ven*.exe。請放入安裝檔，或設定 EXE_FILE。
        exit /b 8
    )
    if not "!EXE_COUNT!"=="1" (
        call :Log [ERROR] 在 !PKG_DIR! 找到 !EXE_COUNT! 個安裝檔，無法判斷要裝哪一個。請設定 EXE_FILE。
        exit /b 8
    )
)

set "INSTALLER=!PKG_DIR!!EXE_FILE!"
if not exist "!INSTALLER!" (
    call :Log [ERROR] 找不到安裝檔: !INSTALLER!
    exit /b 8
)

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
    exit /b 8
) else (
    call :Log [OK]     VEN 安裝完成。
)

call :FindCtl
if not defined VEN_CTL (
    call :Log [ERROR] 安裝後仍找不到 illumio-ven-ctl.exe。詳見: %VEN_INSTALL_LOG%
    exit /b 8
)

:step4
REM === Step 4: 啟用 ===
call :Log [Step 4/4] 向 PCE 啟用

REM 已配對的 VEN 會在資料目錄留下 agent_id.cfg；再次 activate 會失敗，故直接跳過
set "ACTIVATED="
if exist "%DATA_DIR%\etc\agent_id.cfg" set "ACTIVATED=1"
if exist "%DEFAULT_DATA_DIR%\etc\agent_id.cfg" set "ACTIVATED=1"
if defined ACTIVATED (
    call :Log [SKIP]   VEN 已啟用，跳過啟用。
    goto :done
)

call :Log [INFO]   PCE: %MANAGEMENT_SERVER%
"!VEN_CTL!" activate -activation-code %ACTIVATION_CODE% -management-server %MANAGEMENT_SERVER% >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :Log [ERROR] 啟用失敗。請確認啟用碼有效且未超過使用次數。詳見: %LOG_FILE%
    exit /b 9
)
call :Log [OK]     啟用完成。

:done
if defined REBOOT_REQUIRED (
    call :Log [OK]     部署完成，需要重新開機 ^(結束碼 3010^)。
    exit /b 3010
)
call :Log [OK]     部署完成。
exit /b 0

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
if exist "%DEFAULT_INSTALL_DIR%\illumio-ven-ctl.exe" set "VEN_CTL=%DEFAULT_INSTALL_DIR%\illumio-ven-ctl.exe"
if exist "%INSTALL_DIR%\illumio-ven-ctl.exe" set "VEN_CTL=%INSTALL_DIR%\illumio-ven-ctl.exe"
exit /b 0
