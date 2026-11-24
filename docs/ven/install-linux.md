# Illumio VEN — Linux 安裝

> **適用版本**：Illumio PCE 25.x / 26.x，VEN 25.x / 26.x（腳本於 VEN 26.2.20 實機驗證）  
> **最後更新**：2026-11-24

## 1. 目的與適用情境

在 RHEL 系（RHEL、CentOS、Rocky、AlmaLinux、Oracle Linux）與 Debian 系（Ubuntu、Debian）主機上安裝 VEN 並向 PCE 配對。本文是 Linux 安裝的唯一完整說明，涵蓋三種做法：

| 做法 | 適用情境 | 使用的檔案 |
|---|---|---|
| A. 部署腳本 | 大量派送、封閉環境、要自訂目錄 | [`linux/manual_deploy/deploy-illumio.sh`](../../linux/manual_deploy/deploy-illumio.sh) |
| B. 官方配對指令 | 少量主機、直接用 PCE 產生的指令 | [`linux/pairing_prereq/prepare-and-pair.sh`](../../linux/pairing_prereq/prepare-and-pair.sh)（只做前置） |
| C. 全手動 | 逐步驗證、排除問題 | 無 |

搭配派送工具的做法見 [大規模派送](./mass-deployment.md)。

## 2. 前置條件

- **權限**：root，或可用 `sudo`。
- **作業系統與相依套件**：見 [VEN 作業系統支援與相依套件](../reference/ven-os-support.md)。相依套件必須在安裝 VEN 之前裝好。
- **網路**：主機能解析 PCE 的 FQDN，並可連到下列埠。

  | 部署類型 | 埠 | 用途 |
  |---|---|---|
  | 地端 PCE | TCP 8443 | REST API (HTTPS) |
  | 地端 PCE | TCP 8444 | 長連線 (TLS) |
  | SaaS | TCP 443 | 兩者共用 |
  | SecureConnect（選用） | UDP 500、4500 | VEN 之間的 IPsec |

- **憑證**：PCE 憑證若由私有 CA 簽發，主機必須信任該 CA。路徑上若有 TLS 攔截設備，必須對 VEN 到 PCE 的流量停用攔截。
- **其他**：時間同步正常（NTP）；至少保留 10 GB 磁碟空間。
- **配對資訊**：PCE 位址（`FQDN:PORT`）與 Pairing Profile 產生的啟用碼。

## 3. 操作步驟

### 做法 A：部署腳本

`deploy-illumio.sh` 依序完成：偵測作業系統 → 匯入 CA 憑證 → 檢查 PCE 連線 → 安裝 VEN → 啟用。全程不需互動，可重複執行（已安裝、已啟用的部分會跳過）。

```bash
sudo bash deploy-illumio.sh \
    --management-server <PCE_FQDN>:<PORT> \
    --activation-code <ACTIVATION_CODE>
```

| 選項 | 說明 | 預設 |
|---|---|---|
| `--management-server HOST:PORT` | PCE 位址。也可用環境變數 `ILLUMIO_MANAGEMENT_SERVER` | 必填 |
| `--activation-code CODE` | 啟用碼。也可用環境變數 `ILLUMIO_ACTIVATION_CODE` | 必填 |
| `--cert-file PATH` | CA 憑證（PEM） | 腳本同目錄的 `illumio-ca.crt`，其次腳本內嵌憑證 |
| `--source-dir DIR` | 安裝包所在目錄 | 腳本所在目錄 |
| `--package FILE` | 安裝包檔名或絕對路徑 | 自動尋找 `*illumio-ven*.rpm` / `.deb` |
| `--no-download` | 本機沒有安裝包時不向 PCE 下載 | 會下載 |
| `--install-prefix DIR` | 程式的上層目錄（僅 RPM） | `/opt` |
| `--data-prefix DIR` | 資料的上層目錄 | `/opt` |
| `--skip-tls-check` | 略過安裝前的 PCE 連線檢查 | 會檢查 |
| `--api-version vNN` | 下載安裝包使用的 PCE API 版本 | `v25` |
| `--log-file PATH` | 日誌檔 | `/var/log/illumio-deploy.log` |

各步驟的行為：

- **CA 憑證**：有提供憑證就匯入系統信任庫，內容相同則跳過。沒有提供就跳過這一步，改用系統既有的信任憑證（PCE 使用公開 CA 或 SaaS 時不需要匯入）。
- **PCE 連線檢查**：安裝前先對 PCE 做一次 TLS 握手。信任鏈不通或連不到就中止，不會留下「裝了卻啟用不了」的主機。
- **安裝包**：先找本機的安裝包；找不到時以啟用碼向 PCE 的 VEN Library 下載符合本機作業系統的版本，並驗證 SHA256。這與官方 `pair.sh` 是同一套機制。找到多個安裝包時會中止，請用 `--package` 指定。
- **相依套件**：以 `rpm -i --test` 或 `dpkg --dry-run -i` 試裝，缺件就以結束碼 5 中止，並列出缺少的套件與建議的安裝指令。**腳本不會自行安裝任何作業系統套件。** 原廠支援表另外列出、但安裝包沒有宣告的套件只會提醒。
- **啟用**：`illumio-ven-ctl status` 的 Agent state 不是 `unpaired` 時視為已啟用，直接跳過。VEN 服務停止時 `status` 仍會回報原本的狀態，判斷不受影響。

啟用碼不會寫入日誌。用環境變數傳入可避免它出現在派送工具的命令列紀錄：

```bash
sudo ILLUMIO_MANAGEMENT_SERVER=<PCE_FQDN>:<PORT> ILLUMIO_ACTIVATION_CODE=<ACTIVATION_CODE> \
    bash deploy-illumio.sh
```

結束碼見 [大規模派送 §結束碼](./mass-deployment.md#結束碼)。

#### 自訂安裝目錄

```bash
# RPM：程式與資料目錄都可自訂
sudo bash deploy-illumio.sh --management-server <PCE_FQDN>:<PORT> --activation-code <ACTIVATION_CODE> \
    --install-prefix /app/illumio --data-prefix /data/illumio

# DEB：只能自訂資料目錄
sudo bash deploy-illumio.sh --management-server <PCE_FQDN>:<PORT> --activation-code <ACTIVATION_CODE> \
    --data-prefix /data/illumio
```

| 套件格式 | 程式目錄 | 資料目錄 |
|---|---|---|
| RPM | 可自訂，結果為 `<install-prefix>/illumio_ven` | 可自訂，結果為 `<data-prefix>/illumio_ven_data` |
| DEB | 固定為 `/opt/illumio_ven`（`dpkg` 不支援） | 可自訂；之後升級必須沿用，不能搬移 |

- 自訂目錄只在初次安裝時生效。之後重跑腳本不必再給這兩個選項，腳本會從套件管理員的紀錄找到實際位置。
- **SELinux**：自訂目錄預設的標籤會讓 systemd 無法執行 VEN 常駐程式，啟用會失敗。腳本偵測到 SELinux 啟用時，會讓 `<install-prefix>/illumio_ven` 與 `<data-prefix>/illumio_ven_data` 這兩個子目錄比照預設位置的標籤規則。上層目錄與其中其他應用程式的檔案不會被更動，所以把資料目錄指向 `/data` 這類共用位置是安全的。系統有 `semanage` 時建立永久規則；沒有時只做暫時標記並顯示警告，請依警告補上永久規則。

### 做法 B：官方配對指令

官方配對指令會自行下載並安裝 VEN。事前只需要處理憑證與相依套件，這由 `prepare-and-pair.sh` 完成。

> **注意**：官方的 `pair.sh` 會自動安裝相依套件，全程不詢問。不允許自動安裝套件的環境請改用做法 A 或 C。`prepare-and-pair.sh` 本身只檢查與報告，不會安裝套件。

| 作業系統 | 官方 `pair.sh` 執行的安裝指令 | 效果 |
|---|---|---|
| RHEL 系 | `yum -y --nogpgcheck localinstall <安裝包>`，失敗才退回 `rpm -ivh` | 缺的相依套件自動從主機設定的套件庫安裝；略過簽章檢查 |
| Ubuntu 16.04 以上 | `apt-get --assume-yes install <安裝包>` | 自動補齊相依套件 |
| 較舊的 Ubuntu、Debian | 先 `dpkg -i`；失敗就以 `apt-get install --assume-yes` 安裝 Depends 清單後重試 | 失敗時自動補裝 |
| SLES | `zypper --no-gpg-checks --non-interactive install <安裝包>` | 自動補齊相依套件；略過簽章檢查 |

主機連不到套件庫時，RHEL 系會退回 `rpm -ivh`，此時缺件會直接失敗。

| 選項 | 說明 |
|---|---|
| `--cert-file PATH` | CA 憑證（PEM）。預設為腳本同目錄的 `illumio-ca.crt`，其次腳本內嵌憑證 |
| `--strict` | 缺少相依套件時以結束碼 5 結束（預設只報告） |
| `--log-file PATH` | 日誌檔。預設 `/var/log/illumio-deploy.log` |

接著到 PCE Web Console 的 **Servers & Endpoints > Pairing Profiles**，選定 Pairing Profile 後產生 Pairing Key，複製 Linux OS Pairing Script 在主機上執行。指令形式如下：

```bash
rm -fr /opt/illumio_ven_data/tmp && umask 026 && mkdir -p /opt/illumio_ven_data/tmp && \
curl --tlsv1 "https://<PCE_FQDN>:<PORT>/api/v<NN>/software/ven/image?pair_script=pair.sh&profile_id=<PROFILE_ID>" \
    -o /opt/illumio_ven_data/tmp/pair.sh && \
chmod +x /opt/illumio_ven_data/tmp/pair.sh && \
/opt/illumio_ven_data/tmp/pair.sh --management-server <PCE_FQDN>:<PORT> --activation-code <ACTIVATION_CODE>
```

`curl --tlsv1` 的意思是「至少 TLS 1.0」，實際會協商到雙方都支援的最高版本。要強制下限可改成 `--tlsv1.2`。

### 做法 C：全手動

```bash
# 1. 確認相依套件（清單見 VEN 作業系統支援與相依套件）
rpm -i --test illumio-ven-<VERSION>.<PLATFORM>.rpm        # RHEL 系
sudo dpkg --dry-run -i illumio-ven-<VERSION>.<PLATFORM>.deb   # Debian 系

# 2. 匯入 CA 憑證 (PCE 使用私有 CA 時)
#    RHEL 系
sudo cp illumio-ca.crt /etc/pki/ca-trust/source/anchors/illumio-ca.crt
sudo update-ca-trust extract
#    Debian 系
sudo cp illumio-ca.crt /usr/local/share/ca-certificates/illumio-ca.crt
sudo update-ca-certificates

# 3. 確認 PCE 憑證受信任
curl -sS -o /dev/null https://<PCE_FQDN>:<PORT>/ && echo "TLS OK"

# 4. 安裝
sudo rpm -ivh illumio-ven-<VERSION>.<PLATFORM>.rpm        # RHEL 系
sudo dpkg -i illumio-ven-<VERSION>.<PLATFORM>.deb         # Debian 系

# 5. 啟用
sudo /opt/illumio_ven/illumio-ven-ctl activate \
    --management-server <PCE_FQDN>:<PORT> --activation-code <ACTIVATION_CODE>
```

### 解除安裝

先解除配對，VEN 會一併移除套件並從 PCE 刪除該 workload：

```bash
sudo /opt/illumio_ven/illumio-ven-ctl unpair <recommended | saved | open>
```

| 模式 | 解除後的防火牆狀態 |
|---|---|
| `recommended` | 只允許 SSH (22)，直到重新開機 |
| `saved` | 還原成安裝 VEN 之前的規則 |
| `open` | 全部開放 |

憑證若不再需要，另外移除：

```bash
sudo rm /etc/pki/ca-trust/source/anchors/illumio-ca.crt && sudo update-ca-trust extract        # RHEL 系
sudo rm /usr/local/share/ca-certificates/illumio-ca.crt && sudo update-ca-certificates --fresh   # Debian 系
```

## 4. 驗證

```bash
sudo /opt/illumio_ven/illumio-ven-ctl status
```

- 四個常駐程式（venAgentMgr、venPlatformHandler、venVtapServer、venAgentMonitor）都在執行。
- `Agent state` 為 Pairing Profile 指定的模式（`idle`、`illuminated`、`selective`、`enforced`），不是 `unpaired`。
- PCE Web Console 的 Workloads 清單出現該主機，狀態為 Online。

## 5. 失敗回滾 / 救援

| 現象 | 處理方式 |
|---|---|
| 結束碼 5，列出缺少的套件 | 依日誌中「建議的安裝指令」自行安裝後重跑 |
| 結束碼 6，憑證無效 | 確認檔案是 PEM 格式，內容完整 |
| 結束碼 7，無法驗證 PCE 憑證 | 提供簽發 PCE 憑證的 CA（`--cert-file`）；確認路徑上沒有 TLS 攔截 |
| 結束碼 7，無法連線 | 檢查 DNS、防火牆、Proxy |
| 結束碼 8，PCE 沒有符合的安裝包或啟用碼無效 | 確認啟用碼；或自備安裝包（`--package`） |
| 結束碼 9，啟用失敗 | 確認啟用碼有效且未超過使用次數；查看 `<資料目錄>/log/` |
| 自訂目錄下啟用失敗，系統日誌出現 `Permission denied` | SELinux 標籤問題，見「自訂安裝目錄」 |
| 安裝後要整個退回 | `illumio-ven-ctl unpair saved` |

腳本的日誌在 `/var/log/illumio-deploy.log`。

## 6. 原廠文件參照

- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Linux: Install and Upgrade with CLI and VEN CTL — `rpm -ivh`、`illumio-ven-ctl activate` 的參數；`rpm --prefix` 與 `VEN_DATA_DIR` 自訂目錄；DEB 不支援自訂程式目錄
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Pair a Linux Workload — 官方配對指令的形式
- [Web] https://support.illumio.com/shared/software/os-support-package-dependencies/ven.html — 作業系統支援與相依套件
- [現場] 官方 `pair.sh`（PCE 26.2）— 以 `agent_0` 加啟用碼向 `/api/vNN/software/ven/image` 下載安裝包，回應標頭含 `X-SHA256`
- [現場] 2026-11-24 於 CentOS Stream 8（SELinux Enforcing）與 Ubuntu 24.04 對 lab PCE 實機驗證

## 7. 與原廠差異（若有）

- **相依套件檢查**：原廠支援表列出的套件與安裝包實際宣告的不完全相同（例：支援表列 `net-tools`，VEN 26.2 的安裝包未宣告，未安裝也能正常運作）。腳本以安裝包試裝的結果為準，支援表的差異只提醒。
- **SELinux 與自訂目錄**：原廠文件只說明 `--prefix` 與 `VEN_DATA_DIR`，未提到 SELinux 啟用時需要調整標籤。此為現場實測補充。
- **已啟用的判斷**：以 `illumio-ven-ctl status` 的 Agent state 判斷，原廠文件未明載重複執行 `activate` 的行為。
- **內容改寫**（2026-11-24）：本文取代原 SOP 與 `linux/` 下兩份 README 的重複內容。原 SOP 內嵌的 lab CA 憑證與 lab 主機名稱已移除，改為佔位符；安裝包檔名改為 `<VERSION>.<PLATFORM>` 形式。
- **官方 pair.sh 自動安裝相依套件**：依 PCE 26.2 產生的 `pair.sh` 原始碼確認，各作業系統的指令見做法 B 的表格。本專案的部署腳本刻意不這麼做，缺件時只列出建議的安裝指令。
