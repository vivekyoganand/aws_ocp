#!/bin/bash

# Variables
OCP_VERSION="4.14.9"
AWS_REGION="ap-south-1"
CLUSTER_NAME="ocp"
BASE_DOMAIN="ocplocal.in"
INSTALL_DIR="/home/ec2-user/ocp-install"
ACTUAL_USER="ec2-user"
AWS_ACCESS_KEY=
AWS_SECRET_KEY=

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

# Function to check command status
check_status() {
    if [ $? -eq 0 ]; then
        log "$1 successful"
    else
        error "$1 failed"
        exit 1
    fi
}

# Setup AWS Configuration
setup_aws() {
    log "Setting up AWS Configuration..."

    # Export AWS credentials to environment
    export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY}
    export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_KEY}
    export AWS_DEFAULT_REGION=${AWS_REGION}

    # Verify AWS access
    aws sts get-caller-identity
    check_status "AWS authentication"
}

# Download OpenShift installer and client
download_openshift_tools() {
    log "Downloading OpenShift installer and client..."

    cd /home/${ACTUAL_USER}

    # Download installer and client
    wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-linux-${OCP_VERSION}.tar.gz
    wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-client-linux-${OCP_VERSION}.tar.gz

    # Extract files
    tar -xvf openshift-install-linux-${OCP_VERSION}.tar.gz
    tar -xvf openshift-client-linux-${OCP_VERSION}.tar.gz

    # Move binaries
    mv openshift-install /usr/local/bin/
    mv oc kubectl /usr/local/bin/

    # Clean up
    rm -f openshift-install-linux-${OCP_VERSION}.tar.gz openshift-client-linux-${OCP_VERSION}.tar.gz README.md

    # Verify installation
    openshift-install version
    oc version
    check_status "OpenShift tools installation"
}

# Generate SSH key
generate_ssh_key() {
    log "Generating SSH key..."
    mkdir -p /home/${ACTUAL_USER}/.ssh
    ssh-keygen -f /home/${ACTUAL_USER}/.ssh/ocp4-aws-key -N ''
    chown -R ${ACTUAL_USER}:${ACTUAL_USER} /home/${ACTUAL_USER}/.ssh
    check_status "SSH key generation"
}

# Create install config
create_install_config() {
    log "Creating installation configuration..."

    # Create install directory
    mkdir -p ${INSTALL_DIR}
    chown ${ACTUAL_USER}:${ACTUAL_USER} ${INSTALL_DIR}

    # Get pull secret
    log "Please enter your Red Hat pull secret (paste and press Enter, then Ctrl+D):"
    PULL_SECRET=$(cat)

    # Create install-config.yaml
    cat << EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    aws:
      type: m5.2xlarge
  replicas: 0
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      type: m5.2xlarge
  replicas: 1
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: ${AWS_REGION}
pullSecret: '${PULL_SECRET}'
sshKey: '$(cat /home/${ACTUAL_USER}/.ssh/ocp4-aws-key.pub)'
EOF

    # Backup config
    cp ${INSTALL_DIR}/install-config.yaml ${INSTALL_DIR}/install-config.yaml.backup
    chown ${ACTUAL_USER}:${ACTUAL_USER} ${INSTALL_DIR}/install-config.yaml*

    check_status "Install config creation"
}

# Install cluster
install_cluster() {
    log "Starting cluster installation..."
    cd ${INSTALL_DIR}
    openshift-install create cluster --dir=${INSTALL_DIR} --log-level=info
    check_status "Cluster installation"
}

# Main function
main() {
    log "Starting OpenShift installation"

    # Verify Route53 setup
    if ! aws route53 list-hosted-zones | grep -q ${BASE_DOMAIN}; then
        error "Route53 hosted zone not found. Please run Part 1 first."
        exit 1
    fi

    # Execute steps
    setup_aws
    download_openshift_tools
    generate_ssh_key
    create_install_config
    install_cluster

    # Setup kubeconfig
    mkdir -p /home/${ACTUAL_USER}/.kube
    cp ${INSTALL_DIR}/auth/kubeconfig /home/${ACTUAL_USER}/.kube/config
    chown -R ${ACTUAL_USER}:${ACTUAL_USER} /home/${ACTUAL_USER}/.kube

    log "Installation complete!"
    log "Access your cluster:"
    log "Console: https://console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
    log "API: https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443"
    log "Kubeadmin password:"
    cat ${INSTALL_DIR}/auth/kubeadmin-password
}

# Execute main function
main
