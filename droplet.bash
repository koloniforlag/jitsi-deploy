#!/bin/bash

# Manage a Debian 10 Digital Ocean droplet configured as a Jitsi Meet
# server. Different machine sizes can be chosen by specifying number
# of CPU cores as second argument to the script.

exec >> droplet.log 2>&1

date

set -ex

main() {
  check_env_vars
  case "$1" in
    create)
      set_machine_size "$2"
      create_machine
      assign_float_ip
      ;;
    show)
      show_droplet
      ;;
    stop)
      stop_droplet
      ;;
    destroy)
      destroy_droplet
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
      $0 create [<cpu_count>] | show | stop | destroy
	EOF
}

check_env_vars() {
  # Required environment variables
  [[ -n $JITSI_ADDRESS ]] && [[ -n $API_TOKEN ]] || {
    echo 'Error: Please set both JITSI_ADDRESS and API_TOKEN.'
    exit 1
  }
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
      echo "INFO: No CPU count specified on command line; using default of 4 CPUs."
      readonly MACHINE_SIZE="c-4"
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
  curl_cmd -X GET \
    "https://api.digitalocean.com/v2/droplets?tag_name=jitsi" |
    jq '.droplets[0]|.id?'
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
    # First, we wait 2 minutes for the machine to become ready.
    local countdown=120
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
  else
    # We did not find an available floating IP. Let's do nothing.
    :
  fi
}

main "$@"
