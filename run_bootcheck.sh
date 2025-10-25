#!/usr/bin/env bash

#---- version report -----------
Version="0.0.2"
HW_dependency="none"
SW_dependency="none"
TestCaseID="none"
RequirementID=("none")

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


echo "

 _                 _          _               _    
| |__   ___   ___ | |_    ___| |__   ___  ___| | __
| '_ \ / _ \ / _ \| __|  / __| '_ \ / _ \/ __| |/ /
| |_) | (_) | (_) | |_  | (__| | | |  __/ (__|   < 
|_.__/ \___/ \___/ \__|  \___|_| |_|\___|\___|_|\_\

"

# 0.0.2 10/24/2025
# Purpose: Check local hardware and software dependencies
# Expected to run locally only.
# Calls sub-checking scripts (like CPU_GPU_MEM_Disk_Temp_check.sh).
# -----------------------------------------------------------------------------


# =======================
# Text markup for colors
title=$(tput setaf 7; tput bold)
red=$(tput setaf 1)
yellow=$(tput setaf 3)
green=$(tput setaf 2)
text_style_reset=$(tput sgr0)
# =======================

# Define sub-check scripts (local only)
functionlist=(
  ./CPU_GPU_MEM_Disk_Temp_check.sh
)

# Optionally, define scripts that should only run once
functionlist_runonce=(
  # Example: ./NetworkConfig_check.sh
)

# -----------------------------------------------------------------------------
# Main Execution Loop
# -----------------------------------------------------------------------------
while true; do
  issue_found=0  # Track number of failures
  SECONDS=0      # Reset timer

  # Run each local check function/script
  for each_func in "${functionlist[@]}"; do
    if [[ -x "$each_func" ]]; then
      echo -e "$text_style_reset"
      echo -e "$title 🔍 Running $each_func locally...$text_style_reset"
      $each_func
      if [[ $? -ne 0 ]]; then
        echo -e "$red⚠️  Warning: $each_func failed locally.$text_style_reset"
        ((issue_found++))
      fi
    else
      echo -e "$yellow⚠️  Skipping missing or non-executable script: $each_func$text_style_reset"
      ((issue_found++))
    fi
  done

  # Run-once checks (also local)
  for each_func_runonce in "${functionlist_runonce[@]}"; do
    if [[ -x "$each_func_runonce" ]]; then
      echo -e "$title 🔄 Running single-execution check: $each_func_runonce$text_style_reset"
      $each_func_runonce
      if [[ $? -ne 0 ]]; then
        ((issue_found++))
      fi
    fi
  done

  # Timing summary
  total_time=$SECONDS
  mins=$((total_time / 60))
  secs=$((total_time % 60))

  echo -e "$title \n\n=================================="
  echo -e "$green🕒  Total runtime: ${mins} minute(s) and ${secs} second(s).$text_style_reset"

  # Results summary
  if [[ $issue_found -eq 0 ]]; then
    echo -e "$title✅$green  All local checks passed successfully!$text_style_reset"
    break
  else
    echo -e "$red❌  Total failures: $issue_found$text_style_reset"
    echo -n -e "⚠️  Do you want to rerun the checks? (y/n): "
    read -r user_input
    if [[ "$user_input" != "y" && "$user_input" != "Y" ]]; then
      echo "Exiting script."
      exit 1
    fi
  fi
done
