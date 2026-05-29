> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/illumio_ven_linux_install.txt`

# Illumio VEN — Linux 手動安裝

## 1. 目的與適用情境

在 RHEL/CentOS（及 Ubuntu/Debian）Linux 主機上手動安裝 Illumio VEN，包含相依套件檢查、CA 憑證一鍵匯入、腳本安裝與手動安裝兩種方式，適用於無法使用自動化腳本或需要逐步驗證的部署場景。

自動化版本見 [`../../linux/manual_deploy/deploy-illumio.sh`](../../linux/manual_deploy/deploy-illumio.sh) 與 [`../../linux/pairing_prereq/prepare-and-pair.sh`](../../linux/pairing_prereq/prepare-and-pair.sh)。

## 2. 前置條件

- 已安裝支援的 Linux 發行版（RHEL 7/8/9、Ubuntu/Debian）
- 具備 root 或 sudo 權限
- 主機能解析 PCE FQDN 且防火牆允許連線至 TCP 8443
- 已取得有效的 Activation Code 及 PCE FQDN

## 3. 操作步驟

### [1] 相依套件檢查與安裝

```bash
# --- 適用於 RHEL 7 / CentOS 7 ---
# 檢查指令
rpm -q bind-utils curl gmp ipset iptables libcap libmnl libnfnetlink net-tools sed

# 安裝指令 (缺少時執行)
sudo yum install -y bind-utils curl gmp ipset iptables libcap libmnl libnfnetlink net-tools sed


# --- 適用於 RHEL 8 / 9, Rocky, AlmaLinux ---
# 檢查指令
rpm -q bind-utils diffutils curl gawk gmp gzip libcap libnfnetlink net-tools nftables sed shadow-utils tar util-linux

# 安裝指令 (缺少時執行)
sudo dnf install -y bind-utils diffutils curl gawk gmp gzip libcap libnfnetlink net-tools nftables sed shadow-utils tar util-linux
```

### [2] CA 憑證一鍵匯入

```bash
# --- 請複製以下整段指令並執行(請替換正確的憑證) ---

sudo tee /etc/pki/ca-trust/source/anchors/illumio-ca.crt << 'EOF'
-----BEGIN CERTIFICATE-----
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
eT+JL/8=
-----END CERTIFICATE-----
EOF

# 強制更新信任庫
sudo update-ca-trust force-enable
sudo update-ca-trust extract

# 檢查檔案是否建立
ls -l /etc/pki/ca-trust/source/anchors/illumio-ca.crt
```

### [3] 驗證 CA 是否生效

```bash
# 方法 A: 使用 Curl 測試連線 (推薦)
# 參數說明: -v (顯示詳細握手過程), -I (只抓取標頭)
curl -vvI https://<Target_URL>

# 預期結果:
# 1. 看到 "SSL certificate verify ok"
# 2. 看到 "HTTP/1.1 200 OK" (或 301/302)
# 若出現 "curl: (60) SSL certificate problem" 則代表失敗。

# 方法 B: 檢查系統 Trust Bundle 是否包含該 CA (本地檢查)
# 說明: 檢查 illumioCA 是否已合併入 ca-bundle.crt
grep -i "illumio" /etc/pki/tls/certs/ca-bundle.crt

# 預期結果:
# 應列出 "# illumioCA" 或相關文字，若無輸出代表 update-ca-trust 未成功。
```

### [4.1] 腳本安裝 Agent

```bash
rm -fr /opt/illumio_ven_data/tmp && umask 026 && mkdir -p /opt/illumio_ven_data/tmp && curl --tlsv1 "https://pce.lab.local:8443/api/v27/software/ven/image?pair_script=pair.sh&profile_id=10" -o /opt/illumio_ven_data/tmp/pair.sh && chmod +x /opt/illumio_ven_data/tmp/pair.sh && /opt/illumio_ven_data/tmp/pair.sh --management-server pce.lab.local:8443 --activation-code <ACTIVATION_CODE>
```

### [4.2] 手動安裝 Agent

進入安裝目錄：

```bash
cd /tmp
```

在 CentOS/Redhat 安裝指令：

```bash
rpm -ivh 23.2.31-3113_illumio-ven-23.2.31-3113.c7.x86_64.rpm
```

在 Ubuntu/Debian 安裝指令：

```bash
sudo dpkg -i 23.2.31-3113_illumio-ven-23.2.31-3113.u16.amd64.deb
```

回報至中控的啟用指令：

```bash
sudo /opt/illumio_ven/illumio-ven-ctl activate --management-server pce.lab.local:8443 --activation-code <ACTIVATION_CODE>
```

## 4. 驗證

```bash
# 確認 CA 已匯入
grep -i "illumio" /etc/pki/tls/certs/ca-bundle.crt

# 使用 curl 測試 PCE 連線
curl -vvI https://<PCE_FQDN>:8443
```

## 5. 失敗回滾 / 救援

- — 無 —

若 VEN 啟用失敗，確認 PCE FQDN 可解析、TCP 8443 可連通、Activation Code 未過期，並查閱 `/opt/illumio_ven/log/` 日誌。

## 6. 原廠文件參照

- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Linux Packages and Kernel Modules — RHEL 7/8/9 相依套件清單（curl、ipset、libcap、libnfnetlink、gmp、bind-utils、iptables）
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §About Red Hat 8 Support and nftables — RHEL 8/9 原生支援 nftables（19.3.0 起），取代 iptables
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Pair a Linux Workload / Linux Pairing Script — pair.sh 下載與執行流程（umask 026、curl --tlsv1、--management-server、--activation-code）與 SOP 一致
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Linux: Install and Upgrade with CLI and VEN CTL — 手動 rpm -ivh 安裝後執行 illumio-ven-ctl activate --management-server --activation-code
- [NotebookLM] Illumio Agent部署手冊_20250815.pdf §8.1 憑證錯誤(Error:408) — RHEL 系 CA 安裝至 /etc/pki/ca-trust/source/anchors/ 並執行 update-ca-trust

## 7. 與原廠差異（若有）

- **相依套件清單**：SOP 列出的 RHEL 8/9 套件清單（diffutils、gawk、gzip、tar、util-linux 等）與原廠（Install_Upgrade §Linux Packages）大致一致；RHEL 8/9 需加入 nftables，SOP 已涵蓋。
- **CA 憑證安裝方式**：SOP 使用 heredoc 直接寫入憑證內容，原廠方式相同（將 crt 複製至 anchors 目錄再 update-ca-trust），功能一致。
- **VEN ca-bundle 更新**：SOP 包含 update-ca-trust force-enable 步驟；VEN 重啟後 ca-bundle 自動更新，原廠未記錄此細節，SOP 補強合理。
