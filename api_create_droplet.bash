curl -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $auth_token" -d '{"name":"jitsi-c2-4vcpu-8gb","region":"fra1","size":"c2-4vcpu-8gb","image":"debian-10-x64","ssh_keys":["a4:b9:12:b0:08:8e:b5:81:56:f1:f5:52:61:d4:03:8f"],"user_data":"#!/bin/bash\napt-get update\napt-get install git -y\ngit clone https://github.com/koloniforlag/jitsi-deploy\ncd jitsi-deploy\n./jitsi-deploy-debian10.bash SERVICE_ADDRESS &> jitsi-deploy.log\n","tags":["jitsi"]}' "https://api.digitalocean.com/v2/droplets/"