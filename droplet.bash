#!/bin/bash

# Manage a Debian 10 Digital Ocean droplet configured as a Jitsi Meet
# server. Different machine sizes can be chosen by specifying number
# of CPU cores as a second argument to the script.

# This script requires the following environment variables to be set:
# JITSI_ADDRESS = The DNS address to your Jitsi instance
# API_TOKEN     = Your Digital Ocean API auth token

# N.B. The Digital Ocean IDs of two authorized SSH public keys are
# hardcoded into this script.

# Global variables
declare CPU_COUNT     # Desired number of CPU cores for the droplet
declare MACHINE_SIZE  # The droplet's virtual hardware configuration
declare DROPLET_ID    # The ID of the Digital Ocean droplet created by the script
declare FLOAT_IP      # The first freely available DO "floating IP"

main() {
  case "$1" in
    create)
      pre_checks_and_start_logging
      set_machine_size "$2"
      create_machine
      assign_float_ip
      verify_cert
      ;;
    show)
      pre_checks_and_start_logging
      show_droplet
      ;;
    stop)
      pre_checks_and_start_logging
      stop_droplet
      ;;
    destroy)
      pre_checks_and_start_logging
      destroy_droplet
      ;;
    getid)
      pre_checks_and_start_logging
      get_droplet_id
      ;;
    assignfloat)
      pre_checks_and_start_logging
      assign_float_ip
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

usage() {
  cat <<-EOF
		Usage:
		  $(basename $0) create [<cpu_count>] | show | stop | destroy
	EOF
}

pre_checks_and_start_logging() {
  # Required environment variables
  [[ -n $JITSI_ADDRESS ]] && [[ -n $API_TOKEN ]] || {
    echo 'Error: Please set both JITSI_ADDRESS and API_TOKEN.'
    exit 1
  }
  exec >> droplet.log 2>&1
  set -ex
  date
}

set_machine_size() {
  readonly CPU_COUNT=$1
  case "$CPU_COUNT" in
    2|4|8|16)
      # "CPU-optimized" machine with dedicated cores
      readonly MACHINE_SIZE="c-${CPU_COUNT}"
      ;;
    1)
      # Smallest possible machine
      readonly MACHINE_SIZE=s-1vcpu-1gb
      ;;
    *)
      # Default is 4 dedicated cores
      echo "INFO: No CPU count specified on command line; using default of 2 CPUs."
      readonly MACHINE_SIZE="c-2"
      ;;
  esac
}

creation_json_payload() {
  cat <<EOF
{
  "name": "jitsi-${MACHINE_SIZE}",
  "region": "fra1",
  "size": "$MACHINE_SIZE",
  "image": "debian-10-x64",
  "ssh_keys": [
    29452254,
    29819106
  ],
  "user_data": "#!/bin/bash\n
apt-get update\n
apt-get install git -y\n
git clone https://github.com/koloniforlag/jitsi-deploy\n
cd jitsi-deploy\n
./jitsi-deploy-debian10.bash ${JITSI_ADDRESS} &> jitsi-deploy.log\n",
  "tags": [
    "jitsi"
  ]
}
EOF
}

curl_cmd() {
  # Boilerplate for curl API call. Add arguments to this function.
  curl --silent \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    "$@"
}

get_droplet_id() {
  # Get ID of the first droplet tagged "jitsi".
  # N.B. not intended to work with multiple Jitsi droplets.
  # We make several attempts, with a few seconds in between, before exiting
  # with a warning if we failed to get an ID.
  local droplet_id
  local countdown=30
  while [[ $countdown -gt 0 ]]; do
    droplet_id=$(
      curl_cmd -X GET \
        "https://api.digitalocean.com/v2/droplets?tag_name=jitsi" |
        jq '.droplets[0]|.id?'
    )
    if [[ $droplet_id =~ [0-9]+ ]]; then
      echo $droplet_id
      return
    else
      sleep 2
      (( countdown-=2 ))
    fi
  done
  echo 'Error: Failed to find droplet ID!'
  exit 1
}

get_float_ip() {
# Get any unused floating IP
curl_cmd -X GET \
  "https://api.digitalocean.com/v2/floating_ips" |
  jq '' |
  grep -B1 '"droplet": null' |
  grep -o -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'
}

create_machine() {
  # Create a new droplet
  curl_cmd -X POST \
    --data "$(creation_json_payload)" \
    "https://api.digitalocean.com/v2/droplets/" |
    jq -r ''
}

droplet_status() {
  # Get status of a known droplet
  curl_cmd -X GET \
    "https://api.digitalocean.com/v2/droplets/${DROPLET_ID}" |
    jq -r '.droplet|.status?'
}

show_droplet() {
  # Show the first droplet with the tag "jitsi"
  curl_cmd -X GET \
    "https://api.digitalocean.com/v2/droplets/$(get_droplet_id)" |
    jq -r ''
}

stop_droplet() {
  # Shut down ALL droplets with the tag "jitsi"
  curl_cmd -X POST \
    --data '{ "type": "shutdown" }' \
    "https://api.digitalocean.com/v2/droplets/actions?tag_name=jitsi" |
    jq -r ''
}

destroy_droplet() {
  # Destroy ALL droplets with the tag "jitsi"
  curl_cmd -X DELETE \
    "https://api.digitalocean.com/v2/droplets?tag_name=jitsi" |
    jq -r ''
}

assign_float_ip() {
  readonly DROPLET_ID=$(get_droplet_id)
  readonly FLOAT_IP=$(get_float_ip)
  if [[ -n "$FLOAT_IP" ]]; then
    # Assign the available floating IP to our new machine.
    # If the machine is not ready after 5 minutes, we give up.
    local countdown=300
    while [[ $countdown -gt 0 ]]; do
      if [[ $(droplet_status) = active ]]; then
        # Machine is ready. Let's try to assign our floating IP to it.
        local data=$(cat <<-EOF
					{ "type": "assign", "droplet_id": ${DROPLET_ID} }
				EOF
        )
        curl_cmd -X POST \
          --data "$data" \
          "https://api.digitalocean.com/v2/floating_ips/${FLOAT_IP}/actions" |
          jq -r ''
        break
      else
        # Machine is not ready. Let's wait some more.
        sleep 5
        ((countdown-=5))
      fi
    done
    echo "Warning: Floating IP not assigned. Timed out waiting for the machine to become ready."
  else
    echo "Warning: No available floating IP found."
  fi
}

verify_cert() {
  local countdown=300  # Fail after five minutes of repeated attempts
  local email_subject='Jitsi TLS status:'
  local openssl_result

  sleep 2m  # No use in trying to connect right away; the installation takes a while.

  # We don't want the script to abort if the openssl command fails:
  set +e

  while [[ $countdown -gt 0 ]]; do
    openssl_result=$(
      echo '' | openssl s_client -connect ${FLOAT_IP}:443 2>&1 | grep -B1 '^verify '
    )
    if [[ $openssl_result =~ "Let's Encrypt" ]]; then
      echo "$openssl_result" | mail -s "${email_subject} OK" root
      return
    else
      sleep 10
      (( countdown-=10 ))
    fi
  done
  echo "$openssl_result" | mail -s "${email_subject} FAIL" root
}

main "$@"
