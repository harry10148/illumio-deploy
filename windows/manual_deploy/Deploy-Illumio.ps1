<#
.SYNOPSIS
    Illumio VEN 完整部署 (Windows / PowerShell)

.DESCRIPTION
    1. 匯入 PCE 的 CA 憑證 (未提供憑證則跳過，改用系統既有信任)
    2. 安裝前檢查到 PCE 的連線 (不通即停止，不留下半套安裝)
    3. 靜默安裝 VEN (已安裝則跳過)；本機沒有安裝檔時，向 PCE 下載並驗證 SHA256
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
    安裝檔檔名。預設: 自動尋找 *illumio-ven*.exe；找不到則向 PCE 下載。

.PARAMETER NoDownload
    本機沒有安裝檔時不向 PCE 下載，直接失敗。

.PARAMETER ApiVersion
    下載安裝檔使用的 PCE API 版本。預設: v25 (較新的 PCE 仍接受較舊的版本)

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
      (8 也包含找不到安裝檔與下載失敗)
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
    [switch]$SkipTlsCheck,
    [switch]$NoDownload,
    [string]$ApiVersion       = "v25"
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

# 以 certutil 計算憑證指紋 (PEM 轉 DER 後取 SHA1)。全程不需互動；
# Get-PfxCertificate 遇到無效內容會停在密碼提示，不能用於無人值守。
function Get-CertThumbprint {
    param([string]$Path)
    $der = Join-Path $WorkDir "illumio-ca.der"
    Remove-Item -LiteralPath $der -Force -ErrorAction SilentlyContinue
    & certutil.exe -decode $Path $der | Out-Null
    $src = $der
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $der)) { $src = $Path }   # 已是 DER 格式
    $lines = @(& certutil.exe -hashfile $src SHA1)
    Remove-Item -LiteralPath $der -Force -ErrorAction SilentlyContinue
    if ($lines.Count -lt 2) { return "" }
    $thumb = ($lines[1] -replace '[^0-9A-Fa-f]', '').ToUpper()
    if ($thumb.Length -ne 40) { return "" }
    return $thumb
}

# 私有工作目錄：只有 SYSTEM 與 Administrators 可存取，避免暫存的憑證或安裝檔
# 在驗證後、使用前被其他本機帳號置換
$WorkDir = ""
function New-WorkDir {
    $dir = Join-Path $env:TEMP ("illumio-deploy-{0}-{1}-{2}" -f $PID, (Get-Random), (Get-Random))
    New-Item -ItemType Directory -Path $dir | Out-Null      # 目錄已存在時會失敗，不沿用既有目錄
    & icacls.exe $dir /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "無法設定工作目錄的存取權限: $dir" }
    return $dir
}
function Remove-WorkDir {
    if ($WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}

function Stop-Deploy {
    param([int]$Code, [string]$Message)
    Remove-WorkDir
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
    if ($ApiVersion -notmatch '^v[0-9]+$') { Stop-Deploy 2 "-ApiVersion 格式應為 vNN (例如 v25)，目前為: $ApiVersion" }
    $pceHost, $pcePort = $ManagementServer -split ":"
    $WorkDir = New-WorkDir
    $curl = Join-Path $env:SystemRoot "System32\curl.exe"

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
        $tempCertPath = Join-Path $WorkDir "illumio-ca-embedded.crt"
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
        $thumbprint = Get-CertThumbprint $certPath
        if ($thumbprint -and (Test-Path -LiteralPath "Cert:\LocalMachine\Root\$thumbprint")) {
            Write-Log "SKIP" "憑證已存在於受信任的根憑證授權單位 (Thumbprint: $thumbprint)。"
        } else {
            Invoke-Logged "certutil" "certutil.exe" @("-addstore", "Root", $certPath)
            if ($LASTEXITCODE -ne 0) { Stop-Deploy 6 "憑證匯入失敗 (憑證內容無效，或權限不足)。" }
            Write-Log "OK" "憑證已匯入 (Thumbprint: $thumbprint)。"
        }
    }

    # === Step 2: 安裝前連線檢查 ===
    Write-Log "INFO" "[Step 2/4] 檢查 PCE 連線"

    if ($SkipTlsCheck) {
        Write-Log "SKIP" "已指定略過連線檢查。"
    } else {
        if (Test-Path -LiteralPath $curl) {
            # curl.exe (Windows 10 1803+ / Server 2019+ 內建) 走 Schannel 與系統憑證存放區，可同時驗證信任鏈
            # --ssl-no-revoke：私有 CA 通常沒有可連線的撤銷清單，Schannel 預設會因此拒絕連線
            Invoke-Logged "curl" $curl @("-sS", "--ssl-no-revoke", "-o", "NUL", "--connect-timeout", "10", "--max-time", "30", "https://$ManagementServer/")
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
    # VEN 安裝後會把實際路徑寫入 HKLM\SOFTWARE\Illumio，重跑時不必再給自訂目錄參數
    $regInstall = ""; $regData = ""
    $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Illumio" -ErrorAction SilentlyContinue
    if ($reg) { $regInstall = "$($reg.InstallPath)"; $regData = "$($reg.DataPath)" }

    function Find-VenCtl {
        foreach ($dir in @($regInstall, $InstallDir, $DefaultInstallDir)) {
            if (-not $dir) { continue }
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

        $installerPath = ""
        if ($ExeFile) {
            $installerPath = Join-Path $pkgDir $ExeFile
            if (-not (Test-FileExists $installerPath)) { Stop-Deploy 8 "找不到安裝檔: $installerPath" }
        } else {
            $found = @(Get-ChildItem -LiteralPath $pkgDir -Filter "*illumio-ven*.exe" -ErrorAction SilentlyContinue)
            if ($found.Count -gt 1) {
                $found | ForEach-Object { Write-Log "ERROR" "  候選: $($_.Name)" }
                Stop-Deploy 8 "在 $pkgDir 找到多個安裝檔，無法判斷要裝哪一個。請用 -ExeFile 指定。"
            }
            if ($found.Count -eq 1) { $installerPath = $found[0].FullName }
        }

        if (-not $installerPath) {
            if ($NoDownload) { Stop-Deploy 8 "在 $pkgDir 找不到 *illumio-ven*.exe (已指定 -NoDownload)。" }
            # 與官方 pair.ps1 相同的機制：以啟用碼向 PCE 的 VEN Library 取得符合本機的安裝檔
            $arch = $env:PROCESSOR_ARCHITECTURE
            if ($arch -eq "AMD64") { $arch = "x64" }
            $osParts = (Get-CimInstance -ClassName Win32_OperatingSystem).Version -split "\."
            $osVer = "$($osParts[0]).$($osParts[1])"
            $dlFile = Join-Path $WorkDir "illumio-ven-download.tmp"
            $dlHeaders = Join-Path $WorkDir "illumio-ven-download.headers"
            $url = "https://$ManagementServer/api/$ApiVersion/software/ven/image?architecture=$arch&distribution=Windows&version=$osVer"
            Write-Log "INFO" "本機沒有安裝檔，向 PCE 下載 [$arch][Windows][$osVer]"

            $expectedSha = ""
            $dlName = ""
            if (Test-FileExists $curl) {
                $httpCode = & $curl -sS --ssl-no-revoke --user "agent_0:$ActivationCode" --connect-timeout 10 --max-time 900 -D $dlHeaders -o $dlFile -w "%{http_code}" $url
                if ($httpCode -ne "200") {
                    Remove-Item -LiteralPath $dlFile, $dlHeaders -Force -ErrorAction SilentlyContinue
                    if ($httpCode -eq "401" -or $httpCode -eq "403") { Stop-Deploy 8 "PCE 拒絕下載 (HTTP $httpCode)。請確認啟用碼有效且未過期。" }
                    if ($httpCode -eq "406") { Stop-Deploy 8 "PCE 沒有符合 [$arch][Windows][$osVer] 的安裝檔，或啟用碼無效。請確認啟用碼，或自行提供安裝檔 (-ExeFile)。" }
                    Stop-Deploy 8 "安裝檔下載失敗 (HTTP $httpCode)。"
                }
                $shaLine = Select-String -LiteralPath $dlHeaders -Pattern '^x-sha256:\s*([0-9A-Fa-f]+)' | Select-Object -First 1
                $nameLine = Select-String -LiteralPath $dlHeaders -Pattern '^content-disposition:.*filename="?([^";]+)' | Select-Object -First 1
                Remove-Item -LiteralPath $dlHeaders -Force -ErrorAction SilentlyContinue
                if ($shaLine) { $expectedSha = $shaLine.Matches[0].Groups[1].Value }
                if ($nameLine) { $dlName = $nameLine.Matches[0].Groups[1].Value }
            } elseif ($ExecutionContext.SessionState.LanguageMode -eq "FullLanguage") {
                # Windows Server 2016 以前沒有 curl.exe：改用 .NET WebClient (官方 pair.ps1 的做法)。
                # 這段會用到 .NET 型別，受限語言模式下無法執行。
                try {
                    [System.Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([System.Net.SecurityProtocolType], 3072)
                    $wc = New-Object System.Net.WebClient
                    $basic = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("agent_0:" + $ActivationCode))
                    $wc.Headers.Add("Authorization", "Basic " + $basic)
                    $wc.DownloadFile($url, $dlFile)
                    $expectedSha = $wc.ResponseHeaders["X-SHA256"]
                    $dlName = ($wc.ResponseHeaders["Content-Disposition"] -split "filename=")[1]
                } catch {
                    Remove-Item -LiteralPath $dlFile -Force -ErrorAction SilentlyContinue
                    Stop-Deploy 8 "安裝檔下載失敗: $($_.Exception.Message) (401/406 = 啟用碼無效，或 PCE 沒有符合本機的安裝檔)"
                }
            } else {
                Stop-Deploy 8 "此系統沒有 curl.exe，且 PowerShell 處於受限語言模式，無法向 PCE 下載。請自行提供安裝檔 (-ExeFile)。"
            }

            if (-not $expectedSha -or -not $dlName) {
                Remove-Item -LiteralPath $dlFile -Force -ErrorAction SilentlyContinue
                Stop-Deploy 8 "PCE 回應缺少檔名或 SHA256 標頭，無法驗證安裝檔。"
            }
            $dlName = Split-Path -Leaf ($dlName -replace '"', '').Trim()
            # 先改成最終檔名再驗證，執行的就是剛驗證過的那個檔案
            $installerPath = Join-Path $WorkDir $dlName
            Move-Item -LiteralPath $dlFile -Destination $installerPath -Force
            $actualSha = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
            if ($actualSha -ne $expectedSha) {
                Stop-Deploy 8 "安裝檔 SHA256 不符 (預期 $expectedSha，實際 $actualSha)。"
            }
            Write-Log "OK" "已下載並通過 SHA256 驗證: $dlName"
        }

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
    $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Illumio" -ErrorAction SilentlyContinue
    if ($reg) { $regData = "$($reg.DataPath)" }
    foreach ($dir in @($regData, $DataDir, $DefaultDataDir)) {
        if ($dir -and (Test-FileExists (Join-Path $dir "etc\agent_id.cfg"))) { $activated = $true }
    }

    if ($activated) {
        Write-Log "SKIP" "VEN 已啟用，跳過啟用。"
    } else {
        Write-Log "INFO" "PCE: $ManagementServer"
        $activateArgs = @("activate", "-activation-code", $ActivationCode, "-management-server", $ManagementServer)
        if ($venCtl -like "*.ps1") {
            # VEN 23.5 以前只有 illumio-ven-ctl.ps1：另起 powershell.exe 執行，參數才會照命令列解析，結束碼也才可靠
            Invoke-Logged "ven-ctl" "powershell.exe" (@("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $venCtl) + $activateArgs)
        } else {
            Invoke-Logged "ven-ctl" $venCtl $activateArgs
        }
        if ($LASTEXITCODE -ne 0) {
            Stop-Deploy 9 "啟用失敗 (結束碼 $LASTEXITCODE)。請確認啟用碼有效且未超過使用次數。"
        }
        Write-Log "OK" "啟用完成。"
    }

    Remove-WorkDir
    if ($rebootRequired) {
        Write-Log "OK" "部署完成，需要重新開機 (結束碼 3010)。"
        exit 3010
    }
    Write-Log "OK" "部署完成。"
    exit 0

} catch {
    Remove-WorkDir
    Write-Log "ERROR" "未預期的錯誤: $_"
    exit 1
}
