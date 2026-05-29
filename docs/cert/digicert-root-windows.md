> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/DigiCert_Global_Root_windows.txt`

# DigiCert Global Root CA 匯入（Windows）

## 1. 目的與適用情境

將 DigiCert Global Root G2 與 G3 根憑證匯入 Windows Server / Windows 10 / Windows 11 的本機電腦「受信任的根憑證授權單位」存放區，確保系統與 VEN 能信任 DigiCert 簽發的憑證鏈；包含有網路與 Air-Gapped 離線兩種方案，以及 VEN 重啟流程。

## 2. 前置條件

- 以「系統管理員身分執行」PowerShell（必須，否則寫入 LocalMachine\Root 會因權限不足失敗）
- 憑證將匯入 Local Machine 的「受信任的根憑證授權單位」存放區

## 3. 操作步驟

### 方案 A — 有網際網路連線

```powershell
Import-Module PKI

# --- DigiCert Global Root G2 ---
$g2Path = Join-Path $env:TEMP 'DigiCertGlobalRootG2.pem'
Invoke-WebRequest -UseBasicParsing `
    -Uri 'https://cacerts.digicert.com/DigiCertGlobalRootG2.crt.pem' `
    -OutFile $g2Path
Import-Certificate -FilePath $g2Path `
    -CertStoreLocation 'Cert:\LocalMachine\Root'

# --- DigiCert Global Root G3 ---
$g3Path = Join-Path $env:TEMP 'DigiCertGlobalRootG3.pem'
Invoke-WebRequest -UseBasicParsing `
    -Uri 'https://cacerts.digicert.com/DigiCertGlobalRootG3.crt.pem' `
    -OutFile $g3Path
Import-Certificate -FilePath $g3Path `
    -CertStoreLocation 'Cert:\LocalMachine\Root'
```

### 方案 B — 無網際網路連線 / Air-Gapped

```powershell
Import-Module PKI

# --- DigiCert Global Root G2 ---
@'
-----BEGIN CERTIFICATE-----
MIIDjjCCAnagAwIBAgIQAzrx5qcRqaC7KGSxHQn65TANBgkqhkiG9w0BAQsFADBh
MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
d3cuZGlnaWNlcnQuY29tMSAwHgYDVQQDExdEaWdpQ2VydCBHbG9iYWwgUm9vdCBH
MjAeFw0xMzA4MDExMjAwMDBaFw0zODAxMTUxMjAwMDBaMGExCzAJBgNVBAYTAlVT
MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
b20xIDAeBgNVBAMTF0RpZ2lDZXJ0IEdsb2JhbCBSb290IEcyMIIBIjANBgkqhkiG
9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuzfNNNx7a8myaJCtSnX/RrohCgiN9RlUyfuI
2/Ou8jqJkTx65qsGGmvPrC3oXgkkRLpimn7Wo6h+4FR1IAWsULecYxpsMNzaHxmx
1x7e/dfgy5SDN67sH0NO3Xss0r0upS/kqbitOtSZpLYl6ZtrAGCSYP9PIUkY92eQ
q2EGnI/yuum06ZIya7XzV+hdG82MHauVBJVJ8zUtluNJbd134/tJS7SsVQepj5Wz
tCO7TG1F8PapspUwtP1MVYwnSlcUfIKdzXOS0xZKBgyMUNGPHgm+F6HmIcr9g+UQ
vIOlCsRnKPZzFBQ9RnbDhxSJITRNrw9FDKZJobq7nMWxM4MphQIDAQABo0IwQDAP
BgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNVHQ4EFgQUTiJUIBiV
5uNu5g/6+rkS7QYXjzkwDQYJKoZIhvcNAQELBQADggEBAGBnKJRvDkhj6zHd6mcY
1Yl9PMWLSn/pvtsrF9+wX3N3KjITOYFnQoQj8kVnNeyIv/iPsGEMNKSuIEyExtv4
NeF22d+mQrvHRAiGfzZ0JFrabA0UWTW98kndth/Jsw1HKj2ZL7tcu7XUIOGZX1NG
Fdtom/DzMNU+MeKNhJ7jitralj41E6Vf8PlwUHBHQRFXGU7Aj64GxJUTFy8bJZ91
8rGOmaFvE7FBcf6IKshPECBV1/MUReXgRPTqh5Uykw7+U0b6LJ3/iyK5S9kJRaTe
pLiaWN0bfVKfjllDiIGknibVb63dDcY3fe0Dkhvld1927jyNxF1WW6LZZm6zNTfl
MrY=
-----END CERTIFICATE-----
'@ | Set-Content -Encoding ascii "$env:TEMP\DigiCertGlobalRootG2.pem"

Import-Certificate -FilePath "$env:TEMP\DigiCertGlobalRootG2.pem" `
    -CertStoreLocation "Cert:\LocalMachine\Root"


# --- DigiCert Global Root G3 ---
@'
-----BEGIN CERTIFICATE-----
MIICPzCCAcWgAwIBAgIQBVVWvPJepDU1w6QP1atFcjAKBggqhkjOPQQDAzBhMQsw
CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
ZGlnaWNlcnQuY29tMSAwHgYDVQQDExdEaWdpQ2VydCBHbG9iYWwgUm9vdCBHMzAe
Fw0xMzA4MDExMjAwMDBaFw0zODAxMTUxMjAwMDBaMGExCzAJBgNVBAYTAlVTMRUw
EwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20x
IDAeBgNVBAMTF0RpZ2lDZXJ0IEdsb2JhbCBSb290IEczMHYwEAYHKoZIzj0CAQYF
K4EEACIDYgAE3afZu4q4C/sLfyHS8L6+c/MzXRq8NOrexpu80JX28MzQC7phW1FG
fp4tn+6OYwwX7Adw9c+ELkCDnOg/QW07rdOkFFk2eJ0DQ+4QE2xy3q6Ip6FrtUPO
Z9wj/wMco+I+o0IwQDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAd
BgNVHQ4EFgQUs9tIpPmhxdiuNkHMEWNpYim8S8YwCgYIKoZIzj0EAwMDaAAwZQIx
AK288mw/EkrRLTnDCgmXc/SINoyIJ7vmiI1Qhadj+Z4y3maTD/HMsQmP3Wyr+mt/
oAIwOWZbwmSNuJ5Q3KjVSaLtx9zRSX8XAbjIho9OjIgrqJqpisXRAL34VOKa5Vt8
sycX
-----END CERTIFICATE-----
'@ | Set-Content -Encoding ascii "$env:TEMP\DigiCertGlobalRootG3.pem"

Import-Certificate -FilePath "$env:TEMP\DigiCertGlobalRootG3.pem" `
    -CertStoreLocation "Cert:\LocalMachine\Root"
```

### Illumio VEN 重啟流程

```powershell
# 1. 重命名 ca-bundle.crt，強制 VEN 啟動時重新匯出憑證
Rename-Item 'C:\ProgramData\Illumio\etc\ca-bundle.crt' `
            'C:\ProgramData\Illumio\etc\ca-bundle.crt.old'

# 2. 重啟 VEN
& 'C:\Program Files\Illumio\illumio-ven-ctl.ps1' restart
```

## 4. 驗證

```powershell
# 查詢 LocalMachine\Root 存放區中的 DigiCert Global Root G2 / G3
Get-ChildItem -Path Cert:\LocalMachine\Root |
    Where-Object { $_.Subject -like "*DigiCert Global Root G*" } |
    Select-Object Subject, Thumbprint, NotAfter | Format-List

# 預期 Thumbprint（可用來比對）：
#   G2:  DF3C24F9BFD666761B268073FE06D1CC8D4F82A4
#   G3:  7E04DE896A3E666D00E687D33FFAD93BE83D349E
```

## 5. 失敗回滾 / 救援

- — 無 —

若 `Invoke-WebRequest` 因 TLS 問題無法連線到 `cacerts.digicert.com`，改用方案 B（Air-Gapped 內嵌 PEM）。

若 `Rename-Item` 因目的檔名已存在而失敗，先執行：

```powershell
if (Test-Path 'C:\ProgramData\Illumio\etc\ca-bundle.crt.old') {
    Remove-Item 'C:\ProgramData\Illumio\etc\ca-bundle.crt.old' -Force
}
```

## 6. 原廠文件參照

- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Set up Certificates on Workloads > Installation Locations — CA 憑證需匯入 Windows LocalMachine Trusted Root 存放區，使用 MMC 或憑證匯入精靈
- [NotebookLM] Illumio Agent部署手冊_20250815.pdf §8.1 憑證錯誤(Error:408) — Windows 憑證匯入精靈圖示說明，選擇「本機電腦」→「受信任的根憑證授權單位」
- [Web] https://cacerts.digicert.com/DigiCertGlobalRootG2.crt.pem — DigiCert Global Root G2 官方下載
- [Web] https://cacerts.digicert.com/DigiCertGlobalRootG3.crt.pem — DigiCert Global Root G3 官方下載

## 7. 與原廠差異（若有）

- **PowerShell Import-Certificate**：SOP 使用 Import-Certificate -CertStoreLocation Cert:\LocalMachine\Root，比原廠建議的 MMC GUI 方式更適合自動化，功能一致。
- **VEN ca-bundle.crt 重啟流程**：SOP 包含 Rename-Item ca-bundle.crt.old + illumio-ven-ctl.ps1 restart，原廠文件未明確記錄，SOP 補強合理。
- **DigiCert 特定憑證**：原廠未指定需安裝 DigiCert 根 CA；此 SOP 針對企業環境使用 DigiCert 簽發憑證的特定場景，屬環境適配補強。
