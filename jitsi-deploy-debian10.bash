#! /bin/bash
# Installs Jitsi Meet on a Debian 10 machine. Also installs a Letsencrypt
# certificate for the FQDN provided as an argument to the script.

SERVICE_ADDRESS=$1

if ! [[ -n $SERVICE_ADDRESS ]]; then
  echo 'Error: This script requires a FQDN for the service as an argument.'
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
# Add FQDN to debconf values
sed -i "s,FQDN,${SERVICE_ADDRESS}," ./debconf-values
# Pre-seed debconf database
debconf-set-selections ./debconf-values
# Install the Jitsi packages
apt-get install jitsi-meet -y
# Letsencrypt stuff
/usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh
