# deploy-illumio.sh — Linux 完整部署

匯入 CA 憑證、檢查 PCE 連線、安裝 VEN、啟用，一次完成。不需互動，可重複執行。

```bash
sudo bash deploy-illumio.sh \
    --management-server <PCE_FQDN>:<PORT> \
    --activation-code <ACTIVATION_CODE>
```

- CA 憑證：放在腳本同目錄並命名為 `illumio-ca.crt`，或用 `--cert-file` 指定。PCE 使用公開 CA 時不必提供。
- 安裝包：放在腳本同目錄；沒有時腳本會向 PCE 下載符合本機的版本。
- 所有選項：`bash deploy-illumio.sh --help`
- 日誌：`/var/log/illumio-deploy.log`

完整說明（選項、自訂目錄、SELinux、解除安裝、疑難排解）見 [Linux 安裝](../../docs/ven/install-linux.md)。
派送工具的接法與結束碼見 [大規模派送](../../docs/ven/mass-deployment.md)。
