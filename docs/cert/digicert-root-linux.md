> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/DigiCert_Global_Root_Linux.txt`

# DigiCert Global Root CA 匯入（Linux）

## 1. 目的與適用情境

將 DigiCert Global Root G2 與 G3 根憑證匯入 Linux 系統信任庫，適用於 RHEL/CentOS/Rocky/Alma/Oracle Linux（yum/dnf 系）及 Debian/Ubuntu（apt 系），確保系統與 VEN 能信任 DigiCert 簽發的憑證鏈；包含有網路與 Air-Gapped 離線兩種方案，以及 VEN 重啟流程。

## 2. 前置條件

- 需 root 權限（使用 sudo 或切換為 root）
- 已確認發行版類型（RHEL 系 或 Debian/Ubuntu 系）

## 3. 操作步驟

### 方案 A — 有網際網路連線

**RHEL / CentOS / Rocky / Alma（使用 update-ca-trust）：**

```bash
sudo curl -fsSL -o /etc/pki/ca-trust/source/anchors/DigiCertGlobalRootG2.pem \
  https://cacerts.digicert.com/DigiCertGlobalRootG2.crt.pem

sudo curl -fsSL -o /etc/pki/ca-trust/source/anchors/DigiCertGlobalRootG3.pem \
  https://cacerts.digicert.com/DigiCertGlobalRootG3.crt.pem

sudo update-ca-trust extract
```

**Debian / Ubuntu（使用 update-ca-certificates，副檔名必須是 .crt）：**

```bash
sudo curl -fsSL -o /usr/local/share/ca-certificates/DigiCertGlobalRootG2.crt \
  https://cacerts.digicert.com/DigiCertGlobalRootG2.crt.pem

sudo curl -fsSL -o /usr/local/share/ca-certificates/DigiCertGlobalRootG3.crt \
  https://cacerts.digicert.com/DigiCertGlobalRootG3.crt.pem

sudo update-ca-certificates
```

### 方案 B — 無網際網路連線 / Air-Gapped

**RHEL / CentOS / Rocky / Alma：**

```bash
# --- DigiCert Global Root G2 ---
sudo tee /etc/pki/ca-trust/source/anchors/DigiCertGlobalRootG2.pem > /dev/null <<'EOF'
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
EOF

# --- DigiCert Global Root G3 ---
sudo tee /etc/pki/ca-trust/source/anchors/DigiCertGlobalRootG3.pem > /dev/null <<'EOF'
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
EOF

sudo update-ca-trust extract
```

**Debian / Ubuntu（注意：檔案副檔名必須為 .crt）：**

```bash
# --- DigiCert Global Root G2 ---
sudo tee /usr/local/share/ca-certificates/DigiCertGlobalRootG2.crt > /dev/null <<'EOF'
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
EOF

# --- DigiCert Global Root G3 ---
sudo tee /usr/local/share/ca-certificates/DigiCertGlobalRootG3.crt > /dev/null <<'EOF'
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
EOF

sudo update-ca-certificates
```

### 驗證匯入結果（兩個發行版通用）

```bash
# 驗證 G2
openssl x509 -in /etc/ssl/certs/ca-certificates.crt -noout -subject 2>/dev/null
awk -v cmd='openssl x509 -noout -subject' '/BEGIN/{close(cmd)};{print | cmd}' \
  /etc/ssl/certs/ca-certificates.crt 2>/dev/null | grep -i "DigiCert Global Root G"

# 或使用 trust（RHEL 系）
trust list | grep -i "DigiCert Global Root G"
```

### Illumio VEN 重啟流程

```bash
# 重命名 ca-bundle.crt 以強制 VEN 啟動時重新匯出憑證
sudo mv /opt/illumio_ven_data/etc/ca-bundle.crt /opt/illumio_ven_data/etc/ca-bundle.crt.old

# 重啟 VEN
sudo /opt/illumio_ven/illumio-ven-ctl restart
```

## 4. 驗證

```bash
trust list | grep -i "DigiCert Global Root G"
```

## 5. 失敗回滾 / 救援

- — 無 —

重要提醒：
- Debian/Ubuntu 的 `update-ca-certificates` 只處理副檔名為 `.crt` 的檔案，RHEL 系則接受 `.pem` 或 `.crt`。
- Illumio VEN 路徑可能因版本而異，確認路徑：
  - RHEL 系：`rpm -ql illumio-ven | grep -E 'ven-ctl|ca-bundle'`
  - Debian 系：`dpkg -L illumio-ven | grep -E 'ven-ctl|ca-bundle'`

## 6. 原廠文件參照

- [NotebookLM] Illumio Agent部署手冊_20250815.pdf §8.1 憑證錯誤(Error:408) — CentOS/RHEL 系：cp ca.crt /etc/pki/ca-trust/source/anchors/ && update-ca-trust enable && update-ca-trust extract；Ubuntu 系：cp /usr/local/share/ca-certificates && update-ca-certificates
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Set up Certificates on Workloads — VEN 需信任 PCE 的根 CA 憑證，路徑設定與發行版相關
- [Web] https://cacerts.digicert.com/DigiCertGlobalRootG2.crt.pem — DigiCert Global Root G2 官方下載頁
- [Web] https://cacerts.digicert.com/DigiCertGlobalRootG3.crt.pem — DigiCert Global Root G3 官方下載頁

## 7. 與原廠差異（若有）

- **CA 安裝方式**：SOP 提供 DigiCert 特定根憑證內嵌 PEM 方式，原廠（Agent部署手冊 §8.1）提供通用 CA 安裝方式，原理相同，SOP 針對 DigiCert 場景補強合理。
- **VEN ca-bundle.crt 更新**：SOP 包含 mv ca-bundle.crt ca-bundle.crt.old + illumio-ven-ctl restart 流程；原廠文件未明確記錄此步驟（AIX 章節有提及 ca-bundle），SOP 為 VEN 信任庫刷新的實務補強。
- **Debian/Ubuntu 副檔名要求**：SOP 正確指出 Debian 系需使用 .crt 副檔名（非 .pem），與原廠（Agent部署手冊）一致。
