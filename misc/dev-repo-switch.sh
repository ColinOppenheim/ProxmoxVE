#!/usr/bin/env bash

function header_info {
  clear
  cat <<"EOF"
   _____         _ __       __       ___      ____           
  / ___/      __(_) /______/ /_     |__ \    / __ \___ _   __
  \__ \ | /| / / / __/ ___/ __ \    __/ /   / / / / _ \ | / /
 ___/ / |/ |/ / / /_/ /__/ / / /   / __/   / /_/ /  __/ |/ / 
/____/|__/|__/_/\__/\___/_/ /_/   /____/  /_____/\___/|___/  


EOF
}

# Variables
set -eEuo pipefail
BL="\033[36m"
RD="\033[01;31m"
GN="\033[1;92m"
CL="\033[m"
LOG_FILE=".url_conversion_log.json"

# Check jq installation
function check_install_jq() {
    if ! command -v jq &> /dev/null; then
        echo -e "${BL}jq is not installed. Installing it now...${CL}"
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y jq
        elif command -v yum &> /dev/null; then
            yum install -y jq
        elif command -v dnf &> /dev/null; then
            dnf install -y jq
        else
            echo -e "${RD}Unable to install jq. Please install it manually.${CL}"
            exit 1
        fi
    fi
}

# Log initialization
function initialize_log {
  if [ ! -f "$LOG_FILE" ]; then
    echo '{"files":{}}' > "$LOG_FILE"
  fi
}

# Logging changes
function log_changes {
  local file="$1"
  local original_url="$2"
  local converted_url="$3"

  initialize_log
  local current_log
  current_log=$(jq '.' "$LOG_FILE")

  updated_log=$(echo "$current_log" | jq \
    --arg file "$file" \
    --arg orig "$original_url" \
    --arg conv "$converted_url" \
    '.files[$file].urls += [{"original": $orig, "converted": $conv}]')

  echo "$updated_log" > "$LOG_FILE"
}

# Transform URLs
function process_files {
  local old_repo="community-scripts/ProxmoxVE"
  local new_repo="$USERNAME/$REPO/refs/heads/$BRANCH"

  echo -e "${BL}Searching for files to process...${CL}"
  find . -type f -name "*.sh" | while read -r file; do
    echo -e "${BL}[Info] Processing file: $file${CL}"
    while IFS= read -r line; do
      if [[ $line =~ https://github\.com/$old_repo/raw/main ]]; then
        # Transform github.com URLs with /raw/
        original_url=$(echo "$line" | grep -o 'https://github\.com/[^[:space:]"'\'']*')
        converted_url=$(echo "$original_url" | sed "s#github.com/$old_repo/raw/#raw.githubusercontent.com/$new_repo/#")
        # Escape special characters for sed
        escaped_original=$(echo "$original_url" | sed 's/[&/\]/\\&/g; s/"/\\\"/g')
        escaped_converted=$(echo "$converted_url" | sed 's/[&/\]/\\&/g; s/"/\\\"/g')
        sed -i "s#$escaped_original#$escaped_converted#g" "$file"
        log_changes "$file" "$original_url" "$converted_url"
      elif [[ $line =~ https://raw\.githubusercontent\.com/$old_repo/main ]]; then
        # Transform raw.githubusercontent.com URLs
        original_url=$(echo "$line" | grep -o 'https://raw.githubusercontent.com/[^[:space:]"'\'']*')
        converted_url=$(echo "$original_url" | sed "s#raw.githubusercontent.com/$old_repo/#raw.githubusercontent.com/$new_repo/#")
        # Escape special characters for sed
        escaped_original=$(echo "$original_url" | sed 's/[&/\]/\\&/g; s/"/\\\"/g')
        escaped_converted=$(echo "$converted_url" | sed 's/[&/\]/\\&/g; s/"/\\\"/g')
        sed -i "s#$escaped_original#$escaped_converted#g" "$file"
        log_changes "$file" "$original_url" "$converted_url"
      elif [[ $line =~ https://github\.com/$old_repo/blob/main ]]; then
        # Transform github.com URLs without /raw/
        original_url=$(echo "$line" | grep -o 'https://github\.com/[^[:space:]"'\'']*')
        converted_url=$(echo "$original_url" | sed "s#github.com/$old_repo/blob/main#github.com/$new_repo/blob/$BRANCH#")
        # Escape special characters for sed
        escaped_original=$(echo "$original_url" | sed 's/[&/\]/\\&/g; s/"/\\\"/g')
        escaped_converted=$(echo "$converted_url" | sed 's/[&/\]/\\&/g; s/"/\\\"/g')
        sed -i "s#$escaped_original#$escaped_converted#g" "$file"
        log_changes "$file" "$original_url" "$converted_url"
      fi
    done < "$file"
    echo -e "${GN}[Success] Processed: $file${CL}"
  done
}

# Revert changes
function revert_changes {
  if [ ! -f "$LOG_FILE" ]; then
    echo -e "${RD}No log file found. Cannot revert changes.${CL}"
    exit 1
  fi

  jq -r '.files | to_entries[] | "\(.key) \(.value.urls[] | .original) \(.value.urls[] | .converted)"' "$LOG_FILE" | while read -r file original_url converted_url; do
    if [ -f "$file" ]; then
      sed -i "s#$converted_url#$original_url#g" "$file"
    fi
  done
  echo -e "${GN}Reverted all changes based on the log file.${CL}"
}

# Main Script
header_info
check_install_jq

# Get user input
read -rp "Enter your GitHub username (e.g., ColinOppenheim): " USERNAME
read -rp "Enter your GitHub repository name (e.g., ProxmoxVE): " REPO
read -rp "Enter the branch name (e.g., Unifi-VM): " BRANCH

# Validate inputs
if [[ -z "$USERNAME" || -z "$REPO" || -z "$BRANCH" ]]; then
  echo -e "${RD}Error: All inputs are required.${CL}"
  exit 1
fi

# Main Menu
echo -e "\n${BL}What would you like to do?${CL}"
echo "1) Transform URLs to the testing repository"
echo "2) Revert URLs to the original repository"
read -rp "Enter your choice (1 or 2): " choice

case $choice in
  1)
    echo -e "${BL}Transforming URLs to the testing repository...${CL}"
    process_files
    echo -e "${GN}Transformation complete. Changes logged to $LOG_FILE.${CL}"
    ;;
  2)
    echo -e "${BL}Reverting URLs to the original repository...${CL}"
    revert_changes
    ;;
  *)
    echo -e "${RD}Invalid choice. Exiting.${CL}"
    exit 1
    ;;
esac
