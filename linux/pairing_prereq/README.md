# prepare-and-pair.sh — Linux 官方配對前置

在執行 PCE 產生的配對指令之前，檢查相依套件並匯入 CA 憑證。本腳本不安裝 VEN。

```bash
sudo bash prepare-and-pair.sh --cert-file /path/to/illumio-ca.crt
```

- 未指定 `--cert-file` 時，使用腳本同目錄的 `illumio-ca.crt`。
- 相依套件預設只報告；加上 `--strict` 則缺件時以結束碼 5 結束。
- 所有選項：`bash prepare-and-pair.sh --help`

完成後到 PCE Web Console 複製配對指令執行。完整說明見 [Linux 安裝 §做法 B](../../docs/ven/install-linux.md#做法-b官方配對指令)。
