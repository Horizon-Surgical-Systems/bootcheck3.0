#!/usr/bin/env bash
#0.0.1 10/10/2025 init design
# 0.0.2 10/16/2025 add TestCaseID and RequirementID
# 0.0.3 10/17/2025 make the parent script pass down version and other info by system varible

Version="${Version:-0.0.3}"  # fallback to 0.0.0 if not provided
HW_dependency="${HW_dependency:-none}"
SW_dependency="${SW_dependency:-none}"
TestCaseID="${TestCaseID:-none}"
RequirementID=(${RequirementID[@]:-none})  # Can be an array if multiple IDs are needed


function report_version() {
    echo "Version: $Version"
}

function report_hw_dependency() {
    echo "Hardware Dependency: $HW_dependency"
}

function report_sw_dependency() {
    echo "Software Dependency: $SW_dependency"
}

function report_test_case_id() {
    echo "Test Case ID: $TestCaseID"
}

function report_requirement_id() {
    echo -n "Requirement ID: "
    printf "%s" "${RequirementID[0]}"
    for ((i = 1; i < ${#RequirementID[@]}; i++)); do
        printf ", %s" "${RequirementID[$i]}"
    done
    echo
}

if [[ $# -lt 1 ]]; then
    echo "No arguments provided."
    echo "Expected arguments: --version, --hw_dependency, --sw_dependency, --test_case_id, --requirement_id"
    exit 1
fi

case "$1" in
    --version)
        report_version
        ;;
    --hw_dependency)
        report_hw_dependency
        ;;
    --sw_dependency)
        report_sw_dependency
        ;;
    --test_case_id)
        report_test_case_id
        ;;
    --requirement_id)
        report_requirement_id
        ;;
    *)
        echo "Unexpected argument: $1"
        echo "Expected arguments: --version, --hw_dependency, --sw_dependency, --test_case_id, --requirement_id"
        exit 1
        ;;
esac

: <<'END_COMMENT'
put below in to bash files
#---- version report -----------
Version="0.0.1"
HW_dependency="none"
SW_dependency="none"
TestCaseID="none"
RequirementID=("none")
if [[ "$1" == --* ]]; then
    report_script="$AUTOMATEDTESTTOOL/VersionDependencyReportClass.sh"
    if [[ -f "$report_script" ]]; then
        export Version HW_dependency SW_dependency TestCaseID RequirementID
        "$report_script" "$1"
    else
        echo "don't forget to source setup_path.sh from project root"

    fi
    exit 0
fi
#==============================  
END_COMMENT