#!/bin/bash

# Configuration
GCP_PROJECT="autoscaling-project-449817"     # Replace with your GCP project ID
ZONE="us-central1-a"              # Replace with your GCP zone
THRESHOLD=75                          # Scaling threshold (CPU/Memory %)
GCP_LOAD_BALANCER_IP=""  
SERVICE_ACCOUNT_NAME="auto-scale-sa"  # Name for the service account
SERVICE_ACCOUNT_KEY="/tmp/service-account-key.json"  # Path to store the key
INSTANCE_GROUP="auto-scale-group"     # GCP managed instance group name
INSTANCE_TEMPLATE="auto-scale-template" # GCP instance template
ACTIVE_GCP_VMS_FILE="/tmp/active_gcp_vms.txt"    # File to store the number of active GCP VMs
BUCKET_NAME="web-content-bucket-$GCP_PROJECT"  # Unique bucket name

# ------------------------------------------------------------------------------------
# Step 1: Install Google Cloud SDK
# ------------------------------------------------------------------------------------

install_gcloud() {
  echo "[+] Installing Google Cloud SDK..."
  if ! command -v gcloud &> /dev/null; then
    sudo apt update > /dev/null 2>&1
    sudo apt install -y apt-transport-https ca-certificates curl gnupg > /dev/null 2>&1
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - > /dev/null 2>&1
    sudo apt update > /dev/null 2>&1
    sudo apt install -y google-cloud-sdk > /dev/null 2>&1
  fi
}

# ------------------------------------------------------------------------------------
# Step 2: Check authentication and authenticate if necessary
# ------------------------------------------------------------------------------------

check_and_authenticate() {
  echo "[+] Checking if user is authenticated..."

  # Check if the user is authenticated
  ACTIVE_ACCOUNT=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)")

  if [ -z "$ACTIVE_ACCOUNT" ]; then
    echo "[-] No active account found. Authenticating now..."
    gcloud auth login
    if [ $? -ne 0 ]; then
      echo "[-] Authentication failed. Please try again."
      exit 1
    fi
  else
    echo "[+] Active account found: $ACTIVE_ACCOUNT"
  fi

  # Set the project for gcloud
  gcloud config set project $GCP_PROJECT
}

# ------------------------------------------------------------------------------------
# Step 3: Create a GCP service account and generate a key
# ------------------------------------------------------------------------------------

create_service_account() {
  echo "[+] Creating GCP service account: $SERVICE_ACCOUNT_NAME..."
  if ! gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
    --description="Service account for auto-scaling" \
    --display-name="Auto Scale SA" \
    --project=$GCP_PROJECT > /dev/null 2>&1; then
    echo "[-] Failed to create service account. Ensure the GCP project ID is correct and billing is enabled."
    exit 1
  fi

  echo "[+] Assigning roles to the service account..."
  # Grant Compute Admin role
  gcloud projects add-iam-policy-binding $GCP_PROJECT \
    --member="serviceAccount:$SERVICE_ACCOUNT_NAME@$GCP_PROJECT.iam.gserviceaccount.com" \
    --role="roles/compute.admin" > /dev/null 2>&1

  # Grant Service Account User role (required for VM operations)
  gcloud iam service-accounts add-iam-policy-binding \
    "$SERVICE_ACCOUNT_NAME@$GCP_PROJECT.iam.gserviceaccount.com" \
    --member="serviceAccount:$SERVICE_ACCOUNT_NAME@$GCP_PROJECT.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser" \
    --project="$GCP_PROJECT" > /dev/null 2>&1
    
  # Grant storage admin role
  gcloud projects add-iam-policy-binding $GCP_PROJECT \
    --member="serviceAccount:$SERVICE_ACCOUNT_NAME@$GCP_PROJECT.iam.gserviceaccount.com" \
    --role="roles/storage.admin" > /dev/null 2>&1
      
  # Grant Storage Object Viewer role
  gcloud projects add-iam-policy-binding $GCP_PROJECT \
    --member="serviceAccount:$SERVICE_ACCOUNT_NAME@$GCP_PROJECT.iam.gserviceaccount.com" \
    --role="roles/storage.objectViewer" > /dev/null 2>&1

  echo "[+] Generating service account key..."
  if ! gcloud iam service-accounts keys create $SERVICE_ACCOUNT_KEY \
    --iam-account="$SERVICE_ACCOUNT_NAME@$GCP_PROJECT.iam.gserviceaccount.com" > /dev/null 2>&1; then
    echo "[-] Failed to generate service account key. Check permissions and try again."
    exit 1
  fi

  echo "[+] Authenticating with the service account..."
  if ! gcloud auth activate-service-account --key-file=$SERVICE_ACCOUNT_KEY > /dev/null 2>&1; then
    echo "[-] Failed to authenticate with the service account. Check the key file and try again."
    exit 1
  fi
}

# ------------------------------------------------------------------------------------

# Function to create GCP instance template
create_gcp() {
    echo "Creating GCP instance template..."
    gcloud compute instance-templates create "$INSTANCE_TEMPLATE" \
    --machine-type=e2-medium \
    --image-project=ubuntu-os-cloud \
    --image-family=ubuntu-2204-lts \
    --tags=http-server \
    --service-account="$SERVICE_ACCOUNT_NAME@$GCP_PROJECT.iam.gserviceaccount.com" \
    --scopes=cloud-platform,storage-ro \
    --metadata-from-file startup-script=<(cat <<'EOF'
#!/bin/bash
# Install required tools
sudo apt update -y
sudo apt install -y apache2 php libapache2-mod-php
sudo apt-get update -qq

# Add Google Cloud SDK repository
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null

# Import Google Cloud GPG key
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - > /dev/null

  # Install Google Cloud SDK
  sudo apt-get update -qq && sudo apt-get install -y -qq google-cloud-cli

# Download web content from GCS
sudo gsutil -m cp -r gs://web-content-bucket-autoscaling-project-449817/* /var/www/html/ 2>&1 | sudo tee /var/log/startup-script.log

# Ensure proper ownership
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html
sudo rm /var/www/html/index.html

# Enable the PHP module for Apache
sudo a2enmod php

# Enable required modules (rewrite, proxy, proxy_http)
sudo a2enmod rewrite
sudo a2enmod proxy
sudo a2enmod proxy_http

# Restart Apache to apply changes
sudo systemctl restart apache2
sudo systemctl enable apache2
EOF
)
            
    echo "Creating GCP managed instance group..."
    gcloud compute instance-groups managed create "$INSTANCE_GROUP" \
        --base-instance-name=web-instance \
        --template="$INSTANCE_TEMPLATE" \
        --size=0 \
        --zone="$ZONE"
        
        echo "Setting up auto-scaling policy for GCP..."
    gcloud compute instance-groups managed set-autoscaling "$INSTANCE_GROUP" \
        --zone="$ZONE" \
        --min-num-replicas=0 \
        --max-num-replicas=5 \
        --target-cpu-utilization=0.60 \
         --cool-down-period=300
         
    gcloud compute instance-groups managed set-named-ports "$INSTANCE_GROUP" \
  		--zone="$ZONE" \
  		--named-ports=http:80
}

# Function to create GCP HTTP Load Balancer
create_gcp_load_balancer() {

# Configure firewall rules
echo "Setting up firewall rules..."
# Allow HTTP traffic
gcloud compute firewall-rules create allow-http \
  --allow=tcp:80 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=http-server

# Allow health checks from Google IP ranges
gcloud compute firewall-rules create allow-health-check \
  --allow=tcp:80 \
  --source-ranges="130.211.0.0/22,35.191.0.0/16" \
  --target-tags=http-server

# ---- LOAD BALANCER SETUP ----
echo "Setting up load balancer..."
# Create a health check
gcloud compute health-checks create http web-health-check \
  --port=80 \
  --check-interval=10s \
  --timeout=5s \
  --healthy-threshold=2 \
  --unhealthy-threshold=3

# Create a backend service
gcloud compute backend-services create web-backend-service \
  --protocol=HTTP \
  --port-name=http \
  --health-checks=web-health-check \
  --global

# Add the instance group to the backend service
gcloud compute backend-services add-backend web-backend-service \
  --instance-group="$INSTANCE_GROUP" \
  --instance-group-zone="$ZONE" \
  --global

# Create a URL map
gcloud compute url-maps create web-url-map \
  --default-service=web-backend-service

# Create a target HTTP proxy
gcloud compute target-http-proxies create web-http-proxy \
  --url-map=web-url-map

# Create a global forwarding rule
gcloud compute forwarding-rules create web-forwarding-rule \
  --global \
  --target-http-proxy=web-http-proxy \
  --ports=80
  
GCP_LOAD_BALANCER_IP=$(gcloud compute forwarding-rules describe web-forwarding-rule --global --format="value(IPAddress)")
    echo "GCP Load Balancer IP: $GCP_LOAD_BALANCER_IP"
}

# Function to configure Apache on the local VM
configure_apache() {
    echo "Configuring Apache on the local VM..."

    # Update and install Apache and PHP
    sudo apt update
    sudo apt install -y apache2 php libapache2-mod-php

    # Set ownership and permissions for the web directory
    sudo chown -R $USER:$USER /var/www/html
    sudo chmod -R 755 /var/www/html

    # Create the index.php file with the provided PHP-based HTML code
    cat <<EOF | sudo tee /var/www/html/index.php > /dev/null
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
</head>
<body>
   <h2>Hello From : <?php echo gethostname(); ?></h2>
</body>
</html>
EOF

    # Initialize the active GCP VMs file with a default value of 0
    echo "0" > "$ACTIVE_GCP_VMS_FILE"

    # Write the Apache configuration
    cat <<EOF | sudo tee /etc/apache2/sites-available/000-default.conf > /dev/null
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    # Use RewriteEngine to conditionally route traffic
    RewriteEngine On

    # Check if the active GCP VMs file contains a value >= 1
    RewriteCond %{REQUEST_URI} ^/$
    RewriteCond $(cat $ACTIVE_GCP_VMS_FILE) ^[1-9]
    RewriteRule ^(.*)$ http://$GCP_LOAD_BALANCER_IP/$1 [P,L]

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

    # Enable the PHP module for Apache
    sudo a2enmod php

    # Enable required modules (rewrite, proxy, proxy_http)
    sudo a2enmod rewrite
    sudo a2enmod proxy
    sudo a2enmod proxy_http

    # Restart Apache to apply changes
    sudo systemctl restart apache2
}

# ------------------------------------------------------------------------------------
# New function: Create bucket and upload web content
# ------------------------------------------------------------------------------------
upload_to_gcs() {
    echo "[+] Creating GCS bucket and uploading web content..."
    
    # Create bucket
    gsutil mb -p $GCP_PROJECT -l us-central1 gs://$BUCKET_NAME
    
    # Copy local web content to bucket
    gsutil -m cp -r /var/www/html/* gs://$BUCKET_NAME/
    
    # Set public read access (adjust permissions as needed)
    gsutil iam ch allUsers:objectViewer gs://$BUCKET_NAME
}



# Function to monitor local VM resources
monitor_local_resources() {
    echo "Monitoring local VM resources..."
    while true; do
        CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
        MEMORY_USAGE=$(free | grep Mem | awk '{print $3/$2 * 100}')

        echo "CPU Usage: $CPU_USAGE%, Memory Usage: $MEMORY_USAGE%"
        
        # Read the number of active GCP VMs from the file
        ACTIVE_GCP_VMS=$(cat $ACTIVE_GCP_VMS_FILE)

        # Check if CPU usage exceeds 75%
        if (( $(echo "$CPU_USAGE > 75" | bc -l) )); then 
            # Inner if: Execute only if active VMs are equal to zero
            if [ "$ACTIVE_GCP_VMS" -eq 0 ]; then
                echo "Resource usage exceeds threshold and no active GCP VMs. Creating new resources..."
                upload_to_gcs
                create_gcp
                create_gcp_load_balancer
                create_check_gcp_vms_script
            else
                echo "Resource usage exceeds threshold and active GCP VMs are present. Scaling to cloud..."
                
                # Get the current size of the instance group
                CURRENT_SIZE=$(gcloud compute instance-groups managed describe "$INSTANCE_GROUP" \
                    --zone="$ZONE" \
                    --format="value(targetSize)")

                # Increase the size by 1
                NEW_SIZE=$((CURRENT_SIZE + 1))

                # Set the new size
                gcloud compute instance-groups managed resize "$INSTANCE_GROUP" \
                    --zone="$ZONE" \
                    --size="$NEW_SIZE"
            fi
        fi	

        sleep 90  # Check every 90 seconds
    done
}

create_check_gcp_vms_script() {
    echo "Creating script to check active GCP VMs..."

    # Use unindented EOF to avoid issues
    cat <<EOF | sudo tee /usr/local/bin/check_gcp_vms.sh > /dev/null
#!/bin/bash

# Set the necessary environment variables
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ACTIVE_GCP_VMS_FILE="/tmp/active_gcp_vms.txt"
APACHE_CONFIG="/etc/apache2/sites-available/000-default.conf"

# Fetch the GCP Load Balancer IP dynamically
GCP_LOAD_BALANCER_IP=$(gcloud compute forwarding-rules describe web-forwarding-rule --global --format="value(IPAddress)")

# Fetch the number of active GCP VMs
active_gcp_vms=\$(gcloud compute instances list --filter="status=RUNNING" --format="value(name)" | wc -l)

# Update the active GCP VMs file
echo "\$active_gcp_vms" > "\$ACTIVE_GCP_VMS_FILE"

# Rewrite the Apache configuration file
cat <<APACHE_EOF | sudo tee "\$APACHE_CONFIG" > /dev/null
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    # Use RewriteEngine to conditionally route traffic
    RewriteEngine On

    # Check if the active GCP VMs file contains a value >= 1
    RewriteCond %{REQUEST_URI} ^/\$
    RewriteCond \$(cat \$ACTIVE_GCP_VMS_FILE) ^[1-9]
    RewriteRule ^(.*)\$ http://\$GCP_LOAD_BALANCER_IP/\$1 [P,L]

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
APACHE_EOF

# Restart Apache to apply changes
sudo systemctl restart apache2
EOF

    # Make the script executable
    sudo chmod +x /usr/local/bin/check_gcp_vms.sh

    # Schedule the script to run every 1 minute
    (crontab -l 2>/dev/null; echo "*/1 * * * * . /etc/profile; /usr/local/bin/check_gcp_vms.sh > /dev/null 2>&1") | crontab -

    # Configure passwordless sudo for the script
    echo "Configuring passwordless sudo for Apache configuration updates..."
    sudo bash -c 'echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/apache2/sites-available/000-default.conf, /usr/bin/systemctl restart apache2" >> /etc/sudoers.d/apache-updates'
}
# ------------------------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------------------------

main() {
  install_gcloud
  check_and_authenticate
  create_service_account
  configure_apache
  monitor_local_resources
}

main
