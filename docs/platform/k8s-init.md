> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/illumilo_k8s_init.txt`

# Illumio Kubernetes 初始化作業

## 1. 目的與適用情境

在已部署 Illumio Core 的 Kubernetes 叢集上執行初始化前置作業，包含 machineID 確認、自簽 CA 匯入系統與 ConfigMap、安裝 calicoctl 並調整 Calico Felix chainInsertMode 設定（含三種方法）、設定 Helm values 並部署，以及設定 CoreDNS 自訂域名解析。

## 2. 前置條件

- Kubernetes 叢集已正常運行
- `kubectl`、`helm` 已安裝
- 自簽 CA 憑證（`ca.crt`）已備妥
- 已確認叢集各節點的 machineID 唯一

## 3. 操作步驟

確認各節點 machineID：

```bash
kubectl get node -o yaml | grep machineID
      machineID: c2ea9def5cb2479aa28bc1bc2e062b08
      machineID: 36abf709dcb44214ad3b7ce9b70bd590
      machineID: 260a099dcefb401c82c2f476e1081585
```

匯入自簽 CA 至系統信任庫（Ubuntu 節點）：

```bash
sudo apt-get install -y ca-certificates
sudo cp ca.crt /usr/local/share/ca-certificates
sudo update-ca-certificates
```

建立 Kubernetes ConfigMap 存放自簽憑證：

```bash
kubectl -n illumio-system create configmap root-ca-config --from-file=./ca.crt
```

安裝 calicoctl：

```bash
curl -L https://github.com/projectcalico/calico/releases/download/v3.28.0/calicoctl-linux-amd64 -o calicoctl
chmod +x ./calicoctl
sudo mv calicoctl /usr/local/bin/
```

調整 Calico chainInsertMode — 方法一（calicoctl，官方指南）：

```bash
calicoctl get felixconfig default -o yaml --export > felix.yaml
vi felix.yaml
  chainInsertMode: Append
calicoctl replace -f felix.yaml
kubectl rollout restart daemonset/calico-node -n calico-system
```

調整 Calico chainInsertMode — 方法二（kubectl patch）：

```bash
kubectl patch felixconfiguration default --patch '{"spec": {"chainInsertMode": "Append"}}' --type=merge
```

調整 Calico chainInsertMode — 方法三（apply YAML）：

```yaml
apiVersion:felix-config.yaml projectcalico.org/v3
kind: FelixConfiguration
metadata:
  name: default
spec:
  chainInsertMode: Append
```

```bash
kubectl apply -f felix-config.yaml
kubectl rollout restart daemonset/calico-node -n calico-system
```

調整 Calico chainInsertMode — 方法四（Illumio UserGuide，直接編輯 DaemonSet）：

```bash
kubectl -n kube-system edit ds calico-node
```

在 spec > template > spec > containers 加入：

```
- name: FELIX_CHAININSERTMODE
  value: Append
```

設定 Helm values 並部署：

```bash
vi illumio-values.yaml
```

illumio-values.yaml 內容：

```yaml
pce_url: pce.lab.local:8443
cluster_id: <ILO_CLUSTER_UUID>
cluster_token: <ILO_CLUSTER_TOKEN>
cluster_code: <ILO_CLUSTER_CODE>
containerRuntime: crio
containerManager: kubernetes
extraVolumeMounts:
  - name: root-ca
    mountPath: /etc/pki/tls/ilo_certs/
    readOnly: false
extraVolumes:
  - name: root-ca
    configMap:
        name: root-ca-config
ignore_cert: true
clusterMode: clas
```

```bash
helm install illumio -f illumio-values.yaml oci://quay.io/illumio/illumio --version <ver#> --namespace illumio-system --create-namespace
helm upgrade illumio -f illumio-values.yaml oci://quay.io/illumio/illumio -n illumio-system --version <ver#>
```

設定 CoreDNS 自訂域名解析（kube-dns-config.yaml）：

```bash
vi kube-dns-config.yaml
```

kube-dns-config.yaml 內容：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  lab.server: | # All custom server files must have a ".server" file extension.
    # Change example.com to the domain you wish to forward.
    lab.local {
      # Change 1.1.1.1 to your customer DNS resolver.
      forward . 172.16.15.100
    }
  upstreamNameservers: |
    ["172.16.15.100"]
```

```bash
kubectl apply -f kube-dns-config.yaml

kubectl rollout restart -n kube-system deployment coredns
```

## 4. 驗證

```bash
# 確認 calico-node daemonset 已成功 rollout
kubectl rollout status daemonset/calico-node -n calico-system

# 確認 CoreDNS 設定已套用
kubectl rollout status deployment/coredns -n kube-system

# 確認 illumio-system namespace Pod 正常
kubectl get pods -n illumio-system
```

## 5. 失敗回滾 / 救援

- — 無 —

若 chainInsertMode 設定未生效，重新執行 `kubectl rollout restart daemonset/calico-node -n calico-system` 並觀察 Pod 是否正常重啟。

## 6. 原廠文件參照

- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Configure Calico in Append Mode — kubectl -n kube-system edit ds calico-node，加入 FELIX_CHAININSERTMODE: Append，與 SOP 方法四一致
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Deploy with Helm Chart / Helm Chart Parameters — pce_url、cluster_id、cluster_token、cluster_code、containerRuntime、extraVolumes/extraVolumeMounts 參數說明
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Implement Kubelink with a Private PKI — ConfigMap root-ca-config 搭配 extraVolumes 掛載 CA 憑證至 Pod
- [NotebookLM] MicroK8s Illumio 支援性諮詢 — Illumio 官方僅支援 Vanilla K8s、OpenShift、EKS、AKS、GKE、IKS；MicroK8s 非官方支援平台

## 7. 與原廠差異（若有）

- **Calico chainInsertMode 四種方法**：SOP 提供 calicoctl、kubectl patch、YAML apply、直接編輯 DaemonSet 四種方法；原廠（Install_Upgrade §Configure Calico in Append Mode）以直接編輯 DaemonSet 為主要說明，其他方法為 SOP 補充，均可達到相同效果。
- **CoreDNS 自訂域名**：原廠文件未包含 CoreDNS 自訂設定步驟，SOP 為 Lab 環境補強（使 Pod 能解析 PCE FQDN）。
- **MicroK8s**：SOP 用於 MicroK8s 環境；原廠未正式支援，建議在 SOP 中加入免責說明。
- **machineID 確認**：原廠文件未提及此步驟，SOP 補強合理（避免相同 machineID 導致 Illumio 識別問題）。
