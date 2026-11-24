<#
.SYNOPSIS
    Illumio VEN 完整部署 (Windows / PowerShell)

.DESCRIPTION
    1. 匯入 PCE 的 CA 憑證 (未提供憑證則跳過，改用系統既有信任)
    2. 安裝前檢查到 PCE 的連線 (不通即停止，不留下半套安裝)
    3. 靜默安裝 VEN (已安裝則跳過)
    4. 向 PCE 啟用 (已啟用則跳過)

    可重複執行、全程不需互動，適合 SCCM / Intune / GPO 等派送工具。
    只使用 Windows 內建指令；可在 Constrained Language Mode 下執行。

.PARAMETER ManagementServer
    PCE 位址 (FQDN:PORT)。未指定時取環境變數 ILLUMIO_MANAGEMENT_SERVER。

.PARAMETER ActivationCode
    啟用碼。未指定時取環境變數 ILLUMIO_ACTIVATION_CODE。

.PARAMETER CertFile
    CA 憑證 (PEM)。預設: 腳本同目錄 illumio-ca.crt，其次內嵌憑證。

.PARAMETER SourceDir
    安裝檔所在目錄。預設: 腳本所在目錄。

.PARAMETER ExeFile
    安裝檔檔名。預設: 自動尋找 *illumio-ven*.exe。

.PARAMETER InstallDir
    VEN 安裝目錄。預設: C:\Program Files\Illumio

.PARAMETER DataDir
    VEN 資料目錄。預設: C:\ProgramData\Illumio

.PARAMETER LogFile
    日誌檔。預設: %TEMP%\IllumioDeploy.log (以 SYSTEM 執行時為 C:\Windows\Temp)

.PARAMETER SkipTlsCheck
    略過安裝前的 PCE 連線檢查。

.EXAMPLE
    .\Deploy-Illumio.ps1 -ManagementServer pce.example.com:8443 -ActivationCode <CODE>

.NOTES
    結束碼:
      0    成功 (含已安裝、已啟用而跳過)      6  憑證無效或匯入失敗
      3010 成功，但需要重新開機               7  無法連線或無法驗證 PCE
      1    未預期的錯誤                       8  安裝失敗
      2    參數錯誤                           9  啟用失敗
      3    權限不足
#>

param(
    [string]$ManagementServer = "<YOUR_PCE_FQDN:PORT>",
    [string]$ActivationCode   = "<YOUR_ACTIVATION_CODE>",
    [string]$CertFile         = "",
    [string]$SourceDir        = "",
    [string]$ExeFile          = "",
    [string]$InstallDir       = "C:\Program Files\Illumio",
    [string]$DataDir          = "C:\ProgramData\Illumio",
    [string]$LogFile          = "$env:TEMP\IllumioDeploy.log",
    [switch]$SkipTlsCheck
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# 內嵌憑證 (選用)。保留佔位符 = 不使用內嵌憑證。
$EmbeddedCertContent = @"
-----BEGIN CERTIFICATE-----
PLACEHOLDER_CERTIFICATE_CONTENT_REPLACE_WITH_YOUR_ACTUAL_CERTIFICATE
-----END CERTIFICATE-----
"@

$DefaultInstallDir = "C:\Program Files\Illumio"
$DefaultDataDir    = "C:\ProgramData\Illumio"

function Write-Log {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    $color = switch ($Level) { "INFO" {"Cyan"} "OK" {"Green"} "SKIP" {"Yellow"} "ERROR" {"Red"} default {"White"} }
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

# 執行外部程式並把輸出寫入日誌。PowerShell 5.1 在 ErrorActionPreference=Stop 時，
# 外部程式只要寫入 stderr 就會被當成例外，所以這裡區域性改為 Continue。
function Invoke-Logged {
    param([string]$Label, [string]$Exe, [string[]]$ArgList)
    $ErrorActionPreference = "Continue"
    & $Exe @ArgList 2>&1 | ForEach-Object { Write-Log "INFO" "${Label}: $_" }
}

# 路徑所在磁碟機不存在時 Test-Path 可能丟出例外，一律視為不存在
function Test-FileExists {
    param([string]$Path)
    try { return [bool](Test-Path -LiteralPath $Path -PathType Leaf) } catch { return $false }
}

function Stop-Deploy {
    param([int]$Code, [string]$Message)
    Write-Log "ERROR" $Message
    Write-Log "ERROR" "部署中止 (結束碼 $Code)。日誌: $LogFile"
    exit $Code
}

try {
    # 參數未指定時改取環境變數
    if ($ManagementServer -like "<*" -and $env:ILLUMIO_MANAGEMENT_SERVER) { $ManagementServer = $env:ILLUMIO_MANAGEMENT_SERVER }
    if ($ActivationCode -like "<*" -and $env:ILLUMIO_ACTIVATION_CODE) { $ActivationCode = $env:ILLUMIO_ACTIVATION_CODE }

    Write-Log "INFO" "==== Illumio VEN 部署 (PowerShell) ===="

    # 權限檢查：High (S-1-16-12288) 或 System (S-1-16-16384) 完整性等級。
    # 用 whoami 而非 .NET 型別，才能在 Constrained Language Mode 下執行。
    $groups = (& whoami.exe /groups) -join "`n"
    if ($groups -notmatch "S-1-16-12288" -and $groups -notmatch "S-1-16-16384") {
        Stop-Deploy 3 "需要以系統管理員身分執行。"
    }

    # 必填參數先驗證，避免安裝完才發現無法啟用
    if (-not $ActivationCode -or $ActivationCode -like "<*") {
        Stop-Deploy 2 "未設定啟用碼。請用 -ActivationCode 或環境變數 ILLUMIO_ACTIVATION_CODE。"
    }
    if (-not $ManagementServer -or $ManagementServer -like "<*") {
        Stop-Deploy 2 "未設定 PCE 位址。請用 -ManagementServer 或環境變數 ILLUMIO_MANAGEMENT_SERVER。"
    }
    if ($ManagementServer -notmatch '^[A-Za-z0-9._-]+:[0-9]+$') {
        Stop-Deploy 2 "PCE 位址格式應為 主機名稱:埠號 (例如 pce.example.com:8443)，目前為: $ManagementServer"
    }
    $pceHost, $pcePort = $ManagementServer -split ":"

    # === Step 1: CA 憑證 ===
    Write-Log "INFO" "[Step 1/4] 匯入 CA 憑證"

    $certPath = ""
    $tempCertPath = ""
    $localCertPath = Join-Path $PSScriptRoot "illumio-ca.crt"
    if ($CertFile) {
        if (-not (Test-Path -LiteralPath $CertFile)) { Stop-Deploy 6 "指定的憑證檔不存在: $CertFile" }
        $certPath = $CertFile
    } elseif (Test-Path -LiteralPath $localCertPath) {
        $certPath = $localCertPath
    } elseif ($EmbeddedCertContent -notlike "*PLACEHOLDER_CERTIFICATE_CONTENT*") {
        $tempCertPath = Join-Path $env:TEMP "illumio-ca-embedded.crt"
        Set-Content -Path $tempCertPath -Value $EmbeddedCertContent -Encoding Ascii
        $certPath = $tempCertPath
    }

    if (-not $certPath) {
        Write-Log "SKIP" "未提供 CA 憑證，跳過匯入。將以系統既有的信任憑證驗證 PCE。"
    } else {
        Write-Log "INFO" "憑證來源: $certPath"
        if ((Get-Content -LiteralPath $certPath -Raw) -like "*PLACEHOLDER_CERTIFICATE_CONTENT*") {
            Stop-Deploy 6 "憑證檔內容仍為佔位符。"
        }
        try {
            $thumbprint = (Get-PfxCertificate -FilePath $certPath).Thumbprint
        } catch {
            Stop-Deploy 6 "憑證內容無法解析為有效的 X.509 憑證: $_"
        }
        if (Test-Path -LiteralPath "Cert:\LocalMachine\Root\$thumbprint") {
            Write-Log "SKIP" "憑證已存在於受信任的根憑證授權單位 (Thumbprint: $thumbprint)。"
        } else {
            try {
                Import-Certificate -FilePath $certPath -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
            } catch {
                Stop-Deploy 6 "憑證匯入失敗: $_"
            }
            Write-Log "OK" "憑證已匯入 (Thumbprint: $thumbprint)。"
        }
        if ($tempCertPath) { Remove-Item -LiteralPath $tempCertPath -Force -ErrorAction SilentlyContinue }
    }

    # === Step 2: 安裝前連線檢查 ===
    Write-Log "INFO" "[Step 2/4] 檢查 PCE 連線"

    if ($SkipTlsCheck) {
        Write-Log "SKIP" "已指定略過連線檢查。"
    } else {
        $curl = Join-Path $env:SystemRoot "System32\curl.exe"
        if (Test-Path -LiteralPath $curl) {
            # curl.exe (Windows 10 1803+ / Server 2019+ 內建) 走 Schannel 與系統憑證存放區，可同時驗證信任鏈
            Invoke-Logged "curl" $curl @("-sS", "-o", "NUL", "--connect-timeout", "10", "--max-time", "30", "https://$ManagementServer/")
            $curlRc = $LASTEXITCODE
            if ($curlRc -eq 0) {
                Write-Log "OK" "已與 $ManagementServer 完成 TLS 握手，憑證受信任。"
            } elseif (@(35, 51, 53, 54, 58, 59, 60, 77, 83, 90, 91) -contains $curlRc) {
                Stop-Deploy 7 "無法驗證 PCE 憑證 (curl 結束碼 $curlRc)。請提供簽發 PCE 憑證的 CA (-CertFile)，並確認路徑上沒有 TLS 攔截。"
            } else {
                Stop-Deploy 7 "無法連線至 $ManagementServer (curl 結束碼 $curlRc)。請檢查 DNS、防火牆與 Proxy 設定。"
            }
        } else {
            # 較舊的系統沒有 curl.exe，只檢查 TCP 埠是否可達
            $reachable = Test-NetConnection -ComputerName $pceHost -Port $pcePort -InformationLevel Quiet -WarningAction SilentlyContinue
            if (-not $reachable) {
                Stop-Deploy 7 "無法連線至 $ManagementServer。請檢查 DNS 與防火牆設定。"
            }
            Write-Log "OK" "TCP 埠可連線 (此系統無 curl.exe，未驗證憑證信任鏈)。"
        }
    }

    # === Step 3: 安裝 VEN ===
    Write-Log "INFO" "[Step 3/4] 安裝 VEN"

    # VEN 24.2.10 起提供 illumio-ven-ctl.exe；23.5 以前為 illumio-ven-ctl.ps1
    function Find-VenCtl {
        foreach ($dir in @($InstallDir, $DefaultInstallDir)) {
            foreach ($name in @("illumio-ven-ctl.exe", "illumio-ven-ctl.ps1")) {
                $candidate = Join-Path $dir $name
                if (Test-FileExists $candidate) { return $candidate }
            }
        }
        return ""
    }

    $rebootRequired = $false
    $venCtl = Find-VenCtl
    if ($venCtl) {
        Write-Log "SKIP" "VEN 已安裝 ($venCtl)，跳過安裝。"
    } else {
        $pkgDir = $SourceDir
        if (-not $pkgDir) { $pkgDir = $PSScriptRoot }

        if (-not $ExeFile) {
            $found = @(Get-ChildItem -LiteralPath $pkgDir -Filter "*illumio-ven*.exe" -ErrorAction SilentlyContinue)
            if ($found.Count -eq 0) { Stop-Deploy 8 "在 $pkgDir 找不到 *illumio-ven*.exe。請放入安裝檔，或用 -ExeFile 指定。" }
            if ($found.Count -gt 1) {
                $found | ForEach-Object { Write-Log "ERROR" "  候選: $($_.Name)" }
                Stop-Deploy 8 "在 $pkgDir 找到多個安裝檔，無法判斷要裝哪一個。請用 -ExeFile 指定。"
            }
            $ExeFile = $found[0].Name
        }
        $installerPath = Join-Path $pkgDir $ExeFile
        if (-not (Test-Path -LiteralPath $installerPath)) { Stop-Deploy 8 "找不到安裝檔: $installerPath" }

        $installerLog = Join-Path $env:TEMP "IllumioVENInstall.log"
        $installArgs = @("/install", "/quiet", "/norestart", "/log", "`"$installerLog`"")
        # INSTALLFOLDER 與 DATAFOLDER 是獨立的安裝屬性，各自非預設值時才傳入
        if ($InstallDir -ne $DefaultInstallDir) { $installArgs += "INSTALLFOLDER=`"$InstallDir`"" }
        if ($DataDir -ne $DefaultDataDir) { $installArgs += "DATAFOLDER=`"$DataDir`"" }

        Write-Log "INFO" "安裝: $installerPath"
        $proc = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru
        if ($proc.ExitCode -eq 3010) {
            $rebootRequired = $true
            Write-Log "OK" "VEN 安裝完成 (安裝程式回報需要重新開機)。"
        } elseif ($proc.ExitCode -ne 0) {
            Stop-Deploy 8 "安裝失敗 (安裝程式結束碼 $($proc.ExitCode))。詳見: $installerLog"
        } else {
            Write-Log "OK" "VEN 安裝完成。"
        }

        $venCtl = Find-VenCtl
        if (-not $venCtl) { Stop-Deploy 8 "安裝後仍找不到 illumio-ven-ctl。詳見: $installerLog" }
    }

    # === Step 4: 啟用 ===
    Write-Log "INFO" "[Step 4/4] 向 PCE 啟用"

    # 已配對的 VEN 會在資料目錄留下 agent_id.cfg；再次 activate 會失敗，故直接跳過
    $activated = $false
    foreach ($dir in @($DataDir, $DefaultDataDir)) {
        if (Test-FileExists (Join-Path $dir "etc\agent_id.cfg")) { $activated = $true }
    }

    if ($activated) {
        Write-Log "SKIP" "VEN 已啟用，跳過啟用。"
    } else {
        Write-Log "INFO" "PCE: $ManagementServer"
        Invoke-Logged "ven-ctl" $venCtl @("activate", "-activation-code", $ActivationCode, "-management-server", $ManagementServer)
        if ($LASTEXITCODE -ne 0) {
            Stop-Deploy 9 "啟用失敗 (結束碼 $LASTEXITCODE)。請確認啟用碼有效且未超過使用次數。"
        }
        Write-Log "OK" "啟用完成。"
    }

    if ($rebootRequired) {
        Write-Log "OK" "部署完成，需要重新開機 (結束碼 3010)。"
        exit 3010
    }
    Write-Log "OK" "部署完成。"
    exit 0

} catch {
    Write-Log "ERROR" "未預期的錯誤: $_"
    exit 1
}
