#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2024 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

function header_info {
clear
cat <<"EOF"
   __  __      _ _____ 
  / / / /__   (_) __(_)
 / / / / __ \/ / /_/ / 
/ /_/ / / / / / __/ /  
\____/_/ /_/_/_/ /_/   
 
EOF
}

function run_avx_check {
  if grep -q 'avx' /proc/cpuinfo; then
    echo "AVX is supported. Proceeding with LXC setup."
  else
    echo "AVX instructions supported on this CPU. Would you like to explore alternatives?"
    read -p "(y/n): " avx_response
    if [[ "$avx_response" =~ ^[Yy]$ ]]; then
      handle_avx_alternatives
    else
      echo "Exiting setup due to lack of AVX support."
      exit 1
    fi
  fi
}

function handle_avx_alternatives {
  echo "Choose an alternative installation method:"
  echo "1) Install MongoDB 4.2 on LXC container"
  echo "2) Install the latest UniFi version on a Debian 12 VM"
  read -p "Enter your choice (1 or 2): " alt_choice
  if [[ "$alt_choice" == "1" ]]; then
    echo "Proceeding with MongoDB 4.2 installation on LXC..."
    # Set a flag for the installer script
    export MONGO_VERSION="4.2"
  elif [[ "$alt_choice" == "2" ]]; then
    setup_unifi_vm
  else
    echo "Invalid choice. Exiting."
    exit 1
  fi
}

function setup_unifi_vm {
  # Check if unifi-vm.sh exists before downloading
  if [ ! -f "unifi-vm.sh" ]; then
    echo "Downloading unifi-vm.sh..."
    wget -qO unifi-vm.sh "https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/vm/unifi-vm.sh"
  else
    echo "unifi-vm.sh already exists. Skipping download."
  fi
  # Run unifi_vm.sh to start the VM setup
  bash unifi-vm.sh
  exit 0
}

header_info
run_avx_check
echo -e "Loading..."
APP="Unifi"
var_disk="8"
var_cpu="2"
var_ram="2048"
var_os="debian"
var_version="12"
variables
color
catch_errors

function default_settings() {
  CT_TYPE="1"
  PW=""
  CT_ID=$NEXTID
  HN=$NSAPP
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="no"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="no"
  VERB="no"
  echo_default
}

function update_script() {
header_info
check_container_storage
check_container_resources
if [[ ! -d /usr/lib/unifi ]]; then msg_error "No ${APP} Installation Found!"; exit; fi
msg_info "Updating ${APP}"
apt-get update --allow-releaseinfo-change
apt-get install -y unifi
msg_ok "Updated Successfully"
exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${APP}${CL} should be reachable by going to the following URL.
         ${BL}https://${IP}:8443${CL} \n"