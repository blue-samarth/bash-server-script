#!/bin/bash

# Logging functions
# This script provides functions for logging messages with different severity levels.
# Author: Blue-sam
# Version: 1.1

# Capture the name of the script for use in logs
# If sourced, use the name of the calling script; if executed directly, use this script's name.
SCRIPT_NAME="${BASH_SOURCE[1]:-${BASH_SOURCE[0]##*/}}"

# Users can override SCRIPT_NAME after sourcing this script if needed.
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

# Debug logging function
# To enable debug logging, set the DEBUG environment variable to "true" (case-insensitive).
debug() {
    [[ "${DEBUG,,}" == "true" ]] && echo -e "\033[0;34m[DEBUG]\033[0m $(date '+%Y-%m-%d %H:%M:%S') [$SCRIPT_NAME:${BASH_LINENO[1]}] $*"
}
