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



#---- version report -----------
Version="0.0.9"
HW_dependency="none"
SW_dependency="nvidia-smi"


if [[ "$1" == --* ]]; then
    report_script="./VersionDependencyReportClass.sh"
    if [[ -f "$report_script" ]]; then
        export Version HW_dependency SW_dependency TestCaseID RequirementID
        "$report_script" "$1"
    else
        echo "⚠️  Please source setup_path.sh from the project root before running version report."
    fi
    exit 0
fi

# =======================

# Load PC list and password
source ./utils_function.sh

PASSWORD="$SSH_PASS"
REMOTE_PC=""

cmd_result=""
cmd_exit_code=""

# # Function to execute a command locally or remotely
# function cmd() {
#   local command="$@"
#   if [[ $REMOTE_PC == "localhost" ]]; then
#     # If $REMOTE_PC is "localhost", execute the command locally
#     cmd_result=$(bash -c "$command" 2>&1) # Execute the command locally
#     cmd_exit_code="$?"
#   else
#     ping $REMOTE_PC -c 1 &>/dev/null
#     if [[ $? -ne 0 ]]; then
#       echo "Failed to connect to $REMOTE_PC"
#       cmd_result="fail to ping"
#       cmd_exit_code=1
#       exit 1
#     fi
#     # If $REMOTE_PC is set, execute the command remotely with sshpass
#     cmd_result=$(sshpass -p horizon ssh -o ConnectTimeout=3 horizon@$REMOTE_PC "$command" 2>&1) # Execute the command remotely
#     cmd_exit_code="$?"
#   fi
# }

# Text markup for colors
title=$(tput setaf 7; tput bold)
red=$(tput setaf 1)
yellow=$(tput setaf 3)
green=$(tput setaf 2)
text_style_reset=$(tput sgr0)

check_cpu_model_by_hostname() {
    expected_model=""

    echo -e "$title ----- Checking CPU model on $host_name"

    case "${host_name,,}" in
       *"imaging"* | *"visualization"*)
        expected_model="Intel(R) Xeon(R) w5-3425"
      ;;
      *"control"* | *"central"* |  *"cockpit"* )
        expected_model="Intel(R) Core(TM) i7-10700 CPU @ 2.90GHz"
      ;;
      *)
        echo -e "$yellow [WARNING] Unknown hostname pattern for CPU check."
        return 0
      ;;
      esac

    #cmd 'cat /proc/cpuinfo | grep "model name" | head -1'
    cmd 'cat /proc/cpuinfo | grep "model name" | head -1' 
    actual_model=$(echo $cmd_result | cut -d ':' -f2 | sed 's/^[ \t]*//')
    #echo "$actual_model"

    if [[ "$actual_model" == "$expected_model" ]]; then
        echo -e "$green CPU model matches expected: $expected_model - pass"
    else
        echo -e "$red CPU model mismatch. Expected: $expected_model, Got: $actual_model -fail"
        exit 1
    fi
}


check_cpu() {
  echo -e "$text_style_reset"
  echo -e "$title ----- Checking CPU Load (5-min avg) on $host_name"
  fault_flag=0

  # Run uptime and get the 5-minute load average
  cmd "uptime | awk -F'load average:' '{ print \$2 }' | cut -d',' -f2 | awk '{print \$1}'"
  if [[ $cmd_exit_code -ne 0 ]]; then
    echo -e "$red Failed to get CPU load."
    echo -e "$yellow Error: $cmd_result"
    fault_flag=1
  fi

  load_5min=$(echo "$cmd_result" | awk '{printf "%.2f", $1}')
  cores=$(nproc)  # or define manually, e.g. cores=4

  # Threshold: load should be less than total cores
  threshold=$(echo "$cores * 0.90" | bc -l)

  if (( $(echo "$load_5min < $threshold" | bc -l) )); then
    echo -e "$green CPU Load (5-min avg): $load_5min (Threshold: $threshold) - pass"
  
  else
    echo -e "$red CPU Load (5-min avg): $load_5min (Threshold: $threshold) - fail (too high)"
    fault_flag=1
  fi

  echo -e "$text_style_reset"
  echo -e "$title ----- Checking performace setting $host_name"
  cmd "cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort -u"
  line_count=$(echo "$cmd_result" | wc -l)
  if [[ $line_count == "1" ]]; then 
    if [[ $cmd_result == "performance" ]]; then
      echo -e "$green CPU performance setting matches: $cmd_result - pass"
    else
      echo -e "$red CPU performace setting fail to match- fail"
      echo -e " Expected: performance"
      echo -e " Actual: $cmd_result"
      fault_flag=1
    fi
  else
    echo -e "$red CPU performace setting fail to match- fail"
    echo -e " Expected: performance setting for all cores"
    echo -e " Actual: $cmd_result"
    fault_flag=1
  fi
  return $fault_flag

}


check_gpu_model_by_hostname() {
    expected_gpu=""
    cmd 'hostname'
    host_name=$cmd_result
    echo -e "$text_style_reset"
    echo -e "$title  ----- Checking GPU driver on $host_name"
    fault_flag=0

    case "${host_name,,}" in
      *"imaging"*)
        expected_gpu_drive="VGA compatible controller: NVIDIA Corporation Device 26b1 (rev a1)"
        expected_gpu_model='NVIDIA RTX 6000 Ada Generation'
        expected_Driver_version="560.28.03"
        expected_cuda_version="12.6"
        expected_vbios_version="95.02.59.00.09"
        expected_image_version="G133.0510.00.02"
        expected_GSP_version="560.28.03"
      ;;
      *"visualization"*)
        expected_gpu_drive="VGA compatible controller: NVIDIA Corporation GA102GL [RTX A4500] (rev a1)"
        expected_gpu_model='NVIDIA RTX A4500'
        expected_driver_version="560.28.03"
        expected_cuda_version="12.6"
        expected_vbios_version="94.02.88.00.01"
        expected_image_version="G132.0510.00.01"
        expected_GSP_version="560.28.03"
      ;;


      *"control"* | *"central"* | *"cockpit"*)
        expected_gpu_drive="VGA compatible controller: Intel Corporation CometLake-S GT2 [UHD Graphics 630] (rev 05)"
        expected_gpu_model='nvidia-smi: command not found'

      ;;
      *)
        echo -e "$yellow [WARNING] Unknown hostname pattern for GPU check."
        return 0
      ;;
    esac

    cmd "lspci | grep -i 'vga' | tail -1"
    actual_gpu=$(echo "$cmd_result" | sed 's/^[^ ]* //')


    if [[ "$actual_gpu" == *"$expected_gpu_drive"* ]]; then

        echo -e "$green GPU driver matches expected: $expected_gpu_drive - pass"
    else
        echo -e "$red GPU driver mismatch.  - fail
        Expected: $expected_gpu_drive, 
        Got: $actual_gpu"
        fault_flag=1
    fi

    echo -e "$text_style_reset"
    echo -e "$title  ----- Checking GPU model on $host_name"

    cmd "nvidia-smi --query-gpu=name --format=csv |tail -1"
    actual_gpu="$cmd_result"


    if [[ "$actual_gpu" == *"$expected_gpu_model"* ]]; then
        echo -e "$green GPU model matches expected: $expected_gpu_model - pass"
    elif [[ "$actual_gpu" == *"command not found"* ]]; then
        echo -e "$yello nvidia-smi: command not found"
    else
        echo -e "$red GPU model mismatch.  - fail
        Expected: $expected_gpu_model, 
        Got: $actual_gpu"
        fault_flag=1
    fi

    echo -e "$text_style_reset"
    echo -e "$title  ----- Checking GPU version on $host_name"
    cmd "nvidia-smi -q"
    driver_version=$(echo "$cmd_result" | grep -i "Driver Version" | awk -F ':' '{print $2}' | xargs)
    cuda_version=$(echo "$cmd_result" | grep -i "CUDA Version" | awk -F ':' '{print $2}' | xargs)
    vbios_version=$(echo "$cmd_result" | grep -i "VBIOS Version" | awk -F ':' '{print $2}' | xargs)
    image_version=$(echo "$cmd_result" | grep -i "Image Version" | awk -F ':' '{print $2}' | xargs)
    GSP_version=$(echo "$cmd_result" | grep -i "GSP Firmware Version" | awk -F ':' '{print $2}' | xargs)

    if [[ "$driver_version" == *"$expected_driver_version"* ]]; then
        echo -e "$green GPU driver version: $driver_version - pass"
    else
        echo -e "$red GPU driver version mismatch.  - fail
        Expected: $expected_driver_version
        Acual : $driver_version"
        fault_flag=1
    fi

    if [[ "$cuda_version" == *"$expected_cuda_version"* ]]; then
        echo -e "$green GPU driver version: $cuda_version - pass"
    else
        echo -e "$red GPU driver version mismatch.  - fail
        Expected: $expected_cuda_version
        Acual : $cuda_version"
        fault_flag=1
    fi

    if [[ "$vbios_version" == *"$expected_vbios_version"* ]]; then
        echo -e "$green GPU vbios version: $vbios_version - pass"
    else
        echo -e "$red GPU vbios version mismatch.  - fail
        Expected: $expected_vbios_version
        Acual : $vbios_version"
        fault_flag=1
    fi

    if [[ "$image_version" == *"$expected_image_version"* ]]; then
        echo -e "$green GPU image version: $image_version - pass"
    else
        echo -e "$red GPU image version mismatch.  - fail
        Expected: $expected_cuda_version
        Acual : $image_version"
        fault_flag=1
    fi

    if [[ "$GSP_version" == *"$expected_GSP_version"* ]]; then
        echo -e "$green GPU GSP firmware version: $GSP_version - pass"
    else
        echo -e "$red GPU GSP firmware version mismatch.  - fail
        Expected: $expected_GSP_version
        Acual : $GSP_version"
        fault_flag=1
    fi


    return $fault_flag



}


# Function to check GPU usage (NVIDIA only - requires nvidia-smi)
check_gpu() {
  echo -e "$text_style_reset"
  echo -e "$title ----- Checking GPU Usage on $host_name"

  cmd "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits"
  if [[ $cmd_exit_code -ne 0 ]]; then
    echo -e "$yellow nvidia-smi not found or no NVIDIA GPU detected. Skipping GPU check."
    return 0
  fi
  #nvidia-smi --query-gpu=name --format=csv

  gpu_usage=$(echo "$cmd_result" | awk '{printf "%.2f", $1}')

  if (( $(echo "$gpu_usage < 90" | bc -l) )); then
    echo -e "$green GPU Usage: $gpu_usage% - pass"
    return 0
  else
    echo -e "$red GPU Usage: $gpu_usage% - fail (greater than 90%)"
    return 1
  fi
}

# Function to check RAM (Memory) usage
check_memory() {
  echo -e "$text_style_reset"
  echo -e "$title ----- Checking Memory (RAM) Usage on $host_name"

  cmd "free -m | awk 'NR==2 {printf \"%.2f\", (\$3/\$2)*100}'"
  if [[ $cmd_exit_code -ne 0 ]]; then
    echo -e "$red Failed to get Memory (RAM) usage."
    echo -e "$yellow Error: $cmd_result"
    return 1
  fi

  memory_usage=$(echo "$cmd_result")

  if (( $(echo "$memory_usage < 90" | bc -l) )); then
    echo -e "$green Memory (RAM) Usage: $memory_usage% - pass"
    return 0
  else
    echo -e "$red Memory (RAM) Usage: $memory_usage% - fail (greater than 90%)"
    return 1
  fi
}

# Function to check Disk space for physical mounted drives
check_physical_disks() {
  echo -e "$text_style_reset"
  echo -e "$title ----- Checking Physical Disk Space on $host_name"

  #cmd "df -Pl | awk 'NR>1 && !/tmpfs|devtmpfs|udev|overlay|efivarfs/ {print $1 " " $5}'"
  cmd "df -Pl | awk 'NR>1 && !/tmpfs|devtmpfs|udev|overlay|efivarfs/'"
  echo "$cmd_result"
  if [[ $cmd_exit_code -ne 0 ]]; then
    echo -e "$red Failed to get list of mounted physical drives."
    echo -e "$yellow Error: $cmd_result"
    return 1
  fi

  local mount_points=($(echo "$cmd_result" | awk '{print $6}'))
  local overall_disk_status=0

  if [[ -z "$mount_points" ]]; then
    echo -e "$yellow No physical drives found mounted."
    return 0
  else
    echo -e "$green physical drives found mounted."
  fi

  for mount_point in "${mount_points[@]}"; do
    echo -e "$text_style_reset"
    echo -e "$title ----------Checking Disk Space on $host_name:$mount_point"
    cmd "df -P \"$mount_point\" | awk 'NR==2 {printf \"%.2f\", (\$5+0)}'"
    local disk_exit_code="$cmd_exit_code"
    local disk_result=$(echo "$cmd_result" | sed 's/%//g')

    if [[ $disk_exit_code -ne 0 ]]; then
      echo -e "$red Failed to get disk space for $mount_point."
      echo -e "$yellow Error: $cmd_result"
      overall_disk_status=1
    elif (( $(echo "$disk_result < 50" | bc -l) )); then
      echo -e "$green Disk Usage on $mount_point: $disk_result% - pass"
    else
      echo -e "$red Disk Usage on $mount_point: $disk_result% - fail (less than 50% available)"
      overall_disk_status=1
    fi
  done

  return $overall_disk_status
}


# Function to check system temperatures (CPU and GPU)
check_temperature() {
  echo -e "$text_style_reset"
  echo -e "$title ----- Checking Temperature on $host_name"

  local temperature_warning=0


  # Check CPU temperature
  #cmd "sensors | grep -i 'temp' | grep -Eo '[+-]?[0-9]+\.[0-9]+' | sort -nr | head -1"
  
  cmd 'for zone in /sys/class/thermal/thermal_zone*; do
    type=$(cat "$zone/type")
    temp=$(cat "$zone/temp")
    echo "$type: $((temp / 1000))°C"
  done'
  #echo "$cmd_result"

  if [[ $cmd_exit_code -ne 0 ]]; then
    echo -e "${yellow}Could not retrieve CPU temperature.${reset}"
  else
    temperature_warning=0
    while IFS= read -r line; do
      # Extract temp in °C using more precise pattern
      temp_value=$(echo "$line" | awk -F': ' '{print $2}' | tr -d '°C')

      if (( temp_value >= 75 )); then
        echo -e "${red} ${line} - FAIL (too hot!)${reset}"
        temperature_warning=1
      else
        echo -e "${green} ${line} - OK${reset}"
      fi
    done <<< "$cmd_result"

    if [[ $temperature_warning -eq 1 ]]; then
      echo -e "${red} One or more temperature readings are too high!${reset}"
    else
      echo -e "${green} All temperature readings are within safe limits.${reset}"
    fi
  fi

  # Check GPU temperature if NVIDIA GPU is present
  cmd "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits"
  if [[ $cmd_exit_code -eq 0 ]]; then
    gpu_temp=$(echo "$cmd_result" | awk '{printf "%.2f", $1}')
    if (( $(echo "$gpu_temp < 85" | bc -l) )); then
      echo -e "$green GPU Temperature: $gpu_temp°C - pass"
    else
      echo -e "$red GPU Temperature: $gpu_temp°C - fail (too hot!)"
      temperature_warning=1
    fi
  fi

  return $temperature_warning
}

# Main function to perform all checks
CPU_GPU_MEM_Disk_check() {
  local overall_status=0

  cmd 'hostname'
  if [[ "$cmd_result" == "ping failed" ]]; then
    return 0
  fi
  if [[ "$cmd_result" == *"ssh password incorrect"* ]]; then
    echo -e "$yellow SSH password incorrect. Skipping $REMOTE_PC.$text_style_reset"
    return 0
  fi
  host_name=$cmd_result

  check_cpu_model_by_hostname || overall_status=1
  check_cpu || overall_status=1
  check_gpu_model_by_hostname || overall_status=1
  check_gpu
  check_memory || overall_status=1
  check_physical_disks || overall_status=1
  check_temperature || overall_status=1

  echo -e "$text_style_reset"
  if [[ $overall_status -eq 0 ]]; then
    echo -e "$green ----- System checks passed on $host_name -----"
  else
    echo -e "$red ----- System checks failed on $host_name -----"
  fi
  return $overall_status

}

if [[ -n "$REMOTE_PC" ]]; then
  echo -e "$title Running remote system check on $REMOTE_PC...$text_style_reset"
else
  echo -e "$title Running local system check...$text_style_reset"
fi

CPU_GPU_MEM_Disk_check
exit $?