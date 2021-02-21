#! /bin/bash
# Installs Jitsi Meet on Debian 10.

set -ex

exec &> ./$(basename $0).log

SERVICE_ADDRESS=$1
LE_SCRIPT=/usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh

if ! [[ -n $SERVICE_ADDRESS ]]; then
  echo 'Error: This script requires a DNS name for the service as an argument.'
  exit 1
fi

# Update repos
apt-get update
# Install required tools
apt-get install gnupg2 curl -y
# Fetch Jitsi GPG key
curl https://download.jitsi.org/jitsi-key.gpg.key | sudo sh -c 'gpg --dearmor > /usr/share/keyrings/jitsi-keyring.gpg'
# Configure Jitsi repos
echo 'deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/' | tee /etc/apt/sources.list.d/jitsi-stable.list > /dev/null
# Update repos
apt-get update
# Add current DNS name to debconf values
sed -i "s,FQDN,${SERVICE_ADDRESS}," ./debconf-values
# Pre-seed debconf database
debconf-set-selections ./debconf-values
# Install the Jitsi packages
apt-get install jitsi-meet -y
# Remove email prompt in Let's Encrypt script
sed -i "s,^read EMAIL$,EMAIL=info@${SERVICE_ADDRESS}," $LE_SCRIPT
# Install a Let's Encrypt certificate if/when $SERVICE_ADDRESS
# resolves to this host
while true; do
  curl "${SERVICE_ADDRESS}/thisisatest" &&
    grep -q thisisatest /var/log/nginx/access.log && {
      $LE_SCRIPT
      exit
    }
  sleep 5
done
