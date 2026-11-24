<#
.SYNOPSIS
    Illumio VEN 方式一前置作業 (Windows)：匯入 PCE 的 CA 憑證

.DESCRIPTION
    將 CA 憑證匯入「本機電腦\受信任的根憑證授權單位」。已存在相同憑證時跳過。
    在執行 Illumio 官方配對腳本 (pair.ps1) 之前使用。

    可重複執行、全程不需互動。只使用 Windows 內建指令；
    可在 Constrained Language Mode 下執行。

.PARAMETER CertFile
    CA 憑證 (PEM)。預設: 腳本同目錄 illumio-ca.crt，其次內嵌憑證。

.EXAMPLE
    .\Import-RootCA.ps1
    .\Import-RootCA.ps1 -CertFile "C:\certs\illumio-ca.crt"

.NOTES
    結束碼: 0 成功   1 未預期的錯誤   3 權限不足   6 未提供憑證、憑證無效或匯入失敗
#>

param(
    [string]$CertFile = ""
)

$ErrorActionPreference = "Stop"

# 內嵌憑證 (選用)。保留佔位符 = 不使用內嵌憑證。
$EmbeddedCertContent = @"
-----BEGIN CERTIFICATE-----
PLACEHOLDER_CERTIFICATE_CONTENT_REPLACE_WITH_YOUR_ACTUAL_CERTIFICATE
-----END CERTIFICATE-----
"@

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

function Stop-Import {
    param([int]$Code, [string]$Message)
    if ($WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Output "[ERROR] $Message"
    exit $Code
}

# 私有工作目錄：只有 SYSTEM 與 Administrators 可存取，避免暫存的憑證在匯入前被置換
$WorkDir = ""
try {
    Write-Output "==== Illumio CA 憑證匯入 ===="

    # 權限檢查：High (S-1-16-12288) 或 System (S-1-16-16384) 完整性等級。
    # 用 whoami 而非 .NET 型別，才能在 Constrained Language Mode 下執行。
    $groups = (& whoami.exe /groups) -join "`n"
    if ($groups -notmatch "S-1-16-12288" -and $groups -notmatch "S-1-16-16384") {
        Stop-Import 3 "需要以系統管理員身分執行。"
    }

    $WorkDir = Join-Path $env:TEMP ("illumio-deploy-{0}-{1}-{2}" -f $PID, (Get-Random), (Get-Random))
    New-Item -ItemType Directory -Path $WorkDir | Out-Null      # 目錄已存在時會失敗，不沿用既有目錄
    & icacls.exe $WorkDir /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "無法設定工作目錄的存取權限: $WorkDir" }

    # 憑證來源優先序: -CertFile > 同目錄 illumio-ca.crt > 內嵌憑證
    $certPath = ""
    $localCertPath = Join-Path $PSScriptRoot "illumio-ca.crt"
    if ($CertFile) {
        if (-not (Test-Path -LiteralPath $CertFile)) { Stop-Import 6 "指定的憑證檔不存在: $CertFile" }
        $certPath = $CertFile
    } elseif (Test-Path -LiteralPath $localCertPath) {
        $certPath = $localCertPath
    } elseif ($EmbeddedCertContent -notlike "*PLACEHOLDER_CERTIFICATE_CONTENT*") {
        $certPath = Join-Path $WorkDir "illumio-ca-embedded.crt"
        Set-Content -Path $certPath -Value $EmbeddedCertContent -Encoding Ascii
    }
    if (-not $certPath) {
        Stop-Import 6 "未提供 CA 憑證。請用 -CertFile 指定，或將 illumio-ca.crt 放在腳本同目錄。"
    }

    Write-Output "[INFO] 憑證來源: $certPath"
    if ((Get-Content -LiteralPath $certPath -Raw) -like "*PLACEHOLDER_CERTIFICATE_CONTENT*") {
        Stop-Import 6 "憑證檔內容仍為佔位符。"
    }

    $thumbprint = Get-CertThumbprint $certPath
    Write-Output "[INFO] Thumbprint: $thumbprint"

    if ($thumbprint -and (Test-Path -LiteralPath "Cert:\LocalMachine\Root\$thumbprint")) {
        Write-Output "[SKIP] 憑證已存在於受信任的根憑證授權單位，無須重複匯入。"
    } else {
        & certutil.exe -addstore Root $certPath | ForEach-Object { Write-Output "[INFO] certutil: $_" }
        if ($LASTEXITCODE -ne 0) { Stop-Import 6 "憑證匯入失敗 (憑證內容無效，或權限不足)。" }
        Write-Output "[OK] 憑證已匯入受信任的根憑證授權單位。"
    }

    Write-Output "[OK] 接著請至 PCE Web Console 的 Pairing Profile 複製配對指令，在本機執行。"
    exit 0

} catch {
    Write-Output "[ERROR] 未預期的錯誤: $_"
    exit 1
} finally {
    if ($WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
