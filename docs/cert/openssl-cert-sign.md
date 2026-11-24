# OpenSSL 自簽憑證程序

> **適用版本**：Illumio PCE 25.4 / VEN 25.4  
> **最後更新**：2026-11-24

## 1. 目的與適用情境

使用 OpenSSL 建立自有 CA 金鑰與根憑證、伺服器金鑰、憑證簽署請求（CSR），並以自有 CA 簽發含有 SAN 的伺服器憑證，適用於 Illumio PCE 實驗室或測試環境需要自簽 TLS 憑證的場景。

## 2. 前置條件

- 已安裝 OpenSSL
- 確認 PCE FQDN 及所有節點主機名稱（用於 SAN 設定）

## 3. 操作步驟

```bash
#1.Create CA key
	openssl genrsa -des3 -out ca.key 4096
#2.Create CA cert
	openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out illumio-ca.crt
#3.Create Server key
	openssl genrsa -out server.key 4096
#4.Create ssl.conf
#=======================================================================
[ req ]
prompt					= no
default_bits				= 4096
distinguished_name			= req_distinguished_name
req_extensions  			= req_ext

[ req_distinguished_name ]
countryName				= TW
stateOrProvinceName			= Taiwan
localityName				= Taipei
organizationName			= illumio
organizationalUnitName			= Fairline
commonName				= pce.example.com
[ req_ext ]
extendedKeyUsage			= serverAuth, clientAuth
subjectAltName				= @alt_names

[alt_names]
DNS.1   = pce.example.com
DNS.2   = core0.example.com
DNS.3   = core1.example.com
DNS.4   = data0.example.com
DNS.5   = data1.example.com


#=======================================================================
#5.Create CSR
openssl req -new -sha256 \
    -out server.csr \
    -key server.key \
    -config ssl.conf


#6.Use CA to sign key
openssl x509 -req \
            -days 3650 \
            -in server.csr \
            -out server.crt \
            -extensions req_ext \
            -extfile ssl.conf \
            -CA ca.crt \
            -CAkey illumio-ca.key \
            -CAcreateserial \
            -sha256
```

## 4. 驗證

- — 無 —

可使用以下指令確認簽發完成的憑證內容正確：

```bash
openssl x509 -in server.crt -noout -text | grep -A1 "Subject Alternative Name"
```

## 5. 失敗回滾 / 救援

- — 無 —

## 6. 原廠文件參照

- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Kubernetes and Openshift > Download the Root CA Certificate — 顯示 openssl 指令範例及 RSA 4096-bit 金鑰，用於驗證憑證鏈（非 PCE 憑證生成指南）
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Prerequisites for VEN Installation — RHEL 8/9 FUTURE 加密政策要求 RSA ≥ 3072 bit
- [NotebookLM] 資料庫無相關內容：PCE 自簽憑證生成（openssl req、CA 簽發、SAN 設定）Illumio 官方文件未提供具體 OpenSSL 指令，PCE Installation Guide 25.4 未收錄於資料庫

## 7. 與原廠差異（若有）

- **原廠文件未涵蓋**：Illumio 官方文件不提供 PCE 自簽 TLS 憑證的 OpenSSL 生成步驟；此 SOP 為環境補強（Lab/POC 用途），內容基於 OpenSSL 標準實作。SAN 設定（包含所有節點 FQDN 與 PCE FQDN）是 PCE 憑證的必要條件，SOP 正確包含此設定。
- **範例環境去識別**（2026-11-24）：原 SOP 中的 lab 主機名稱與 IP 已改為 `example.com` 與 `10.0.0.x` 範例值；指令與參數本身未變更。
