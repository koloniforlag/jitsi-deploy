#! /bin/bash
# This script is intended to be pasted into the "user data" field of a cloud
# provider. Replace "SERVICE_ADDRESS" with the installation's DNS name.
apt-get update -y
apt-get install git -y
git clone https://github.com/koloniforlag/jitsi-deploy
cd jitsi-deploy
./jitsi-deploy-debian10.bash SERVICE_ADDRESS &> jitsi-deploy.log
