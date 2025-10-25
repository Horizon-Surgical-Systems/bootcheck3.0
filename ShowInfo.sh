#!/bin/bash
# this script search for all executable files under AutomatedTestFramwork
# the use file name --version, --sw_dependency, --hw_dependency to collect their outputs.

# 0.0.1 10/13/2025
# 0.0.2 10/16/2025 update to show TestCaseID and RequirementID
# 0.0.3 10/22/2025 add Exclude specific files or directories
#                   add Handle Binary Executables like TestArenaCamera


# Optional: color definitions for pretty output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

Version=0.0.3
HW_dependency="none"
SW_dependency="none"
TestCaseID="none"
RequirementID=["none"]

# Get absolute path to this script
self_path=$(realpath "$0")
self_name=$(basename "$0")
#echo "$self_name Version: $Version" 
printf "${GREEN}%-20s${NC} %s\n" "$self_name" " Version: $Version" 



# current location
scan_dir="$(pwd)"

# Resolve the real path (eliminates symlinks)
#scan_dir=$(realpath "$scan_dir")
#echo "scan_dir $scan_dir"

# Ensure the directory exists
if [[ ! -d "$scan_dir" ]]; then
    echo "Error: '$scan_dir' does not exist."
    exit 1
fi

#echo "Scanning for executable scripts in: $scan_dir"

# Use find with -P to avoid following symlinks
# Exclude specific files or directories with -path and -prune
find -P "$scan_dir" \
    -path "$scan_dir/DepenedencyInstallers" -prune -o \
    -path "$scan_dir/DepenedencyInstallers/squish-9.1.0-qt69x-linux64.run" -prune -o \
    -path "$scan_dir/DepenedencyInstallers/playwright" -prune -o \
    -path "$scan_dir/TestEnviromentScript/CloudDashboard/playwright" -prune -o \
    -path "$scan_dir/TestEnviromentScript/CloudDashboard/node_modules" -prune -o \
    -path "$scan_dir/.git" -prune -o \
    -type f -executable -print | while read -r script; do
    #-path "$scan_dir/TestToolsNHelpScripts/TestArenaCamera" -prune -o \
    script_path=$(realpath -P "$script")
    # Skip this script itself
    if [[ "$script_path" == "$self_path" ]]; then
        continue
    fi

    # Skip if the script is in the excluded directory
    if [[ "$script_path" == "$scan_dir/DepenedencyInstallers"* ]]; then
        continue
    fi

    # Print full path to the script
    filename="$(basename $script_path)"
    printf "${YELLOW}%-40s${NC}\n" "$script_path"

    # Try to get version with --version, capture both stdout and stderr
    output=$("$script_path" --version 2>&1)
    if [[ $? -ne 0 || -z "$output" ]]; then
        echo -e "${RED}$script_path: No version info or not supported.${NC}"
    else
        printf "${GREEN}%-20s${NC} %s\n" "$filename" "$output"
    fi

    # Try --sw_dependency
    output=$("$script_path" --sw_dependency 2>&1)
    if [[ $? -ne 0 || -z "$output" ]]; then
        echo -e "${RED}$script_path: No sw_dependency info or not supported.${NC}"
    else
        printf "${GREEN}%-20s${NC} %s\n" "$filename" "$output"
    fi

    # Try --hw_dependency
    output=$("$script_path" --hw_dependency 2>&1)
    if [[ $? -ne 0 || -z "$output" ]]; then
        echo -e "${RED}$script_path: No hw_dependency info or not supported.${NC}"
    else
        printf "${GREEN}%-20s${NC} %s\n" "$filename" "$output"
    fi

    # Try --test_case_id
    output=$("$script_path" --test_case_id 2>&1)
    if [[ $? -ne 0 || -z "$output" ]]; then
        echo -e "${RED}$script_path: No test_case_id info or not supported.${NC}"
    else
        printf "${GREEN}%-20s${NC} %s\n" "$filename" "$output"
    fi

    # Try --requirement_id
    output=$("$script_path" --requirement_id 2>&1)
    if [[ $? -ne 0 || -z "$output" ]]; then
        echo -e "${RED}$script_path: No requirement_id info or not supported.${NC}"
    else
        printf "${GREEN}%-20s${NC} %s\n" "$filename" "$output"

    fi
    
done
