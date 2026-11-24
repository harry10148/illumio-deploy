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

function Stop-Import {
    param([int]$Code, [string]$Message)
    Write-Output "[ERROR] $Message"
    exit $Code
}

$tempCertPath = ""
try {
    Write-Output "==== Illumio CA 憑證匯入 ===="

    # 權限檢查：High (S-1-16-12288) 或 System (S-1-16-16384) 完整性等級。
    # 用 whoami 而非 .NET 型別，才能在 Constrained Language Mode 下執行。
    $groups = (& whoami.exe /groups) -join "`n"
    if ($groups -notmatch "S-1-16-12288" -and $groups -notmatch "S-1-16-16384") {
        Stop-Import 3 "需要以系統管理員身分執行。"
    }

    # 憑證來源優先序: -CertFile > 同目錄 illumio-ca.crt > 內嵌憑證
    $certPath = ""
    $localCertPath = Join-Path $PSScriptRoot "illumio-ca.crt"
    if ($CertFile) {
        if (-not (Test-Path -LiteralPath $CertFile)) { Stop-Import 6 "指定的憑證檔不存在: $CertFile" }
        $certPath = $CertFile
    } elseif (Test-Path -LiteralPath $localCertPath) {
        $certPath = $localCertPath
    } elseif ($EmbeddedCertContent -notlike "*PLACEHOLDER_CERTIFICATE_CONTENT*") {
        $tempCertPath = Join-Path $env:TEMP "illumio-ca-embedded.crt"
        Set-Content -Path $tempCertPath -Value $EmbeddedCertContent -Encoding Ascii
        $certPath = $tempCertPath
    }
    if (-not $certPath) {
        Stop-Import 6 "未提供 CA 憑證。請用 -CertFile 指定，或將 illumio-ca.crt 放在腳本同目錄。"
    }

    Write-Output "[INFO] 憑證來源: $certPath"
    if ((Get-Content -LiteralPath $certPath -Raw) -like "*PLACEHOLDER_CERTIFICATE_CONTENT*") {
        Stop-Import 6 "憑證檔內容仍為佔位符。"
    }

    try {
        $cert = Get-PfxCertificate -FilePath $certPath
    } catch {
        Stop-Import 6 "憑證內容無法解析為有效的 X.509 憑證: $_"
    }
    $thumbprint = $cert.Thumbprint
    Write-Output "[INFO] Thumbprint: $thumbprint"
    Write-Output "[INFO] Subject:    $($cert.Subject)"

    if (Test-Path -LiteralPath "Cert:\LocalMachine\Root\$thumbprint") {
        Write-Output "[SKIP] 憑證已存在於受信任的根憑證授權單位，無須重複匯入。"
    } else {
        try {
            Import-Certificate -FilePath $certPath -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
        } catch {
            Stop-Import 6 "憑證匯入失敗: $_"
        }
        Write-Output "[OK] 憑證已匯入受信任的根憑證授權單位。"
    }

    Write-Output "[OK] 接著請至 PCE Web Console 的 Pairing Profile 複製配對指令，在本機執行。"
    exit 0

} catch {
    Write-Output "[ERROR] 未預期的錯誤: $_"
    exit 1
} finally {
    if ($tempCertPath) { Remove-Item -LiteralPath $tempCertPath -Force -ErrorAction SilentlyContinue }
}
