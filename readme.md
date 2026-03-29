# Auto-Scaling from Local VM to Google Cloud Platform (GCP) 

This assignment automates scaling from a local VirtualBox VM to Google Cloud Platform (GCP) when CPU/memory usage exceeds **75%**. It provisions GCP resources (Managed Instance Groups, Load Balancer) dynamically and redirects traffic seamlessly.

---

## Features ✨
- **Local VM Setup**: VirtualBox VM running Apache + resource monitoring script.
- **Threshold-Based Scaling**: Auto-provisions GCP resources when CPU/memory > 75%.
- **Traffic Redirection**: Routes requests to GCP Load Balancer once scaling triggers.
- **Cost-Efficient Cleanup**: Script to delete all GCP resources after testing.

---

## Prerequisites ✅
- **Local Machine**:
  - VirtualBox ([Download](https://www.virtualbox.org/))
  - Linux-based VM (e.g., Lubuntu)
- **GCP Account**:
  - Billing-enabled project.
  - IAM roles: `Compute Admin`, `Storage Admin`, `Service Account User`.
- **Tools**:
  - Google Cloud SDK (`gcloud` CLI)
  - `stress` (for load testing)

---

## Setup Guide 🛠️

### 1. Create Local VM in VirtualBox
- **OS**: Lubuntu (or lightweight Linux distro).
- **Resources**: 2 vCPUs, 4GB RAM.
- **Network**: Use *Bridged Adapter* for internet access.
- **Update Packages**:
  ```bash
  sudo apt update && sudo apt upgrade -y
  
### 2. Clone Repository & Configure Script

```bash
git clone https://github.com/sudoshubh/VCC_Assignment3.git
cd VCC_Assignment3
```
- **Edit auto_scaling_script_gcs.sh:**
```bash
GCP_PROJECT="YOUR_PROJECT_ID"   # Replace with your GCP Project ID
ZONE="us-central1-a"            # Replace with your GCP zone
```
- **Make the script executable:**
```bash
chmod +x auto_scaling_script_gcs.sh
```
### 3. Authenticate with GCP
```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```
### 4. Run the Auto-Scaling Script
```bash
./auto_scaling_script_gcs.sh
```
#### What the script does:

- **Installs Google Cloud SDK (if missing)**
- **Creates a GCP service account with required roles**
- **Configures Apache and deploys a sample PHP app**
- **Starts monitoring CPU/memory usage every 90 seconds**
---
## Testing Auto-Scaling ⚡

### 1. Trigger High CPU Usage
```bash
sudo apt install stress
stress -c 2 --timeout 60    # Spikes CPU usage to breach 75% threshold
```
### 2. Observe Scaling Actions
#### The script will:

- **Upload web content to Google Cloud Storage (GCS)**
- **Create a GCP Instance Template, Managed Instance Group (MIG), and Load Balancer**
- **Redirect traffic to GCP via Apache rewrite rules**

### 3. Verify in GCP Console
- **Instance Groups: Check for new VM instances**
- **Load Balancer: Confirm traffic forwarding rules**
- **Cloud Storage: Verify uploaded web content**

---
## Cleanup Resources 🧹
#### Avoid unnecessary charges by deleting all GCP resources:
```bash
chmod +x delete_resources_gcs.sh
./delete_resources_gcs.sh
```
---
## 📚 References
- [GCP SDK](https://cloud.google.com/sdk?hl=en)
- [GCP CLI](https://cloud.google.com/cli?hl=en)
- [Auto-scaling in GCP](https://cloud.google.com/compute/docs/autoscaler)
- [Firewall Rules](https://cloud.google.com/firewall/docs/firewalls)
- [IAM Overview](https://cloud.google.com/iam/docs/overview)

---

## 👥 Authors
- Shubham Sharma (M25AI2024@iitj.ac.in)
