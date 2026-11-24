# Illumio 手冊索引

PCE、VEN、憑證與平台整合的操作手冊。每份 SOP 都依 [SOP 模板](./SOP-TEMPLATE.md) 的七個章節撰寫：目的、前置條件、操作步驟、驗證、失敗救援、原廠文件參照、與原廠差異。

## VEN（`ven/`）

| 主題 | 檔案 |
|---|---|
| Linux 安裝（腳本、官方配對、全手動、自訂目錄、解除安裝） | [install-linux.md](./ven/install-linux.md) |
| Windows 安裝（腳本、官方配對、全手動、自訂目錄、解除安裝） | [install-windows.md](./ven/install-windows.md) |
| AIX 安裝 | [install-aix.md](./ven/install-aix.md) |
| AIX 解除安裝 | [uninstall-aix.md](./ven/uninstall-aix.md) |
| 大規模派送（SCCM、Intune、群組原則、Ansible、結束碼、嚴格環境） | [mass-deployment.md](./ven/mass-deployment.md) |
| Proxy 與 Pairing Profile | [proxy-pairprofile.md](./ven/proxy-pairprofile.md) |
| Rule Hit Count 查詢 | [rule-hit-count.md](./ven/rule-hit-count.md) |

部署腳本在 [`../linux/`](../linux/) 與 [`../windows/`](../windows/)。

## PCE（`pce/`）

| 主題 | 檔案 |
|---|---|
| SNC 單節點安裝 | [snc-setup.md](./pce/snc-setup.md) |
| MNC 多節點安裝 | [mnc-setup.md](./pce/mnc-setup.md) |
| 升級 | [upgrade.md](./pce/upgrade.md) |
| 備份 | [backup.md](./pce/backup.md) |
| 漏洞處理 | [vulnerability.md](./pce/vulnerability.md) |
| 網路設定 | [network-setting.md](./pce/network-setting.md) |
| 節點移除 | [remove-node.md](./pce/remove-node.md) |

## 憑證（`cert/`）

| 主題 | 檔案 |
|---|---|
| DigiCert Root CA 匯入（Linux） | [digicert-root-linux.md](./cert/digicert-root-linux.md) |
| DigiCert Root CA 匯入（Windows） | [digicert-root-windows.md](./cert/digicert-root-windows.md) |
| OpenSSL 自簽憑證 | [openssl-cert-sign.md](./cert/openssl-cert-sign.md) |

## 平台與整合（`platform/`）

| 主題 | 檔案 |
|---|---|
| Kubernetes 部署 | [k8s.md](./platform/k8s.md) |
| Kubernetes 初始化 | [k8s-init.md](./platform/k8s-init.md) |
| FlowLink | [flowlink.md](./platform/flowlink.md) |
| Linux Emergency Mode | [linux-emergency-mode.md](./platform/linux-emergency-mode.md) |
| RedHat LVM 調整 | [redhat-lvm.md](./platform/redhat-lvm.md) |

## 參考資料（`reference/`）

| 主題 | 檔案 |
|---|---|
| VEN 作業系統支援與相依套件（原廠支援表） | [ven-os-support.md](./reference/ven-os-support.md) |
| 舊檔名對映（原 `tmp/*.txt` 到現行位置） | [legacy-filenames.md](./reference/legacy-filenames.md) |

## 原廠手冊（`guide/`）

存放原廠中文手冊的本機快取，內容不進版本控制（`.gitignore` 排除）：

- `Illumio Agent部署手冊_20250815.docx`
- `Illumio_PCE操作手冊_20251128.docx`

取得方式：內部來源，或 NotebookLM「Illumio」筆記（ID `8c325126-bc83-4c86-8c6e-8759a242928e`）。`guide/_rework/` 是這兩份手冊的核對報告與風格指南。

## 新增或修改 SOP

複製 [`SOP-TEMPLATE.md`](./SOP-TEMPLATE.md)，依模板填寫。提交前在專案根目錄執行：

```bash
./scripts/check-docs.sh
```
