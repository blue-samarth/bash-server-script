#!/bin/bash

# Logging functions
# This script provides functions for logging messages with different severity levels.
# Author: Blue-sam
# Version: 1.1

# Capture the name of the current script for use in logs
SCRIPT_NAME="${BASH_SOURCE[0]##*/}"

fatal() {
    echo -e "\033[1;31m[FATAL]\033[0m $(date '+%Y-%m-%d %H:%M:%S') [$SCRIPT_NAME:${BASH_LINENO[1]}] $*" >&2
    exit 1
}

error() {
    echo -e "\033[0;31m[ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') [$SCRIPT_NAME:${BASH_LINENO[1]}] $*" >&2
}

warn() {
    echo -e "\033[1;33m[WARN]\033[0m $(date '+%Y-%m-%d %H:%M:%S') [$SCRIPT_NAME:${BASH_LINENO[1]}] $*" >&2
}

info() {
    echo -e "\033[0;32m[INFO]\033[0m $(date '+%Y-%m-%d %H:%M:%S') [$SCRIPT_NAME:${BASH_LINENO[1]}] $*"
}

debug() {
    [[ "${DEBUG,,}" == "true" ]] && echo -e "\033[0;34m[DEBUG]\033[0m $(date '+%Y-%m-%d %H:%M:%S') [$SCRIPT_NAME:${BASH_LINENO[1]}] $*"
}
