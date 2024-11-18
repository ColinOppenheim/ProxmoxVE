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
LOG_FILE=".url_conversion_log.json"

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
            echo -e "${RD}Unable to install jq. Please install it manually and run this script again.${CL}"
            exit 1
        fi
        echo -e "${GN}jq has been installed successfully.${CL}"
    else
        echo -e "${GN}jq is already installed.${CL}"
    fi
}

function log_original_format() {
    local file=$1
    local temp_json=""
    
    # Create new JSON entry if log file doesn't exist
    if [ ! -f "$LOG_FILE" ]; then
        echo '{"files":{}}' > "$LOG_FILE"
    fi

    # Initialize array for URLs in this file
    urls_array="[]"
    
    # Find and process each URL in the file
    while IFS= read -r line; do
        if [[ $line =~ https://github\.com/.*/raw/main ]]; then
        original_url=$(echo "$line" | grep -o 'https://github\.com/[^[:space:]"'\'']*')
        # First change the domain and remove 'raw/'
        converted_url=$(echo "$original_url" | sed "s#github.com/$OLD_REPO/raw/#raw.githubusercontent.com/$NEW_REPO/#")
        url_entry=$(jq -n \
            --arg orig "$original_url" \
            --arg conv "$converted_url" \
            '{original: $orig, converted: $conv, type: "github_raw"}')
        urls_array=$(echo "$urls_array" | jq ". + [$url_entry]")
        elif [[ $line =~ https://raw\.githubusercontent\.com ]]; then
            original_url=$(echo "$line" | grep -o 'https://raw.githubusercontent.com/[^[:space:]"'\'']*')
            converted_url=$(echo "$original_url" | sed "s#raw.githubusercontent.com/$OLD_REPO/#raw.githubusercontent.com/$NEW_REPO/#")
            url_entry=$(jq -n \
                --arg orig "$original_url" \
                --arg conv "$converted_url" \
                '{original: $orig, converted: $conv, type: "githubusercontent"}')
            urls_array=$(echo "$urls_array" | jq ". + [$url_entry]")
        fi
    done < "$file"

    # Add file entry to JSON log
    jq --arg file "$file" \
       --argjson urls "$urls_array" \
       '.files[$file] = {"urls": $urls}' "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
}

function get_original_format() {
    local file=$1
    if [ -f "$LOG_FILE" ]; then
        # Get URLs array for the file
        urls=$(jq -r --arg file "$file" '.files[$file].urls[]' "$LOG_FILE")
        if [ -n "$urls" ]; then
            while IFS= read -r url_entry; do
                original_url=$(echo "$url_entry" | jq -r '.original')
                converted_url=$(echo "$url_entry" | jq -r '.converted')
                url_type=$(echo "$url_entry" | jq -r '.type')
                
                # Convert back based on type
                case $url_type in
                    "github_raw")
                        sed -i "s#$converted_url#$original_url#g" "$file"
                        ;;
                    "githubusercontent")
                        sed -i "s#$converted_url#$original_url#g" "$file"
                        ;;
                esac
            done <<< "$urls"
            return 0
        fi
    fi
    return 1
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
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${RD}No conversion log found. Are you sure you're in test mode?${CL}"
        exit 1
    fi
    # Get current repo from any file that was converted
    OLD_REPO=$(grep -l "raw.githubusercontent.com" . -r | head -n1 | xargs grep -o "[^/]*/[^/]*/[^/]*/[^/]*" | head -n1)
    NEW_REPO="community-scripts/ProxmoxVE/main"
    echo -e "${BL}Detected current test repository: ${GN}$OLD_REPO${CL}"
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
# Check and install jq if necessary
check_install_jq
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