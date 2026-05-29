> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/illumio_ven_win_install.txt`

# Illumio VEN — Windows 手動安裝

## 1. 目的與適用情境

在 Windows 主機上使用 PowerShell 手動安裝 Illumio VEN，包含 CA 憑證匯入至本機電腦信任區、腳本安裝及手動啟用指令，適用於無法使用自動化部署腳本或需逐步驗證的部署場景。

自動化版本見 [`../../windows/manual_deploy/Deploy-Illumio.ps1`](../../windows/manual_deploy/Deploy-Illumio.ps1)。

## 2. 前置條件

- 以「系統管理員身分」開啟 Windows PowerShell（必須，否則沒有權限寫入系統憑證區）
- 主機能解析 PCE FQDN 且防火牆允許連線至 TCP 8443
- 已取得有效的 Activation Code 及 PCE FQDN

## 3. 操作步驟

### 事前準備

1. 按下 Windows 鍵，搜尋 "PowerShell"。
2. 在 "Windows PowerShell" 上按右鍵，選擇「以系統管理員身分執行」。

### [1] CA 憑證一鍵匯入（PowerShell）

```powershell
# 1. 定義憑證內容
$certContent = @"
-----BEGIN CERTIFICATE-----
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
ZpUPoUdMJg==
-----END CERTIFICATE-----
"@

# 2. 儲存為暫存檔案 (使用 ASCII 編碼避免格式問題)
$tempCertPath = "$env:TEMP\illumio-ca.crt"
Set-Content -Path $tempCertPath -Value $certContent -Encoding Ascii

# 3. 匯入憑證到「本機電腦 (LocalMachine)」的「根 (Root)」存放區
Import-Certificate -FilePath $tempCertPath -CertStoreLocation Cert:\LocalMachine\Root

# 4. 刪除暫存檔 (可選)
Remove-Item -Path $tempCertPath

# 顯示完成訊息
Write-Host "憑證匯入作業已執行。" -ForegroundColor Green
```

### [2] 驗證指令

```powershell
# 方法 A: 檢查憑證庫是否確實包含該憑證
# 說明: 在本機根憑證區搜尋主旨包含 "illumio" 的憑證
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*illumio*" }

# 預期結果: 應顯示 Thumbprint (指紋) 與 Subject (主旨: CN=illumioCA...)


# 方法 B: 使用 Curl 測試連線
# 說明: Windows 10 (1803+) 和 Windows 11 內建 curl.exe
# 請將 <Target_URL> 替換為實際網址
curl.exe -v https://<Target_URL>

# 預期結果:
# 1. 看到 "*  SSL certificate verify ok"
# 2. 若失敗會顯示 "Schannel: SEC_E_UNTRUSTED_ROOT" (代表憑證不受信任)

# 注意: 若使用 PowerShell 的 Invoke-WebRequest (iwr) 指令:
# Invoke-WebRequest https://<Target_URL>
# 成功會回傳 200 OK 的物件；失敗則會直接拋出紅字錯誤訊息。
```

### [3.1] 腳本安裝指令

```powershell
PowerShell -Command "& {Set-ExecutionPolicy -Scope process remotesigned -Force; Start-Sleep -s 3; Set-Variable -Name ErrorActionPreference -Value SilentlyContinue; [System.Net.ServicePointManager]::SecurityProtocol=[Enum]::ToObject([System.Net.SecurityProtocolType], 3072); Set-Variable -Name ErrorActionPreference -Value Continue; (New-Object System.Net.WebClient).DownloadFile('https://<PCE_FQDN>:<PORT>/api/v27/software/ven/image?pair_script=pair.ps1&profile_id=<PROFILE_ID>', (echo $env:windir\temp\pair.ps1)); & $env:windir\temp\pair.ps1 -management-server <PCE_FQDN>:<PORT> -activation-code <YOUR_ACTIVATION_CODE>;}"
```

### [3.2] 手動安裝後執行回報指令

```powershell
& "C:\Program Files\Illumio\illumio-ven-ctl.exe" activate -activation-code <activation_code> -management-server <pce_fqdn:pce_portnumber>
```

## 4. 驗證

```powershell
# 確認憑證已匯入
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*illumio*" }

# 確認 VEN 連線
curl.exe -v https://<PCE_FQDN>:8443
```

## 5. 失敗回滾 / 救援

- — 無 —

若 VEN 啟用失敗，確認 PCE FQDN 可解析、TCP 8443 可連通、Activation Code 未過期，並以系統管理員身分重新執行啟用指令。

## 6. 原廠文件參照

- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Windows Pairing Script — PowerShell pair.ps1 下載與執行（SetExecutionPolicy、TLS 1.2、WebClient DownloadFile、-management-server、-activation-code）
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Windows: Install and Upgrade with CLI and VEN CTL > Windows VEN Activation After Installation — 手動安裝後 illumio-ven-ctl.exe activate（VEN 24.2.10+）或 .ps1（23.5 及更早）
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Set up Certificates on Workloads > Installation Locations — CA 憑證需匯入 LocalMachine Trusted Root 存放區（非 User 層級）
- [NotebookLM] Illumio Agent部署手冊_20250815.pdf §8.1 憑證錯誤(Error:408) — Windows 憑證匯入精靈操作說明

## 7. 與原廠差異（若有）

- **PowerShell CA 匯入方式**：SOP 使用 Import-Certificate -CertStoreLocation Cert:\LocalMachine\Root，原廠建議使用 MMC 或憑證匯入精靈 GUI，功能一致，SOP 的 PowerShell 方式更適合自動化部署。
- **VEN ctl 指令版本差異**：SOP 使用 illumio-ven-ctl.exe（適用 VEN 24.2.10+），若環境為舊版（23.5-）需改用 .ps1；SOP 應補充版本說明。
- **TLS 協商**：SOP PowerShell 指令設定 SecurityProtocol=3072（TLS 1.2），與原廠 pair.ps1 做法一致。
