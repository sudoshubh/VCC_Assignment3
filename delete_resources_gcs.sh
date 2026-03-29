#!/bin/bash
set -euo pipefail

# Set variables (customize these!)
PROJECT_ID="autoscaling-project-449817"
REGION="us-central1"
ZONE="us-central1-a"
INSTANCE_GROUP="auto-scale-group"     # GCP managed instance group name
INSTANCE_TEMPLATE="auto-scale-template" # GCP instance template
ACTIVE_GCP_VMS_FILE="/tmp/active_gcp_vms.txt"    # File to store the number of active GCP VMs
BUCKET_NAME="web-content-bucket-$PROJECT_ID"  # GCS bucket name
SERVICE_ACCOUNT_NAME="auto-scale-sa"  # Service account name

# Load Balancer Components
BACKEND_SERVICE="web-backend-service"
HEALTH_CHECK="web-health-check"
URL_MAP="web-url-map"
TARGET_PROXY="web-http-proxy"
FORWARDING_RULE="web-forwarding-rule"

# Delete Load Balancer Components
echo "Deleting Load Balancer components..."
gcloud compute forwarding-rules delete "$FORWARDING_RULE" --global --quiet
gcloud compute target-http-proxies delete "$TARGET_PROXY" --quiet
gcloud compute url-maps delete "$URL_MAP" --quiet
gcloud compute backend-services delete "$BACKEND_SERVICE" --global --quiet
gcloud compute health-checks delete "$HEALTH_CHECK" --quiet

# Delete Managed Instance Group
echo "Deleting Managed Instance Group..."
gcloud compute instance-groups managed delete "$INSTANCE_GROUP" --zone="$ZONE" --quiet

# Delete Instance Template
echo "Deleting Instance Template..."
gcloud compute instance-templates delete "$INSTANCE_TEMPLATE" --quiet

# Delete Firewall Rules
echo "Deleting Firewall Rules..."
gcloud compute firewall-rules delete allow-http allow-health-check --quiet

# Delete GCS Bucket
echo "Deleting GCS Bucket..."
gsutil rm -r gs://$BUCKET_NAME || echo "Bucket $BUCKET_NAME not found or already deleted"

# Delete Service Account
echo "Deleting Service Account..."
# Remove IAM policy bindings first
gcloud projects remove-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/compute.admin" --quiet || true

gcloud projects remove-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/storage.objectViewer" --quiet || true

# Remove the roles/iam.serviceAccountUser role
gcloud projects remove-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser" --quiet || true

# Remove the roles/iam.storage.admin role
gcloud projects remove-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/iam.storage.admin" --quiet || true

# Delete the service account
gcloud iam service-accounts delete "$PROJECT_ID" --quiet || true

echo "All resources have been deleted successfully."
