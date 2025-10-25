#!/bin/bash

# Function used for sys checks
cmd() {
  local command="$*"
  local cmd_is_local=false

  if [[ -z "$REMOTE_PC" || "$REMOTE_PC" == "localhost" ]]; then
    cmd_is_local=true
  fi

  if $cmd_is_local; then
    cmd_result=$(bash -c "$command" 2>&1)
    cmd_exit_code=$?
  else
    ping -c 1 "$REMOTE_PC" &>/dev/null
    if [[ $? -ne 0 ]]; then
      echo -e "$yellow [ping] $REMOTE_PC unreachable $text_style_reset"
      cmd_result="ping failed"
      cmd_exit_code=0
      return
    fi

    if [[ "$command" == sudo* ]]; then
      cmd_result=$(sshpass -p "$PASSWORD" ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no horizon@"$REMOTE_PC" \
        "echo \"$PASSWORD\" | sudo -S ${command#sudo }" 2>&1)
    else
      cmd_result=$(sshpass -p "$PASSWORD" ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no horizon@"$REMOTE_PC" \
        "$command" 2>&1)
    fi
    cmd_exit_code=$?
  fi
}

scp_file(){
  local command="scp"
  local cmd_is_local=false
  local local_file="$1"
  local remote_file="$2"

  if [[ -z "$REMOTE_PC" || "$REMOTE_PC" == "localhost" ]]; then
    cmd_is_local=true
  fi

  if $cmd_is_local; then
    cp "$local_file" "$remote_file"

  else
    ping -c 1 "$REMOTE_PC" &>/dev/null
    if [[ $? -ne 0 ]]; then
      echo -e "$yellow [ping] $REMOTE_PC unreachable $text_style_reset"
      cmd_result="ping failed"
      cmd_exit_code=0
      return
    fi

    sshpass -p "$PASSWORD" scp "$local_file" horizon@"$REMOTE_PC":/tmp/ 2>&1

    cmd_exit_code=$?
  fi




}


run_check() {
  local description="$1"
  local actual="$2"
  local expected="$3"
  echo -e "$title $description"

  local actual_normalized=$(echo "$actual" | sed 's/^ *//;s/ *$//' | tr -s '[:space:]' ' ')
  local pass=0
#   echo ip addr: $ip_addr Link state: $link_state 

  IFS='|' read -ra expected_values <<< "$expected"
  for val in "${expected_values[@]}"; do
    local expected_normalized=$(echo "$val" | sed 's/^ *//;s/ *$//' | tr -s '[:space:]' ' ')
    if echo "$actual_normalized" | grep -qF "$expected_normalized"; then
      pass=1
      break
    fi
  done

  if [[ $pass -eq 1 ]]; then
    echo -e "$green $actual --pass $text_style_reset"
  else
    echo -e "$red Expected: $expected"
    echo -e " Actual: $actual $text_style_reset"
    failed=1
  fi
}