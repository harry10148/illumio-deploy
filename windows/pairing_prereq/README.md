# Import-RootCA.ps1 — Windows 官方配對前置

在執行 PCE 產生的配對指令之前，把 PCE 的 CA 憑證匯入「受信任的根憑證授權單位」。本腳本不安裝 VEN。

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Import-RootCA.ps1 -CertFile C:\certs\illumio-ca.crt
```

- 未指定 `-CertFile` 時，使用腳本同目錄的 `illumio-ca.crt`。
- 已存在相同憑證（含群組原則派發的）時跳過。
- 結束碼：0 成功、3 權限不足、6 未提供憑證或憑證無效。

完成後到 PCE Web Console 複製配對指令執行。完整說明見 [Windows 安裝 §做法 B](../../docs/ven/install-windows.md#做法-b官方配對指令)。
