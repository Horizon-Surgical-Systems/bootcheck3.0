#!/bin/bash
# imaging_module_setting_check
# This script verifies OS and network settings for the imaging module environment.
# note currently test set to P2 2.6 setup for 3.0 uncomment some of the checks

############################################################
# Version Argument Handling
############################################################
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


VERBOSE=false
if [[ "$1" == "--verbose" || "$1" == "-v" ]]; then
    VERBOSE=true
fi

function debug_msg() {
    if $VERBOSE; then
        echo -e "\n--- DEBUG: $1 ---"
    fi
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "--verbose; -v"
fi



# Function to run a command and capture output
run_cmd() {
    local CMD="$1"
    if $VERBOSE; then
        echo -e "\n--- DEBUG: Running: $CMD ---"
    fi

    # Execute the command in a shell so pipes work
    local OUTPUT
    OUTPUT=$(bash -c "$CMD" 2>&1)

    if $VERBOSE; then
        echo -e "--- DEBUG Output ---\n$OUTPUT\n"
    fi

    echo "$OUTPUT"
}

echo "==============================================================="
echo " Imaging Module Environment Validation 2.7 "
echo "==============================================================="

START_TIME=$(date +%s)

PASS_COUNT=0
FAIL_COUNT=0

# Helper function to print check result in a consistent format
function check_result() {
    local STATUS=$1
    local DESC=$2
    local EXPECTED=$3
    local ACTUAL=$4

    if [ "$STATUS" -eq 0 ]; then
        printf "[OK]   %-45s Expected: %-20s Actual: %s\n" "$DESC" "$EXPECTED" "$ACTUAL"
        ((PASS_COUNT++))
    else
        printf "[FAIL] %-45s Expected: %-20s Actual: %s\n" "$DESC" "$EXPECTED" "$ACTUAL"
        ((FAIL_COUNT++))
    fi
}

############################################################
# 1. Check network interfaces for specific IPs
############################################################
declare -A IP_LABELS=(
    ["192.168.3.2"]="tele"
#    ["192.168.2.2"]="front/back"
#    ["192.168.1.2"]="front/back"
)

for IP in "${!IP_LABELS[@]}"; do
    OUTPUT=$(run_cmd "ip -4 addr show | awk -v ip=\"$IP\" '\$0 ~ ip {print \$NF}'")
    IFACE="$OUTPUT"

    if [ -n "$IFACE" ]; then
        check_result 0 "Interface for ${IP_LABELS[$IP]} ($IP)" "Exists" "$IFACE"
    else
        check_result 1 "Interface for ${IP_LABELS[$IP]} ($IP)" "Exists" "Missing"
    fi
done

############################################################
# 2. Check MTU values = 9000
############################################################
for IP in "${!IP_LABELS[@]}"; do
    IFACE=$(ip -4 addr show | awk -v ip="$IP" '$0 ~ ip {print $NF}')
    if [ -n "$IFACE" ]; then
        MTU=$(run_cmd "ip link show \"$IFACE\" | awk '/mtu/ {print \$5}'")
        if [ "$MTU" -eq 9000 ] 2>/dev/null; then
            check_result 0 "MTU for $IFACE ($IP)" "9000" "$MTU"
        else
            check_result 1 "MTU for $IFACE ($IP)" "9000" "$MTU"
        fi
    else
        check_result 1 "MTU for IP $IP" "9000" "Interface not found"
    fi
done

############################################################
# 3. Ping remote devices
############################################################
#REMOTE_IPS=("192.168.3.100" "192.168.2.100" "192.168.1.100")
REMOTE_IPS=("192.168.3.100")

for IP in "${REMOTE_IPS[@]}"; do
    PING_OUT=$(run_cmd "ping -c 2 -W 2 \"$IP\"")
    if echo "$PING_OUT" | grep -q "0 received"; then
        check_result 1 "Ping remote device $IP" "Reachable" "Unreachable"
    else
        check_result 0 "Ping remote device $IP" "Reachable" "Reachable"
    fi
done

############################################################
# 4. Check sysctl buffer values
############################################################
declare -A SYSCTL_EXPECT=(
    ["net.core.rmem_default"]="655360000"
    ["net.core.wmem_default"]="655360000"
    ["net.core.rmem_max"]="500000000"
    ["net.core.wmem_max"]="500000000"
)

SYSCTL_OUTPUT=$(run_cmd "echo horizon | sudo -S sysctl -p")

for KEY in "${!SYSCTL_EXPECT[@]}"; do
    EXPECT="${SYSCTL_EXPECT[$KEY]}"
    FOUND=$(echo "$SYSCTL_OUTPUT" | grep "$KEY" | awk -F= '{print $2}' | tr -d ' ')
    if [ "$FOUND" == "$EXPECT" ]; then
        check_result 0 "$KEY" "$EXPECT" "$FOUND"
    else
        check_result 1 "$KEY" "$EXPECT" "${FOUND:-Not found}"
    fi
done

############################################################
# 5. horizon-loopback-mtu.service status
############################################################
SERVICE_STATUS=$(run_cmd "systemctl is-active horizon-loopback-mtu.service")
if [[ "$SERVICE_STATUS" == "active" ]]; then
    check_result 0 "Service horizon-loopback-mtu.service" "active (running)" "$SERVICE_STATUS"
else
    check_result 1 "Service horizon-loopback-mtu.service" "active (running)" "$SERVICE_STATUS"
    fi

############################################################
# 6. Check PTPD service existence
############################################################
#for SVC in ptpd-service-0 ptpd-service-1; do
for SVC in ptpd-service-0; do
    EXISTS=$(run_cmd "systemctl list-unit-files | grep -q \"$SVC\" && echo yes || echo no")
    if [[ "$EXISTS" == "yes" ]]; then
        check_result 0 "Service $SVC" "Exists" "Exists"
    else
        check_result 1 "Service $SVC" "Exists" "Missing"
    fi
done

############################################################
# 7. udev rule exists
############################################################
RULE_PATH="/etc/udev/rules.d/99-arduino.rules"

if [ -f "$RULE_PATH" ]; then
    check_result 0 "udev rule $RULE_PATH" "Exists" "Exists"
else
    check_result 1 "udev rule $RULE_PATH" "Exists" "Missing"
fi

############################################################
# 8. Check if 10.10.0.x interface exists
############################################################
IFACE_1010=$(run_cmd "ip -4 addr show | grep -o \"10\.10\.0\.[0-9]*\" | head -n1")

if [ -n "$IFACE_1010" ]; then
    check_result 0 "Interface 10.10.0.x" "Exists" "$IFACE_1010"
else
    check_result 1 "Interface 10.10.0.x" "Exists" "Not found"
fi

############################################################
# 9. Check Alazar PCIe device presence
############################################################
ALAZAR_INFO=$(run_cmd "lspci -vv | grep -A10 \"9373\"")

if [ -z "$ALAZAR_INFO" ]; then
    check_result 1 "Alazar (9373) PCIe card" "Detected" "Not detected"
else
    check_result 0 "Alazar (9373) PCIe card" "Detected" "Detected"
fi

############################################################
# 10. AlazarSysInfo validation
############################################################
ALAZAR_SYSINFO_CMD="/usr/local/AlazarTech/ats9373-7.12.0/AlazarSysInfo"

if [ -x "$ALAZAR_SYSINFO_CMD" ]; then
    SYSINFO_OUTPUT=$(run_cmd "$ALAZAR_SYSINFO_CMD")
    if [ -z "$SYSINFO_OUTPUT" ]; then
        check_result 1 "AlazarSysInfo output" "Valid system info" "No output"
    else
        declare -A SYSINFO_EXPECTS=(
            ["ATSApi Version:"]="7.12.0"
            ["System"]="System 1 : Board 1"
            ["Board Type:"]="ATS9373"
            ["PCB"]="1.5"
            ["CPLD"]="10.7"
            ["FPGA Version:"]="35.3"
            ["PCI"]="Gen2 8X 5.000GT/s 4.000GB/s"
            ["Driver"]="7.12.0"
        )

        for KEY in "${!SYSINFO_EXPECTS[@]}"; do
            EXPECT="${SYSINFO_EXPECTS[$KEY]}"
            ACTUAL=$(echo "$SYSINFO_OUTPUT" | grep "$KEY")
            if [[ "$ACTUAL" == *"$EXPECT"* ]]; then
                check_result 0 "AlazarSysInfo: $KEY" "$EXPECT" "$ACTUAL"
            else
                check_result 1 "AlazarSysInfo: $KEY" "$EXPECT" "${ACTUAL:-Not found}"
            fi
        done
    fi
else
    check_result 1 "AlazarSysInfo executable" "Exists & executable" "Not found"
fi

############################################################
# Summary
############################################################
END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))

echo "==============================================================="
echo " Checks completed: $PASS_COUNT passed, $FAIL_COUNT failed."
echo " Total runtime: ${RUNTIME}s"
echo "==============================================================="

exit $FAIL_COUNT



#=========================================================================
: <<'END_COMMENT'
"imaging_module_setting_check" This check for below OS setting is in place
Pass fail for conclusion 
Show expected result and actual result
show total run time 


check network interface with IP exisi, ip a |grep 
check mtu value for theis three interface to be 9000mtu
	192.168.3.2 #tele
	192.168.2.2 #front/back
	192.168.1.2 #front/back

ping check remote device
	192.168.3.100
	192.168.2.100
	192.168.1.100

check if sysctl -p prints out correct buffer values for
	net.core.rmem_default = 655360000
	net.core.wmem_default = 655360000
	net.core.rmem_max = 500000000
	net.core.wmem_max = 500000000

check `horizon-loopback-mtu.service` status is running

check if ptpd service exists
	ptpd-service-0 
	ptpd-service-1)


check udev rule exisit
	/etc/udev/rules.d/99-arduino.rules

check 10.10.0.x interace exist

Check if Alazar (9373) card is installed on PCIE - there is no way to check installed slot position

run AlazarSysInfo check for version and PCI speed

implement verbose flag that show debug message of what command was used and return of the commands.

implement -h for help

do not remove commented codes

END_COMMENT
