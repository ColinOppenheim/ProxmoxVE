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

set -eEuo pipefail
BL="\033[36m"
RD="\033[01;31m"
GN="\033[1;92m"
CL="\033[m"
LOG_FILE=".url_conversion_log"

function log_original_format() {
    local file=$1
    echo -e "${BL}Recording original URL format for $file${CL}"
    sed -i "\#^$file:#d" "$LOG_FILE" 2>/dev/null || true
    
    if grep -q "https://github.com.*raw/main" "$file"; then
        echo "$file:github_raw" >> "$LOG_FILE"
    elif grep -q "https://raw.githubusercontent.com" "$file"; then
        echo "$file:githubusercontent" >> "$LOG_FILE"
    else
        echo "$file:standard" >> "$LOG_FILE"
    fi
}

function get_original_format() {
    local file=$1
    if [ -f "$LOG_FILE" ]; then
        format=$(grep "^$file:" "$LOG_FILE" | cut -d: -f2)
        if [ -n "$format" ]; then
            echo "$format"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

header_info
echo "Loading..."

# Prompt for direction
echo -e "\n${BL}Choose direction:${CL}"
echo -e "1) Switch to testing branch"
echo -e "2) Switch back to community repository"
read -r DIRECTION

if [ "$DIRECTION" = "1" ]; then
    OLD_REPO="community-scripts/ProxmoxVE/main"
    echo -e "\n${BL}To find your testing repository path:${CL}"
    echo -e "1. Go to any file in your fork on the branch you want to test"
    echo -e "2. Click the 'Raw' button"
    echo -e "3. From the URL, copy everything after 'githubusercontent.com/' up to (but not including) the first '/' after the branch name"
    echo -e "Example URL: https://raw.githubusercontent.com/UserName/ProxmoxVE/refs/heads/branch/folder/file.sh"
    echo -e "You would copy: ${GN}UserName/ProxmoxVE/refs/heads/branch${CL}"
    echo -e "\n${GN}Enter your testing repository path:${CL}"
    read -r NEW_REPO
elif [ "$DIRECTION" = "2" ]; then
    echo -e "\n${GN}Enter your current testing repository path:${CL}"
    read -r OLD_REPO
    NEW_REPO="community-scripts/ProxmoxVE/main"
else
    echo -e "${RD}Invalid choice. Exiting.${CL}"
    exit 1
fi

# Validate input
if [ -z "$NEW_REPO" ]; then
    echo -e "${RD}[Error] No repository provided. Exiting.${CL}"
    exit 1
fi

# Confirm with user
echo -e "\n${BL}You are about to change repository URLs from ${RD}$OLD_REPO${BL} to ${GN}$NEW_REPO${CL}"
echo -e "Are you sure you want to continue? (y/n)"
read -r CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo -e "${RD}Operation cancelled by user.${CL}"
    exit 1
fi

# Find and update files
header_info
echo -e "${BL}Searching for files containing repository URLs...${CL}\n"
AFFECTED_FILES=$(find . -type f -not -path "*/\.*" -exec grep -l "$OLD_REPO" {} \;)

if [ -z "$AFFECTED_FILES" ]; then
    echo -e "${RD}No files found containing repository URLs.${CL}"
    exit 0
fi

echo -e "${GN}Files to be updated:${CL}"
echo "$AFFECTED_FILES"
echo

# Update files
for file in $AFFECTED_FILES; do
    echo -e "${BL}[Info]${GN} Processing $file${CL}"
    
    if [ "$DIRECTION" = "1" ]; then
        # Log original format before making changes
        log_original_format "$file"
        
        # Convert all formats to raw.githubusercontent.com
        sed -i "s#https://github.com/$OLD_REPO/#https://raw.githubusercontent.com/$NEW_REPO/#g" "$file"
        sed -i "s#https://raw.githubusercontent.com/$OLD_REPO/#https://raw.githubusercontent.com/$NEW_REPO/#g" "$file"
        sed -i "s#$OLD_REPO/#$NEW_REPO/#g" "$file"
    else
        # Converting back to original format
        format=$(get_original_format "$file")
        case $format in
            "github_raw")
                sed -i "s#https://raw.githubusercontent.com/$OLD_REPO/#https://github.com/$NEW_REPO/raw/#g" "$file"
                ;;
            "githubusercontent")
                sed -i "s#https://raw.githubusercontent.com/$OLD_REPO/#https://raw.githubusercontent.com/$NEW_REPO/#g" "$file"
                ;;
            *)
                sed -i "s#$OLD_REPO/#$NEW_REPO/#g" "$file"
                ;;
        esac
    fi
    
    if grep -q "$NEW_REPO" "$file"; then
        echo -e "${GN}[Success]${CL} $file updated${CL}"
    else
        echo -e "${RD}[Error]${CL} $file could not be updated properly${CL}"
    fi
done

header_info
echo -e "${GN}The process is complete. Repository URLs have been switched to $NEW_REPO${CL}"
if [ "$DIRECTION" = "1" ]; then
    echo -e "${BL}Original URL formats have been logged to $LOG_FILE${CL}"
fi
echo -e "${BL}To revert changes, run this script again and choose the opposite direction.${CL}\n"