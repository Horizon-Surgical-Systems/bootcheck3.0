#!/bin/bash


# V1 4/15/2025
# This script checks CPU, GPU, RAM (Memory), and physical mounted Disk space.
# It will fail if the available percentage is less than 10%.
# Usage:
# REMOTE_PC=10.10.0.1 ./CPU_GPU_MEM_Disk_check.sh 10.10.0.5 # call remotely
# ./CPU_GPU_MEM_Disk_check.sh # call locally
# V2 4/22/2025 
# add check temp
# V3 5/15/2025 
# change temp check not dependes on thrid party tool
# switch from top to uptime to check CPU load 
# V4 5/22/2025
# add check CPU and GPU name
# V5 6/4/2025 if ssh password incorrect, skip
# V6 6/17/2025 fixed ssh connection issue
# V7 8/26/2025 add check GPU versions
# V8 8/27/2025 add cpu performace check 
# V9 10/24/2025 modified for polaris 3.0
# V10 11/13/2025 update output style
#                add verbose mode and help
#
#

#---- version report -----------
Version="0.0.9"
HW_dependency="none"
SW_dependency="nvidia-smi"

if [[ "$1" == --* && "$1" != "--verbose" && "$1" != "-v" && "$1" != "-h" ]]; then
    report_script="./VersionDependencyReportClass.sh"
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
source ./utils_function.sh

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

check_cpu_model_by_hostname() {

    expected_model=""

    case "${host_name,,}" in
        *"imaging"* | *"visualization"*)
            expected_model="Intel(R) Xeon(R) w5-3425"
            ;;
        *"control"* | *"central"* | *"cockpit"*)
            expected_model="Intel(R) Core(TM) i7-10700 CPU @ 2.90GHz"
            ;;
        *)
            report_check 1 "CPU Model" "Known host pattern" "Unknown hostname: $host_name"
            return 1
            ;;
    esac

    cmd 'cat /proc/cpuinfo | grep "model name" | head -1'
    actual_model=$(echo "$cmd_result" | cut -d ':' -f2 | sed 's/^[ \t]*//')

    if [[ "$actual_model" == "$expected_model" ]]; then
        report_check 0 "CPU Model" "$expected_model" "$actual_model"
    else
        report_check 1 "CPU Model" "$expected_model" "$actual_model"
        return 1
    fi
}


check_cpu() {

    cmd "uptime | awk -F'load average:' '{ print \$2 }' | cut -d',' -f2 | awk '{print \$1}'"
    load_5min=$(printf "%.2f" "$cmd_result")
    cores=$(nproc)
    threshold=$(echo "$cores * 0.90" | bc -l)

    [[ $(echo "$load_5min < $threshold" | bc -l) -eq 1 ]] \
        && report_check 0 "CPU Load (5m)" "< $threshold" "$load_5min" \
        || { report_check 1 "CPU Load (5m)" "< $threshold" "$load_5min"; return 1; }

    cmd "cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort -u"
    governor="$cmd_result"
    expected="performance"

    if [[ "$(echo "$governor" | wc -l)" == "1" && "$governor" == "$expected" ]]; then
        report_check 0 "CPU Governor" "$expected" "$governor"
    else
        report_check 1 "CPU Governor" "$expected" "$governor"
        return 1
    fi
}


check_gpu_model_by_hostname() {

    case "${host_name,,}" in
        *"imaging"*)
            expected_gpu_drive="NVIDIA Corporation Device 26b1"
            expected_gpu_model="NVIDIA RTX 6000 Ada Generation"
            ;;
        *"visualization"*)
            expected_gpu_drive="RTX A4500"
            expected_gpu_model="NVIDIA RTX A4500"
            ;;
        *"control"* | *"central"* | *"cockpit"*)
            expected_gpu_drive="Intel UHD Graphics 630"
            expected_gpu_model="N/A"
            ;;
        *)
            report_check 1 "GPU Host Pattern" "Known pattern" "Unknown hostname"
            return 1
            ;;
    esac

    # Check driver
    cmd "lspci | grep -i 'vga' | tail -1"
    actual_gpu_driver="$cmd_result"

    [[ "$actual_gpu_driver" == *"$expected_gpu_drive"* ]] \
        && report_check 0 "GPU Driver" "$expected_gpu_drive" "$actual_gpu_driver" \
        || report_check 1 "GPU Driver" "$expected_gpu_drive" "$actual_gpu_driver"

    # Check model (nvidia-smi)
    cmd "nvidia-smi --query-gpu=name --format=csv,noheader | tail -1"
    actual_model="$cmd_result"

    if [[ "$actual_model" == *"command not found"* ]]; then
        report_check 1 "GPU Model" "$expected_gpu_model" "nvidia-smi not found"
        return 1
    fi

    [[ "$actual_model" == *"$expected_gpu_model"* ]] \
        && report_check 0 "GPU Model" "$expected_gpu_model" "$actual_model" \
        || report_check 1 "GPU Model" "$expected_gpu_model" "$actual_model"
}


check_gpu() {
    cmd "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits"

    if [[ $cmd_exit_code -ne 0 ]]; then
        report_check 0 "GPU Usage" "Skip" "nvidia-smi not found"
        return 0
    fi

    usage=$(printf "%.2f" "$cmd_result")

    [[ $(echo "$usage < 90" | bc -l) -eq 1 ]] \
        && report_check 0 "GPU Usage %" "< 90%" "$usage%" \
        || report_check 1 "GPU Usage %" "< 90%" "$usage%"
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

        [[ $(echo "$usage < 50" | bc -l) -eq 1 ]] \
            && report_check 0 "Disk Used on $mount_point" "< 50%" "$usage%" \
            || report_check 1 "Disk Used on $mount_point" "< 50%" "$usage%"
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
    cmd "hostname"
    host_name="$cmd_result"

    check_cpu_model_by_hostname
    check_cpu
    check_gpu_model_by_hostname
    check_gpu
    check_memory
    check_physical_disks
    check_temperature
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
