#!/bin/bash

# Create a Debian 10 droplet on Digital Ocean and configure a Jitsi
# Meet server. Different machines sizes can be chosen by specifying
# number of vCPUs as first argument.

# Required environment variables
[[ -n $JITSI_ADDRESS ]] && [[ -n $API_TOKEN ]] || {
  echo 'Error: Please set both JITSI_ADDRESS and API_TOKEN.'
  exit 1
}

readonly CPU_COUNT=$1
case "$CPU_COUNT" in
  2|4|8|16)
    # Dedicated, CPU-optimized machine
    readonly MACHINE_SIZE="c-${CPU_COUNT}"
    ;;
  1)
    # Smallest possible machine
    readonly MACHINE_SIZE=s-1vcpu-1gb
    ;;
  *)
    # Default machine size is 4 cores
    echo "No vCPU count specified on command line; using default of 4 vCPUs."
    readonly MACHINE_SIZE="c-4"
    ;;
esac

print_json_payload() {
  cat <<EOF
{
  "name": "jitsi-${MACHINE_SIZE}",
  "region": "fra1",
  "size": "$MACHINE_SIZE",
  "image": "debian-10-x64",
  "ssh_keys": [
    29452254,
    29705636
  ],
  "user_data": "
    #!/bin/bash
    apt-get update
    apt-get install git -y
    git clone https://github.com/koloniforlag/jitsi-deploy
    cd jitsi-deploy
    ./jitsi-deploy-debian10.bash ${JITSI_ADDRESS} &> jitsi-deploy.log
  ",
  "tags": [
    "jitsi"
  ]
}
EOF
}

curl \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -X POST --data "$(print_json_payload)" \
  "https://api.digitalocean.com/v2/droplets/"
