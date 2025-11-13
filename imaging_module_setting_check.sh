#!/bin/bash
# imaging_module_setting_check
# This script verifies OS and network settings for the imaging module environment.

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
#!/bin/bash
# imaging_module_setting_check
# This script verifies OS, network, and hardware settings for the imaging module.

echo "==============================================================="
echo " Imaging Module Environment Validation"
echo "==============================================================="

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

# ------------------------------------------------------------
# 1. Check network interfaces exist for specific IPs
# ------------------------------------------------------------
declare -A IP_LABELS=(
    ["192.168.3.2"]="tele"
    ["192.168.2.2"]="front/back"
    ["192.168.1.2"]="front/back"
)

for IP in "${!IP_LABELS[@]}"; do
    IFACE=$(ip -4 addr show | awk -v ip="$IP" '$0 ~ ip {print $NF}')
    if [ -n "$IFACE" ]; then
        check_result 0 "Interface for ${IP_LABELS[$IP]} ($IP)" "Exists" "$IFACE"
    else
        check_result 1 "Interface for ${IP_LABELS[$IP]} ($IP)" "Exists" "Missing"
    fi
done

# ------------------------------------------------------------
# 2. Check MTU values = 9000
# ------------------------------------------------------------
for IP in "${!IP_LABELS[@]}"; do
    IFACE=$(ip -4 addr show | awk -v ip="$IP" '$0 ~ ip {print $NF}')
    if [ -n "$IFACE" ]; then
        MTU=$(ip link show "$IFACE" | awk '/mtu/ {print $5}')
        if [ "$MTU" -eq 9000 ] 2>/dev/null; then
            check_result 0 "MTU for $IFACE ($IP)" "9000" "$MTU"
        else
            check_result 1 "MTU for $IFACE ($IP)" "9000" "$MTU"
        fi
    else
        check_result 1 "MTU for IP $IP" "9000" "Interface not found"
    fi
done

# ------------------------------------------------------------
# 3. Ping remote devices
# ------------------------------------------------------------
REMOTE_IPS=("192.168.3.100" "192.168.2.100" "192.168.1.100")
for IP in "${REMOTE_IPS[@]}"; do
    if ping -c 2 -W 2 "$IP" &>/dev/null; then
        check_result 0 "Ping remote device $IP" "Reachable" "Reachable"
    else
        check_result 1 "Ping remote device $IP" "Reachable" "Unreachable"
    fi
done

# ------------------------------------------------------------
# 4. Check sysctl buffer values
# ------------------------------------------------------------
declare -A SYSCTL_EXPECT=(
    ["net.core.rmem_default"]="655360000"
    ["net.core.wmem_default"]="655360000"
    ["net.core.rmem_max"]="500000000"
    ["net.core.wmem_max"]="500000000"
)

SYSCTL_OUTPUT=$(sysctl -p 2>/dev/null)

for KEY in "${!SYSCTL_EXPECT[@]}"; do
    VAL_EXPECT="${SYSCTL_EXPECT[$KEY]}"
    VAL_FOUND=$(echo "$SYSCTL_OUTPUT" | grep "$KEY" | awk -F= '{print $2}' | tr -d ' ')
    if [ "$VAL_FOUND" == "$VAL_EXPECT" ]; then
        check_result 0 "$KEY" "$VAL_EXPECT" "$VAL_FOUND"
    else
        check_result 1 "$KEY" "$VAL_EXPECT" "${VAL_FOUND:-Not found}"
    fi
done

# ------------------------------------------------------------
# 5. Check horizon-loopback-mtu.service status
# ------------------------------------------------------------
if systemctl is-active --quiet horizon-loopback-mtu.service; then
    STATUS="active"
    check_result 0 "Service horizon-loopback-mtu.service" "active (running)" "$STATUS"
else
    STATUS=$(systemctl is-active horizon-loopback-mtu.service 2>/dev/null)
    check_result 1 "Service horizon-loopback-mtu.service" "active (running)" "${STATUS:-inactive}"
fi

# ------------------------------------------------------------
# 6. Check if ptpd services exist
# ------------------------------------------------------------
for SVC in ptpd-service-0 ptpd-service-1; do
    if systemctl list-unit-files | grep -q "$SVC"; then
        check_result 0 "Service $SVC" "Exists" "Exists"
    else
        check_result 1 "Service $SVC" "Exists" "Missing"
    fi
done

# ------------------------------------------------------------
# 7. Check if udev rule exists
# ------------------------------------------------------------
RULE_PATH="/etc/udev/rules.d/99-arduino.rules"
if [ -f "$RULE_PATH" ]; then
    check_result 0 "udev rule $RULE_PATH" "Exists" "Exists"
else
    check_result 1 "udev rule $RULE_PATH" "Exists" "Missing"
fi

# ------------------------------------------------------------
# 8. Check if 10.10.0.x interface exists
# ------------------------------------------------------------
IFACE_1010=$(ip -4 addr show | grep -o "10\.10\.0\.[0-9]*" | head -n1)
if [ -n "$IFACE_1010" ]; then
    check_result 0 "Interface 10.10.0.x" "Exists" "$IFACE_1010"
else
    check_result 1 "Interface 10.10.0.x" "Exists" "Not found"
fi

# ------------------------------------------------------------
# 9. Check if Alazar card is in PCIe Gen2 slot 4
# ------------------------------------------------------------
ALAZAR_INFO=$(lspci -vv | grep -A10 "9373" 2>/dev/null)

if [ -z "$ALAZAR_INFO" ]; then
    check_result 1 "Alazar (9373) PCIe card" "Detected " "Not detected"
else
    check_result 0 "Alazar (9373) PCIe card" "Detected " "Detected"
fi



# ------------------------------------------------------------
# 10. Check AlazarSysInfo details
# ------------------------------------------------------------
ALAZAR_SYSINFO_CMD="/usr/local/AlazarTech/ats9373-7.12.0/AlazarSysInfo"

if [ -x "$ALAZAR_SYSINFO_CMD" ]; then
    SYSINFO_OUTPUT=$(bash -c "$ALAZAR_SYSINFO_CMD" 2>/dev/null)
    if [ -z "$SYSINFO_OUTPUT" ]; then
        check_result 1 "AlazarSysInfo output" "Valid system info" "No output"
    else
        # Expected values
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
            EXPECTED="${SYSINFO_EXPECTS[$KEY]}"
            ACTUAL=$(echo "$SYSINFO_OUTPUT" | grep "$KEY" | sed 's/^[[:space:]]*//')
            if [[ "$ACTUAL" == *"$EXPECTED"* ]]; then
                check_result 0 "AlazarSysInfo: $KEY" "$EXPECTED" "$ACTUAL"
            else
                check_result 1 "AlazarSysInfo: $KEY" "$EXPECTED" "${ACTUAL:-Not found}"
            fi
        done
    fi
else
    check_result 1 "AlazarSysInfo executable" "Exists & executable" "Not found"
fi


# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo "==============================================================="
echo " Checks completed: $PASS_COUNT passed, $FAIL_COUNT failed."
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

END_COMMENT
