#! /bin/bash
# Installs Jitsi Meet on Debian 10.

set -e

SERVICE_ADDRESS=$1

if ! [[ -n $SERVICE_ADDRESS ]]; then
  echo 'Error: This script requires a DNS name for the service as an argument.'
  exit 1
fi

# Update repos
apt-get update -y
# Install required tools
apt-get install gnupg2 curl -y
# Fetch Jitsi GPG key
curl https://download.jitsi.org/jitsi-key.gpg.key | sudo sh -c 'gpg --dearmor > /usr/share/keyrings/jitsi-keyring.gpg'
# Configure Jitsi repos
echo 'deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/' | tee /etc/apt/sources.list.d/jitsi-stable.list > /dev/null
# Update repos
apt-get update -y
# Add current DNS name to debconf values
sed -i "s,FQDN,${SERVICE_ADDRESS}," ./debconf-values
# Pre-seed debconf database
debconf-set-selections ./debconf-values
# Install the Jitsi packages
apt-get install jitsi-meet -y
# Install Let's Encrypt certificate
/usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh
