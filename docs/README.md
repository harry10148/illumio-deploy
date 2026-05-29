# Illumio 維運 SOP

> 本目錄收錄 Illumio PCE / VEN / 憑證 / 平台整合相關的標準作業程序（SOP）。
> 模板與規則見 [SOP-TEMPLATE.md](./SOP-TEMPLATE.md)；驗證流程見
> [設計 spec](./superpowers/specs/2026-05-29-illumio-sop-integration-design.md)。

## 目錄

### PCE 伺服器端 (`pce/`)
| 主題 | 檔案 |
|---|---|
| SNC 單節點安裝 | [snc-setup.md](./pce/snc-setup.md) |
| MNC 多節點安裝 | [mnc-setup.md](./pce/mnc-setup.md) |
| 升級程序 | [upgrade.md](./pce/upgrade.md) |
| 備份程序 | [backup.md](./pce/backup.md) |
| 漏洞處理 | [vulnerability.md](./pce/vulnerability.md) |
| 網路設定 | [network-setting.md](./pce/network-setting.md) |
| 節點移除 | [remove-node.md](./pce/remove-node.md) |

### VEN 端點 (`ven/`)
| 主題 | 檔案 |
|---|---|
| Linux 手動安裝 | [install-linux.md](./ven/install-linux.md) |
| Windows 手動安裝 | [install-windows.md](./ven/install-windows.md) |
| AIX 手動安裝 | [install-aix.md](./ven/install-aix.md) |
| AIX 解除安裝 | [uninstall-aix.md](./ven/uninstall-aix.md) |
| Proxy + Pairing Profile | [proxy-pairprofile.md](./ven/proxy-pairprofile.md) |
| Rule Hit Count 查詢 | [rule-hit-count.md](./ven/rule-hit-count.md) |

> 自動化部署腳本見 [`../linux/`](../linux/)、[`../windows/`](../windows/)、[`../aix/`](../aix/)。

### 憑證與 SSL (`cert/`)
| 主題 | 檔案 |
|---|---|
| DigiCert Root CA（Linux） | [digicert-root-linux.md](./cert/digicert-root-linux.md) |
| DigiCert Root CA（Windows） | [digicert-root-windows.md](./cert/digicert-root-windows.md) |
| OpenSSL 自簽憑證 | [openssl-cert-sign.md](./cert/openssl-cert-sign.md) |

### 平台與整合 (`platform/`)
| 主題 | 檔案 |
|---|---|
| Kubernetes 部署 | [k8s.md](./platform/k8s.md) |
| Kubernetes 初始化 | [k8s-init.md](./platform/k8s-init.md) |
| FlowLink SOP | [flowlink.md](./platform/flowlink.md) |
| Linux Emergency Mode | [linux-emergency-mode.md](./platform/linux-emergency-mode.md) |
| RedHat LVM 調整 | [redhat-lvm.md](./platform/redhat-lvm.md) |

### 原廠手冊 (`guide/`)
本目錄存放原廠中文手冊本機快取，**內容不入 git**（`.gitignore` 排除）：

- `Illumio Agent部署手冊_20250815.docx`
- `Illumio_PCE操作手冊_20251128.docx`

取得方式：
1. 內部來源 / 同事提供
2. NotebookLM「Illumio」筆記（ID `8c325126-bc83-4c86-8c6e-8759a242928e`）內收錄；
   `notebooklm source list -n 8c325126-bc83-4c86-8c6e-8759a242928e` 可看到對應 source。

## 原 tmp/ 對映（歷史參考）

> 若在舊對話紀錄、shell history 或舊 issue 中只記得原始 `.txt` 檔名，
> 可用此表查到對應 SOP 位置。部分檔名含**原始拼寫錯誤**（如 `illumilo`、
> `ilumio`、`ndoe`），此為舊文件本身的錯字，非此表之誤；新檔名一律拼正。

下表記錄遷移前的舊檔名 → 新位置：

| 原 tmp/ 檔名 | 新位置 |
|---|---|
| `illumio_pce_snc_setup_v3.txt` | `pce/snc-setup.md` |
| `illumio_pce_mnc_setup_v4.txt` | `pce/mnc-setup.md` |
| `illumio_pce_upgrade_snc.txt` | `pce/upgrade.md` |
| `illumio_backup_v4.txt` | `pce/backup.md` |
| `illumio_pce_vulnerability.txt` | `pce/vulnerability.md` |
| `illumio_snc_network_setting.txt` | `pce/network-setting.md` |
| `pce_remove_ndoe.txt` | `pce/remove-node.md` |
| `illumio_ven_linux_install.txt` | `ven/install-linux.md` |
| `illumio_ven_win_install.txt` | `ven/install-windows.md` |
| `illumio_ven_aix_install.txt` | `ven/install-aix.md` |
| `illumio_ven_aix_uninstall.txt` | `ven/uninstall-aix.md` |
| `Illumio_ven_proxy_pairprofile.txt` | `ven/proxy-pairprofile.md` |
| `illumio_rulehitcount.txt` | `ven/rule-hit-count.md` |
| `DigiCert_Global_Root_Linux.txt` | `cert/digicert-root-linux.md` |
| `DigiCert_Global_Root_windows.txt` | `cert/digicert-root-windows.md` |
| `openssl_cert-sign.txt` | `cert/openssl-cert-sign.md` |
| `illumio_k8s.txt` | `platform/k8s.md` |
| `illumilo_k8s_init.txt` | `platform/k8s-init.md` |
| `ilumio FlowLink SOP.txt` | `platform/flowlink.md` |
| `linux_emergency_mode_sop.txt` | `platform/linux-emergency-mode.md` |
| `illumio_Redhat_LVM_SOP.txt` | `platform/redhat-lvm.md` |

> 原 `tmp/` 為 `.gitignore` 排除目錄，自始未入 git；
> 原指令文字已逐字併入各 `.md` 的 §3 fenced block，是版控起點。

## 新增 SOP

複製 [`SOP-TEMPLATE.md`](./SOP-TEMPLATE.md)，依模板強制規則填寫。提交前跑：

```bash
./scripts/check-sop-template.sh
```
