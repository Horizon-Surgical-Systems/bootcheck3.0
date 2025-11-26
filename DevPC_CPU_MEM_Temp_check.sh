#!/bin/bash

# V1 11/25/2025
# This script checks developer PC/ laptop system
#   CPU, RAM (Memory), and physical mounted Disk space.
#
#
#

# Absolute path to the directory where THIS script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#---- version report -----------
Version="0.0.1"
HW_dependency="none"
SW_dependency="none"

if [[ "$1" == --* && "$1" != "--verbose" && "$1" != "-v" && "$1" != "-h" ]]; then
    report_script="$SCRIPT_DIR/VersionDependencyReportClass.sh"
    if [[ -f "$report_script" ]]; then
        export Version HW_dependency SW_dependency TestCaseID RequirementID
        "$report_script" "$1"
    else
        echo "⚠️  Please source setup_path.sh from the project root before running version report."
    fi
    exit 0
fi


# ================================================================
# HELP
# ================================================================
if [[ "$1" == "-h" ]]; then
cat <<EOF
System Validation Script - Help

Usage:
  ./validate.sh [OPTIONS]

Options:
  -h              Show help
  --verbose, -v   Enable verbose debug output
  --<version>     Trigger version report (existing behavior)

Functions tested:
  - CPU model
  - CPU load + performance governor check
  - GPU driver, GPU model, GPU firmware versions
  - GPU usage
  - Memory usage
  - Disk usage
  - System temperature
EOF
exit 0
fi


# ================================================================
# VERBOSE MODE
# ================================================================
VERBOSE=false
[[ "$1" == "--verbose" || "$1" == "-v" ]] && VERBOSE=true


# ================================================================
# Load utilities
# ================================================================
source $SCRIPT_DIR/utils_function.sh

PASSWORD="$SSH_PASS"
REMOTE_PC=""

cmd_result=""
cmd_exit_code=""

# DO NOT REMOVE:
# # Function to execute a command locally or remotely
# function cmd() {
#   local command="$@"
#   if [[ $REMOTE_PC == "localhost" ]]; then
#     cmd_result=$(bash -c "$command" 2>&1)
#     cmd_exit_code="$?"
#   else
#     ping $REMOTE_PC -c 1 &>/dev/null
#     if [[ $? -ne 0 ]]; then
#       echo "Failed to connect to $REMOTE_PC"
#       cmd_result="fail to ping"
#       cmd_exit_code=1
#       exit 1
#     fi
#     cmd_result=$(sshpass -p horizon ssh -o ConnectTimeout=3 horizon@$REMOTE_PC "$command" 2>&1)
#     cmd_exit_code="$?"
#   fi
# }


# ================================================================
# NEW CMD EXECUTOR (Supports verbose + pipes + remote)
# ================================================================
function cmd() {
    local command="$*"

    if $VERBOSE; then
        echo -e "\n--- DEBUG COMMAND ---"
        echo "$command"
        echo "----------------------"
    fi

    if [[ "$REMOTE_PC" == "localhost" || -z "$REMOTE_PC" ]]; then
        cmd_result=$(bash -c "$command" 2>&1)
        cmd_exit_code=$?
    else
        ping -c 1 "$REMOTE_PC" &>/dev/null
        if [[ $? -ne 0 ]]; then
            cmd_result="fail to ping"
            cmd_exit_code=1
            return
        fi
        cmd_result=$(sshpass -p "$PASSWORD" ssh -o ConnectTimeout=3 horizon@$REMOTE_PC "$command" 2>&1)
        cmd_exit_code=$?
    fi

    if $VERBOSE; then
        echo -e "--- DEBUG OUTPUT ---"
        echo "$cmd_result"
        echo "---------------------"
    fi
}

echo "==============================================================="
echo " CPU GPU MEM Disk Temperature check "
echo "==============================================================="

START_TIME=$(date +%s)

PASS_COUNT=0
FAIL_COUNT=0

function report_check() {
    local status="$1"
    local name="$2"
    local expected="$3"
    local actual="$4"

    if [[ "$status" -eq 0 ]]; then
        printf "[PASS] %-40s Expected: %-25s Actual: %s\n" "$name" "$expected" "$actual"
        ((PASS_COUNT++))
    else
        printf "[FAIL] %-40s Expected: %-25s Actual: %s\n" "$name" "$expected" "$actual"
        ((FAIL_COUNT++))
    fi
}



# ================================================================
# CHECK FUNCTIONS (rewritten to use Style A PASS/FAIL)
# ================================================================




check_cpu() {

    cmd "uptime | awk -F'load average:' '{ print \$2 }' | cut -d',' -f2 | awk '{print \$1}'"
    load_5min=$(printf "%.2f" "$cmd_result")
    cores=$(nproc)
    threshold=$(echo "$cores * 0.90" | bc -l)

    if (( $(echo "$load_5min < $threshold" | bc -l) )); then
        report_check 0 "CPU Load (5m)" "< $threshold" "$load_5min"
    else
        report_check 1 "CPU Load (5m)" "> $threshold" "$load_5min"
        return 1
    fi


}




check_memory() {

    cmd "free -m | awk 'NR==2 {printf \"%.2f\", (\$3/\$2)*100}'"
    mem=$(printf "%.2f" "$cmd_result")

    [[ $(echo "$mem < 90" | bc -l) -eq 1 ]] \
        && report_check 0 "RAM Usage %" "< 90%" "$mem%" \
        || report_check 1 "RAM Usage %" "< 90%" "$mem%"
}


check_physical_disks() {

    cmd "df -Pl | awk 'NR>1 && !/tmpfs|udev|overlay|efivarfs/'"

    while read -r line; do
        mount_point=$(echo "$line" | awk '{print $6}')
        usage=$(echo "$line" | awk '{print $5}' | sed 's/%//')

        [[ $(echo "$usage < 99" | bc -l) -eq 1 ]] \
            && report_check 0 "Disk Used on $mount_point" "< 99%" "$usage%" \
            || report_check 1 "Disk Used on $mount_point" "< 99%" "$usage%"
    done <<< "$cmd_result"
}


check_temperature() {

    cmd 'for zone in /sys/class/thermal/thermal_zone*; do
            type=$(cat "$zone/type")
            temp=$(cat "$zone/temp")
            echo "$type:$((temp / 1000))"
         done'

    while read -r line; do
        type=$(echo "$line" | cut -d: -f1)
        temp=$(echo "$line" | cut -d: -f2)

        [[ "$temp" -lt 75 ]] \
            && report_check 0 "${type} Temp" "< 75°C" "${temp}°C" \
            || report_check 1 "${type} Temp" "< 75°C" "${temp}°C"
    done <<< "$cmd_result"
}


# ================================================================
# MAIN RUNNER
# ================================================================
CPU_GPU_MEM_Disk_check() {
    check_cpu
    check_memory
    check_physical_disks

}



############################################################
# Summary
############################################################

CPU_GPU_MEM_Disk_check
END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))

echo "==============================================================="
echo " Checks completed: $PASS_COUNT passed, $FAIL_COUNT failed."
echo " Total runtime: ${RUNTIME}s"
echo "==============================================================="

exit $FAIL_COUNT

exit 0
