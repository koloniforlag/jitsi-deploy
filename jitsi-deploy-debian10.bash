#! /bin/bash
# Installs Jitsi Meet on Debian 10.

set -x

JITSI_ADDRESS=$1
LETSENCRYPT_SCRIPT=/usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh

if ! [[ -n $JITSI_ADDRESS ]]; then
  echo 'Error: This script requires a DNS name for the service as an argument.'
  exit 1
fi

# Refresh repos and update all installed packages
apt-get update ; apt-get upgrade -y
# Install required tools
apt-get install gnupg2 curl -y
# Fetch Jitsi GPG key
curl https://download.jitsi.org/jitsi-key.gpg.key | sudo sh -c 'gpg --dearmor > /usr/share/keyrings/jitsi-keyring.gpg'
# Configure Jitsi repos
echo 'deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/' | tee /etc/apt/sources.list.d/jitsi-stable.list > /dev/null
# Update repos
apt-get update
# Add current DNS name to debconf values
sed -i "s,FQDN,${JITSI_ADDRESS}," ./debconf-values
# Pre-seed debconf database
debconf-set-selections ./debconf-values
# Install the Jitsi packages
apt-get install jitsi-meet -y
# Install Prometheus Node Exporter
apt-get install prometheus-node-exporter -y
# Remove email prompt in Let's Encrypt script
sed -i "s,^read EMAIL$,EMAIL=info@${JITSI_ADDRESS}," $LETSENCRYPT_SCRIPT
# Install a Let's Encrypt certificate if/when $JITSI_ADDRESS
# resolves to this host
while true; do
  curl --silent "${JITSI_ADDRESS}/thisisatest" >/dev/null &&
    grep -q thisisatest /var/log/nginx/access.log && {
      $LETSENCRYPT_SCRIPT
      exit
    }
  sleep 5
done
