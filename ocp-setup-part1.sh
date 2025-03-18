#!/bin/bash

# Variables
AWS_REGION="ap-south-1"
BASE_DOMAIN="ocplocal.in"
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

    # Create AWS config directory
    mkdir -p ~/.aws

    # Create credentials file
    cat << EOF > ~/.aws/credentials
[default]
aws_access_key_id = ${AWS_ACCESS_KEY}
aws_secret_access_key = ${AWS_SECRET_KEY}
EOF

    # Create config file
    cat << EOF > ~/.aws/config
[default]
region = ${AWS_REGION}
output = json
EOF

    # Set proper permissions
    chmod 600 ~/.aws/credentials ~/.aws/config

    # Export AWS credentials to environment
    export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY}
    export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_KEY}
    export AWS_DEFAULT_REGION=${AWS_REGION}

    # Verify AWS access
    aws sts get-caller-identity
    check_status "AWS authentication"
}

# Create Route53 hosted zone and verify
create_route53() {
    log "Creating Route53 hosted zone..."

    # Check if hosted zone already exists
    if aws route53 list-hosted-zones | grep -q "${BASE_DOMAIN}"; then
        warning "Hosted zone for ${BASE_DOMAIN} already exists"
        aws route53 list-hosted-zones

        # Get existing nameservers
        ZONE_ID=$(aws route53 list-hosted-zones | grep -A1 "${BASE_DOMAIN}" | grep hostedzone | awk -F'/' '{print $3}' | awk -F'"' '{print $1}')
        NS_RECORDS=$(aws route53 get-hosted-zone --id ${ZONE_ID} --query 'DelegationSet.NameServers' --output text)

        log "Existing nameservers:"
        echo "${NS_RECORDS}"
    else
        # Create new hosted zone
        RESPONSE=$(aws route53 create-hosted-zone \
            --name ${BASE_DOMAIN} \
            --caller-reference "$(date +%s)")

        ZONE_ID=$(echo ${RESPONSE} | jq -r '.HostedZone.Id' | awk -F'/' '{print $3}')
        NS_RECORDS=$(aws route53 get-hosted-zone --id ${ZONE_ID} --query 'DelegationSet.NameServers' --output text)

        log "New hosted zone created with nameservers:"
        echo "${NS_RECORDS}"
    fi

    # Save nameservers to a file
    echo "${NS_RECORDS}" > nameservers.txt

    log "Please update your domain registrar (Hostinger) with these nameservers:"
    cat nameservers.txt

    # Wait for confirmation
    read -p "Have you updated the nameservers at your registrar? (yes/no) " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        error "Please update nameservers before proceeding"
        exit 1
    fi

    # Verify DNS propagation
    log "Verifying DNS propagation (this may take a few minutes)..."
    for NS in ${NS_RECORDS}; do
        log "Checking nameserver: ${NS}"
        dig @${NS} ${BASE_DOMAIN} NS +short
    done
}

# Main function
main() {
    log "Starting OpenShift pre-installation setup"

    # Execute steps
    setup_aws
    create_route53

    log "Pre-installation setup complete!"
    log "Please verify the Route53 configuration before proceeding with Part 2"
    log "Nameservers have been saved to nameservers.txt"
    log "Make sure these nameservers are configured at Hostinger"

    # Show final status
    log "Route53 Hosted Zone Status:"
    aws route53 list-hosted-zones

    log "Nameservers to configure:"
    cat nameservers.txt
}

# Execute main function
main
