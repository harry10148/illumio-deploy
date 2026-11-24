# Deploy-Illumio.ps1 / deploy-illumio.bat — Windows 完整部署

匯入 CA 憑證、檢查 PCE 連線、靜默安裝 VEN、啟用，一次完成。不需互動，可重複執行。兩支腳本流程相同，擇一使用。

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Deploy-Illumio.ps1 `
    -ManagementServer <PCE_FQDN>:<PORT> -ActivationCode <ACTIVATION_CODE>
```

```cmd
set ILLUMIO_MANAGEMENT_SERVER=<PCE_FQDN>:<PORT>
set ILLUMIO_ACTIVATION_CODE=<ACTIVATION_CODE>
cmd.exe /c deploy-illumio.bat
```

- CA 憑證：放在腳本同目錄並命名為 `illumio-ca.crt`（PowerShell 版也可用 `-CertFile`）。PCE 使用公開 CA 或憑證已由群組原則派發時不必提供。
- 安裝檔：放在腳本同目錄；沒有時腳本會向 PCE 下載。
- `deploy-illumio.bat` 不呼叫 PowerShell，適用於封鎖 PowerShell 的環境。
- 日誌：`%TEMP%\IllumioDeploy.log`（以 SYSTEM 執行時為 `C:\Windows\Temp`）

完整說明（參數、自訂目錄、各 Windows 版本的差異、解除安裝、疑難排解）見 [Windows 安裝](../../docs/ven/install-windows.md)。
SCCM、Intune、群組原則的接法與結束碼見 [大規模派送](../../docs/ven/mass-deployment.md)。
