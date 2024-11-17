#!/usr/bin/env bash

# Author: ColinOppenheim
# License: MIT
# /mnt/samba_share/GitRepos/ProxmoxVE/raw/main/LICENSE

function header_info {
  clear
  cat <<"EOF"
   __  __      _ _____    ____           ____       __    _                ______ 
  / / / /___  (_) __(_)  / __ \____     / __ \___  / /_  (_)___ _____     <  /__ \
 / / / / __ \/ / /_/ /  / / / / __ \   / / / / _ \/ __ \/ / __ `/ __ \    / /__/ /
/ /_/ / / / / / __/ /  / /_/ / / / /  / /_/ /  __/ /_/ / / /_/ / / / /   / // __/ 
\____/_/ /_/_/_/ /_/   \____/_/ /_/  /_____/\___/_.___/_/\__,_/_/ /_/   /_//____/ 
                                                                                  
EOF
}

header_info
echo -e "\nLoading..."

GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
NEXTID=$(pvesh get /cluster/nextid)

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
GN=$(echo "\033[1;92m")
RD=$(echo "\033[01;31m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT

function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
  cleanup_vmid
}

function cleanup_vmid() {
  if qm status "$VMID" &>/dev/null; then
    qm stop "$VMID" &>/dev/null
    qm destroy "$VMID" &>/dev/null
  fi
}

function cleanup() {
  popd >/dev/null
  rm -rf "$TEMP_DIR"
}

TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "UniFi Debian 12 VM" --yesno "This will create a New Debian 12 VM and install UniFi Controller. Proceed?" 10 58; then
  :
else
  header_info && echo -e "⚠ User exited script \n" && exit
fi

function msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

function check_root() {
  if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
    clear
    msg_error "Please run this script as root."
    echo -e "\nExiting..."
    sleep 2
    exit
  fi
}

function pve_check() {
  if ! pveversion | grep -Eq "pve-manager/(7|8)\."; then
    msg_error "This version of Proxmox Virtual Environment is not supported"
    echo -e "Requires Proxmox Virtual Environment Version 7.x or 8.x."
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    msg_error "This script will not work with PiMox!"
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function default_settings() {
  VMID="$NEXTID"
  FORMAT=",efitype=4m"
  HN="Unifi"
  CORE_COUNT="2"
  RAM_SIZE="2048"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  START_VM="yes"
  echo -e "${GN}Using Virtual Machine ID: ${BL}${VMID}${CL}"
  echo -e "${GN}Allocated Cores: ${BL}${CORE_COUNT}${CL}"
  echo -e "${GN}Allocated RAM: ${BL}${RAM_SIZE}${CL}"
  echo -e "${GN}Using Bridge: ${BL}${BRG}${CL}"
  echo -e "${GN}Using MAC Address: ${BL}${MAC}${CL}"
  echo -e "${GN}Start VM when completed: ${BL}yes${CL}"
}

check_root
arch_check
pve_check
default_settings

# Start VM Creation Process
msg_info "Validating Storage"
while read -r line; do
  TAG=$(echo $line | awk '{print $1}')
  TYPE=$(echo $line | awk '{printf "%-10s", $2}')
  FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')
VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
  msg_error "Unable to detect a valid storage location."
  exit
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use for ${HN}?\nTo make a selection, use the Spacebar.\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3) || exit
  done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."
msg_info "Retrieving the URL for the Debian 12 Qcow2 Disk Image"
URL=https://cloud.debian.org/images/cloud/bookworm/20240507-1740/debian-12-nocloud-amd64-20240507-1740.qcow2
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
wget -q --show-progress $URL
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

# VM Disk Configuration
STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
  nfs | dir)
    DISK_EXT=".qcow2"
    DISK_REF="$VMID/"
    DISK_IMPORT="-format qcow2"
    ;;
  btrfs)
    DISK_EXT=".raw"
    DISK_REF="$VMID/"
    DISK_IMPORT="-format raw"
    FORMAT=",efitype=4m"
    ;;
esac
for i in {0,1}; do
  disk="DISK$i"
  eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
  eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done

# Cleanup Logic: Ensure no existing VM or disk conflicts
msg_info "Performing cleanup of any existing resources"
if qm status "$VMID" &>/dev/null; then
  echo "VMID $VMID already exists. Removing it..."
  qm stop "$VMID" &>/dev/null || true
  qm destroy "$VMID" &>/dev/null || true
  msg_ok "Removed existing VMID $VMID"
fi

if lvdisplay "/dev/pve/vm-${VMID}-disk-0" &>/dev/null; then
  echo "Disk vm-${VMID}-disk-0 already exists. Removing it..."
  lvremove -y "/dev/pve/vm-${VMID}-disk-0" &>/dev/null || true
  msg_ok "Removed existing disk vm-${VMID}-disk-0"
fi

msg_ok "Cleanup completed successfully"

# Debugging for Variables
#echo "Debug: STORAGE = $STORAGE"
#echo "Debug: DISK0 = $DISK0"
#echo "Debug: VMID = $VMID"

msg_info "Creating a Debian 12 VM"
qm create "$VMID" -agent 1 -tablet 0 -localtime 1 -bios ovmf -cores "$CORE_COUNT" -memory "$RAM_SIZE" \
  -name "$HN" -tags proxmox-helper-scripts -net0 virtio,bridge="$BRG",macaddr="$MAC" -onboot 1 -ostype l26 -scsihw virtio-scsi-pci

# Import disk
msg_info "Importing Disk for VM $VMID"
if [[ "$STORAGE_TYPE" == "lvmthin" ]]; then
  qm importdisk "$VMID" "$TEMP_DIR/$FILE" "$STORAGE"
else
  qm importdisk "$VMID" "$TEMP_DIR/$FILE" "$STORAGE" "$DISK_IMPORT"
fi

# Allocate secondary disk
msg_info "Allocating secondary disk for VM $VMID"
pvesm alloc "$STORAGE" "$VMID" "$DISK1" 8G
if [[ $? -ne 0 ]]; then
  msg_error "Failed to allocate secondary disk for VM $VMID"
  exit 1
fi

# Debugging for Variables
echo "Debug: DISK0_REF = $DISK0_REF"
echo "Debug: DISK1_REF = $DISK1_REF"
echo "Debug: FORMAT = $FORMAT"

# Set VM configuration
msg_info "Setting up VM $VMID"
DESCRIPTION="UniFi Debian 12 VM: Visit Helper-Scripts.com for details or support us on Ko-Fi at https://ko-fi.com/D1D7EP4GF"


qm set "$VMID" \
  -efidisk0 "${DISK0_REF}${FORMAT}" \
  -scsi0 "${DISK1_REF},size=8G" \
  -boot order=scsi0 \
  -serial0 socket \
  -description "$DESCRIPTION" >/dev/null
if [[ $? -ne 0 ]]; then
  msg_error "Failed to configure VM $VMID"
  exit 1
fi

# UniFi Debian 12 VM
if [[ $? -ne 0 ]]; then
  msg_error "Failed to configure VM $VMID"
  exit 1
fi

msg_ok "Created and configured Debian 12 VM ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Debian 12 VM"
  qm start "$VMID"
  msg_ok "Started Debian 12 VM"
fi

echo "Debian 12 VM created with ID $VMID. Proceeding with UniFi setup..."

# Wait for VM to be ready
sleep 10

# Installing Dependencies (JRE, MongoDB, and UniFi) on Debian 12 VM

# Install Java 17
echo "Installing Java 17 on VM $VMID..."
qm exec "$VMID" -- "apt update && apt install -y openjdk-17-jre-headless"

# Install MongoDB (Version compatible with UniFi)
echo "Installing MongoDB on VM $VMID..."
qm exec "$VMID" -- "apt install -y gnupg"
qm exec "$VMID" -- "wget -qO - https://www.mongodb.org/static/pgp/server-4.4.asc | apt-key add -"
qm exec "$VMID" -- "echo 'deb [ arch=amd64 ] https://repo.mongodb.org/apt/debian buster/mongodb-org/4.4 main' | tee /etc/apt/sources.list.d/mongodb-org-4.4.list"
qm exec "$VMID" -- "apt update && apt install -y mongodb-org"

# Install UniFi Controller
echo "Installing UniFi Controller on VM $VMID..."
# Adding UniFi APT repository to always get the latest stable version
qm exec "$VMID" -- "echo 'deb https://www.ui.com/download/unifi/debian stable ubiquiti' | tee /etc/apt/sources.list.d/ubnt-unifi.list"
qm exec "$VMID" -- "apt-key adv --keyserver keyserver.ubuntu.com --recv C0A52C50"
qm exec "$VMID" -- "apt update && apt install -y unifi"

echo "UniFi Controller setup complete on Debian 12 VM ID $VMID."
