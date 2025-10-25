#!/usr/bin/env python3
#0.0.1 10/10/2025 init design
#0.0.2 10./16/2025 add TestCaseID and RequirementID


Version="0.0.1"
HW_dependency="none"
SW_dependency="python3"
TestCaseID="SW-212"
RequirementID=["SW-708"]

import sys
import os

class VersionDependencyReporter:
    def __init__(self, version, hw_dep, sw_dep, caseID, requirementID, script_path=None):
        self.script_path = script_path or sys.argv[0]
        self.version = version
        self.hw_dep = hw_dep
        self.sw_dep = sw_dep
        self.caseID = caseID
        self.requirementID = requirementID

    def report_version(self):
        print(f"Version: {self.version}")

    def report_hardware(self):
        print(f"Hardware Dependency: {self.hw_dep}")

    def report_software(self):
        print(f"Software Dependency: {self.sw_dep}")

    def report_caseID(self):
        print(f"Test Case ID: {self.caseID}")

    def report_requirementID(self):
        print(f"Requirement ID: {', '.join(self.requirementID)}")

    def __str__(self):
        return self.version

# Usage with CLI support
if __name__ == "__main__":
    reporter = VersionDependencyReporter(
        version=Version,
        hw_dep=HW_dependency,
        sw_dep=SW_dependency,
        caseID=TestCaseID,
        requirementID=RequirementID  # Fixed variable name
    )

    # Map CLI options to methods
    options = {
        "--version": reporter.report_version,
        "--hw_dependency": reporter.report_hardware,
        "--sw_dependency": reporter.report_software,
        "--test_case_id": reporter.report_caseID,
        "--requirement_id": reporter.report_requirementID  # Fixed method name
    }

    if len(sys.argv) < 2:
        print("No arguments provided.")
        print("Expected arguments: " + ", ".join(options.keys()))
        sys.exit(1)

    matched = False
    for arg in sys.argv[1:]:
        if arg in options:
            options[arg]()
            matched = True

    if not matched:
        print("Unexpected argument received.")
        print("Expected arguments: " + ", ".join(options.keys()))
        sys.exit(1)

'''
Copy below block to executable main 
    #---- version report -----------
reporter = VersionDependencyReporter(
    version=Version,
    hw_dep=HW_dependency,
    sw_dep=SW_dependency,
    caseID=TestCaseID,
    requirementID=RequirementID
)

flag_actions = {
    "--version": reporter.report_version,
    "--hw_dependency": reporter.report_hardware,
    "--sw_dependency": reporter.report_software,
    "--test_case_id": reporter.report_caseID,
    "--requirement_id": reporter.report_requirementID  
}

for flag, action in flag_actions.items():
    if flag in sys.argv:
        action()
        sys.exit(0)
    #==============================     

'''
