# 🛡️ Ansible CIS Kubernetes Hardening

This comprehensive repository provides a robust suite of **Ansible Playbooks** meticulously engineered to **automatically check and apply security hardening** across your **Kubernetes cluster**. It strictly adheres to the latest **CIS Kubernetes Benchmark** (v1.11-v1.12), ensuring your **Control Plane (Master)** and **Worker Nodes** achieve and maintain the highest level of security compliance.

Support for Kubernetes versions: v1.29 to v1.34.

## 1. 📖 Overview

This project utilizes Ansible to execute the necessary checks and configuration changes required to achieve high security compliance following the latest versions of the **[CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)**

**Scope of Hardening**

This playbook specifically targets and addresses the following critical sections of the CIS Kubernetes Benchmark, ensuring a highly secured cluster configuration:

| **CIS Section**                | **Compliance Status** |
| ------------------------------ | --------------------- |
| 1. Control Plane Components    | 59/60 rules           |
| 2. ETCD                        | 8/8 rules             |
| 3. Control Plane Configuration | 5/5 rules             |
| 4. Worker Node                 | 26/26 rules           |

**Special Note on CIS Rule 1.2.1 (Anonymous Auth):**

This hardening suite explicitly **drops/ignores Rule 1.2.1** (Ensure that the `--anonymous-auth` argument is set to `false`). We maintain `--anonymous-auth` (on the kube-apiserver) as **`true`** because this configuration is still considered secure due to the strict authorization enforced by **RBAC** (Role-Based Access Control).

**Key Goals:**
- **Automation**: Eliminate manual intervention and mitigate human error.
- **Idempotency**: Ensure running the Playbook multiple times does not cause errors or unnecessary state changes.
- **Security**: Enforce hardened configurations for etcd, the API Server, Kubelet, and other critical components.
---
## 2. 📝 Inventory Configuration

The inventory file (`hosts.ini`) is where you define your cluster structure and connection variables. The structure must clearly separate Control Plane (Master) and Worker Nodes.

Example `inventory/hosts.ini`

```
[kube_control_plane]
k8s-m1 ansible_host=10.0.0.4
k8s-m2 ansible_host=10.0.0.5
k8s-m3 ansible_host=10.0.0.6

[etcd]
k8s-etcd1 ansible_host=10.0.0.1
k8s-etcd2 ansible_host=10.0.0.2
k8s-etcd3 ansible_host=10.0.0.3

[kube_node]
k8s-w1 ansible_host=10.0.0.7
k8s-w2 ansible_host=10.0.0.8

[all:vars]
ansible_user=root            
ansible_python_interpreter=/usr/bin/python3
ansible_become=true             
```

---
## 3. 🚀 Execution Steps
### 3.1. Connectivity Check

Always run a connectivity test first to ensure Ansible can successfully SSH and elevate privileges (`sudo`) on all target nodes:

```
ansible all -i inventory/hosts.ini -m ping
```
### 3.2 Running Hardening Playbooks

#### For kubespray

```
ansible-playbook -i inventory/host.ini playbooks/apply-cis.yml --extra-vars "kubespray=true"
```
#### For kubeadm

```
ansible-playbook -i inventory/host.ini playbooks/apply-cis.yml 
```
#### For kubelet approve

```
# For kubespray
ansible-playbook -i inventory/staging.ini playbooks/apply-cis.yml --extra-vars "kubespray=true" --extra-vars "kubelet_approver=true"

# For kubeadm
ansible-playbook -i inventory/staging.ini playbooks/apply-cis.yml --extra-vars "kubelet_approver=true"
```
### 3.3 Running with docker

```
docker run --rm -it \
  -v ~/.ssh/id_rsa:/home/ansible/.ssh/id_rsa:ro \
  -v ./inventory:/tmp/inventory \
  ghcr.io/qhungwork666/ansible-cis-kubernetes:1.0 \
  ansible-playbook \
    -i /tmp/inventory/host.ini \
    playbooks/apply-cis.yml \
    --private-key /home/ansible/.ssh/id_rsa \
    --extra-vars "kubespray=true"
```

---
## 4. 📌 Configuration and Key Notes

### 4.1. Access and User Management

- **`ansible_become=true`**: This is essential. Most CIS hardening changes require **root privileges** (e.g., changing file ownership, editing service configurations).
- **Non-root User:** If you use `ansible_user=ubuntu`, ensure this user has **passwordless sudo** access configured on the target machines.
### 4.2. Cluster Networking Variables

Before running the playbooks, you **must** configure the specific network ranges used by your cluster. These variables are crucial for the **kubelet service connectivity** to the cluster components.

| **Variable**          | **Example Value**  | **Description**                                                                        |
| --------------------- | ------------------ | -------------------------------------------------------------------------------------- |
| `kube_pods_subnet`    | `"192.168.0.0/16"` | The IP range used for all Pods in the cluster (e.g., Flannel/Calico/Cilium).           |
| `kube_svc_subnet`     | `"10.233.0.0/16"`  | The IP range reserved for Kubernetes Services (ClusterIPs).                            |
| `kube_node_addresses` | `"172.29.50.0/24"` | The internal network CIDR where your Kubernetes Nodes reside.                          |
| `kubelet_allow_ips`   |                    | Additional IP/IP ranges (CIDRs) explicitly allowed to access the Kubelet API endpoint. |
### 4.3 Kubelet Server Certificate Rotation

This project integrates the external controller [kubelet-serving-cert-approver](https://github.com/alex1989hu/kubelet-serving-cert-approver) to manage Kubelet server certificates automatically. The feature is enabled by default via the `kubelet_approver: true` variable. This configuration is used to address or replace several CIS controls:
- **Replaces CIS 4.2.9** (Ensure that `--tls-cert-file` and `--tls-private-key-file` arguments are set) by enabling dynamic certificate management.
- **Complements CIS 4.2.11** (Verify that the `RotateKubeletServerCertificate` argument is set to `true`) by providing the mechanism to approve the rotation requests.

Crucially, this setup enables `serverTLSBootstrap` on the Kubelet, allowing the server certificate to be automatically requested and rotated via the Kubernetes Certificate Signing Request (CSR) API.

 **⚠️ Execution Note**

The task for deploying and configuring the Kubelet Server Certificate Approver is executed exclusively on the **first Control Plane node** listed in the Ansible inventory (`kube_control_plane[0]`).

It is critical to ensure that this node is fully functional and has a valid `kubeconfig` configured to communicate with the cluster's API server, as it performs privileged `kubectl` operations (specifically managing CSRs) required for the certificate rotation mechanism to function.

**Required Variables for Approver Integration:**

| **Variable**               | **Value** | **Description**                                                                                                                  |
| -------------------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `kubelet_approver`         | `true`    | Enables the deployment and configuration of the `kubelet-serving-cert-approver` controller.                                      |
| `kubelet_approver_version` | `'0.9.3'` | Specifies the desired version of the controller image to deploy.                                                                 |
| `registry_local`           | `null`    | Ensures the image is pulled from its official public registry (e.g., Docker Hub or Quay) unless an internal mirror is specified. |
### 4.4 Encrypting Confidential Data at Rest

To comply with the CIS requirement for securing sensitive data stored in **etcd**, this Playbook implements **Secret Encryption at Rest** using the **AES-CBC provider**.

This feature is controlled by the following variable, which defines the encryption key used in the `EncryptionConfiguration` file.

Reference: [Kubernetes Documentation on Encrypting Data](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/) 

| **Variable**      | **Default Value**                  | **Description**                                                                                                                                                                                      |
| ----------------- | ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `encrypt_secrets` | `Encrypting-data-etcd!@#123456789` | **Defines the encryption key** for the `EncryptionConfiguration` applied to the API Server. **NOTE:** For production environments, this key **must be changed** to a long, randomly generated value. |
### 4.5. API-server Configuration Files

The following static files, located in the `roles/kube_cis_master/files` directory, enforce several **CIS security controls on the Control Plane**. Review and customize these files based on your organizational policies:

| **File Name**                 | **Purpose and CIS Control Relevance**                                                                                                                                                                                                                                                  |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `audit-policy.yml`            | Defines the rules for Kubernetes **Audit Logging** (CIS 1.2.x). This policy determines which requests are logged and at what level, crucial for security visibility.                                                                                                                   |
| `admission-configuration.yml` | Defines the configuration for **Admission Controllers** (CIS 1.3.x). This controls crucial security mechanisms like **EventRateLimit** and other controllers that enforce security policies across the cluster, including protecting against API abuse and ensuring cluster stability. |
### 4.6 Kubespray Deployment Compatibility

This hardening playbook supports clusters deployed using tools like Kubespray or standard **Kubeadm**. Use the **`kubespray: false`** default variable to control logic paths specific to Kubespray installations

If your cluster was deployed via Kubespray, the Etcd deployment is inherently secure: Kubespray typically deploys **Etcd as a Systemd service (not a Static Pod)**. This method guarantees that the entire **Etcd Section (CIS 1.2)** of the CIS Kubernetes Benchmark is **fully compliant by default**.

