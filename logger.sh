#!/bin/bash

# Reusable Logging Library
# Author: Blue-sam
# Version: 2.0.0
# License: MIT


LOG_SCRIPT_NAME="${BASH_SOURCE[1]:-${BASH_SOURCE[0]##*/}}"
: "${LOG_LEVEL:=1}"       
: "${LOG_USE_COLOR:=true}"
: "${LOG_FILE:=}"
: "${LOG_ROTATION:=false}"
: "${LOG_ROTATION_TYPE:=daily}"
: "${LOG_MAX_SIZE:=10M}"
: "${LOG_KEEP_DAYS:=30}"  # Number of days to keep rotated logs
: "${LOG_JSON:=false}"  

declare -A LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
    [FATAL]=4
)

declare -a LOG_BUFFER=()
LOG_BUFFER_SIZE=10


if [[ "$LOG_USE_COLOR" == "true" && ( -t 1 || -t 2 ) ]]; then
    LOG_RED='\033[0;31m'
    LOG_BRIGHT_RED='\033[1;31m'  
    LOG_GREEN='\033[0;32m'
    LOG_YELLOW='\033[1;33m'
    LOG_BLUE='\033[0;34m'
    LOG_BOLD='\033[1m'
    LOG_RESET='\033[0m'
else
    LOG_RED=''; LOG_GREEN=''; LOG_YELLOW=''; LOG_BLUE=''; LOG_BOLD=''; LOG_RESET=''
fi

# Validate log level first it is an integer then check if it is within the valid range
validate_log_level() {
    if ! [[ "$LOG_LEVEL" =~ ^[0-4]$ ]]; then
        echo "Error: LOG_LEVEL must be an integer between 0 and 4" >&2
        return 1
    fi
}
validate_log_level || exit 1

# Check if script name is set
validate_script_name() {
    [[ -n "$LOG_SCRIPT_NAME" ]] || {
        echo "Error: Script name cannot be empty" >&2
        return 1
    }
}
validate_script_name || exit 1

get_rotation_suffix() {
    case "$LOG_ROTATION_TYPE" in
        daily)   date '+%Y-%m-%d' ;;
        weekly)  date '+%Y-W%U' ;;
        monthly) date '+%Y-%m' ;;
        hourly)  date '+%Y-%m-%d-%H' ;;
        *)       date '+%Y-%m-%d' ;;
    esac
}
size_to_bytes() {
    local size="$1"
    case "${size: -1}" in
        K|k) echo $((${size%?} * 1024)) ;;
        M|m) echo $((${size%?} * 1024 * 1024)) ;;
        G|g) echo $((${size%?} * 1024 * 1024 * 1024)) ;;
        *)   echo "${size}" ;;
    esac
}

detect_caller_context() {   
    local depth=1
    while [[ $depth -lt ${#BASH_SOURCE[@]} ]]; do
        local script="${BASH_SOURCE[$depth]}"
        local line="${BASH_LINENO[$((depth - 1))]}"
        if [[ "$script" != "${BASH_SOURCE[0]}" ]]; then
            echo "${script##*/}:$line"
            return
        fi
        ((depth++))
    done
    echo "${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]:-N/A}"
}

needs_rotation() {
    [[ "$LOG_ROTATION" != "true" || -z "$LOG_FILE" || ! -f "$LOG_FILE" ]] && return 1
    
    case "$LOG_ROTATION_TYPE" in
        size)
            local max_bytes current_size
            max_bytes=$(size_to_bytes "$LOG_MAX_SIZE")
            current_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
            [[ "$current_size" -gt "$max_bytes" ]]
            ;;
        daily|weekly|monthly|hourly)
            local rotation_suffix rotated_name
            rotation_suffix=$(get_rotation_suffix)
            rotated_name="${LOG_FILE}.${rotation_suffix}"
            [[ ! -f "$rotated_name" ]]
            ;;
        *)
            return 1
            ;;
    esac
}
cleanup_old_logs() {
    [[ -z "$LOG_FILE" || "$LOG_KEEP_DAYS" -eq 0 ]] && return 0
    
    local log_dir log_basename
    log_dir="$(dirname "$LOG_FILE")"
    log_basename="$(basename "$LOG_FILE")"
    
    if command -v find >/dev/null 2>&1; then
        find "$log_dir" -name "${log_basename}.*" -type f -mtime +${LOG_KEEP_DAYS} -exec rm -f {} \; 2>/dev/null
    else
        for old_log in "$log_dir"/"$log_basename".* ; do
            [[ -f "$old_log" ]] || continue
            if [[ $(date -r "$old_log" +%s 2>/dev/null || echo 0) -lt $(($(date +%s) - LOG_KEEP_DAYS * 86400)) ]]; then
                rm -f "$old_log" 2>/dev/null
            fi
        done
    fi
}
rotate_log() {
    [[ -z "$LOG_FILE" || ! -f "$LOG_FILE" ]] && return 0
    
    local rotation_suffix rotated_name lock_file
    
    case "$LOG_ROTATION_TYPE" in
        size)
            rotation_suffix=$(date '+%Y-%m-%d-%H%M%S')
            rotated_name="${LOG_FILE}.${rotation_suffix}"
            ;;
        *)
            rotation_suffix=$(get_rotation_suffix)
            rotated_name="${LOG_FILE}.${rotation_suffix}"
            ;;
    esac
    
    # Simple lock mechanism to prevent race conditions
    lock_file="${LOG_FILE}.lock"
    
    # Try to acquire lock (atomic operation)
    if (set -C; echo $$ > "$lock_file") 2>/dev/null; then
        # Only rotate if rotated file doesn't exist
        if [[ ! -f "$rotated_name" ]]; then
            flush_log_buffer
            if cp "$LOG_FILE" "$rotated_name" 2>/dev/null; then
                > "$LOG_FILE"  # Truncate current log
                echo "Info: Log rotated to '$rotated_name'" >&2
            else
                echo "Warning: Failed to rotate log file '$LOG_FILE'" >&2
            fi
        fi
        rm -f "$lock_file" 2>/dev/null
    fi
}
log_rotate_now() {
    if [[ -z "$LOG_FILE" ]]; then
        echo "Error: No log file configured for rotation" >&2
        return 1
    fi
    
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "Info: Log file '$LOG_FILE' does not exist, nothing to rotate" >&2
        return 0
    fi
    
    local timestamp rotated_name
    timestamp=$(date '+%Y-%m-%d-%H%M%S')
    rotated_name="${LOG_FILE}.manual.${timestamp}"
    
    flush_log_buffer
    if cp "$LOG_FILE" "$rotated_name" 2>/dev/null; then
        > "$LOG_FILE"
        echo "Info: Manual log rotation completed: '$rotated_name'" >&2
        cleanup_old_logs
    else
        echo "Error: Failed to rotate log file '$LOG_FILE'" >&2
        return 1
    fi
}
log_get_size() {
    [[ -z "$LOG_FILE" || ! -f "$LOG_FILE" ]] && { echo "0B"; return; }
    
    local size_bytes
    if command -v stat >/dev/null 2>&1; then
        size_bytes=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    else
        # Fallback for systems without stat
        size_bytes=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    fi
    
    if [[ "$size_bytes" -gt 1073741824 ]]; then
        echo "$((size_bytes / 1073741824))G"
    elif [[ "$size_bytes" -gt 1048576 ]]; then
        echo "$((size_bytes / 1048576))M"
    elif [[ "$size_bytes" -gt 1024 ]]; then
        echo "$((size_bytes / 1024))K"
    else
        echo "${size_bytes}B"
    fi
}
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"   # Escape backslashes
    s="${s//\"/\\\"}"   # Escape double quotes
    s="${s//	/\\t}"     # Escape tabs (note: real tab char)
    s="${s//$'\r'/\\r}" # Escape carriage return
    s="${s//$'\n'/\\n}" # Escape newlines
    printf '%s' "$s"
}

validate_log_file() {
    [[ -z "$LOG_FILE" ]] && return 0 

    local log_dir log_name
    log_dir="$(dirname "$LOG_FILE")"
    log_name="$(basename "$LOG_FILE")"

    if [[ ! -d "$log_dir" ]]; then
        echo "Info: Log directory '$log_dir' does not exist. Creating it..." >&2
        mkdir -p "$log_dir" || {
            echo "Error: Failed to create log directory '$log_dir'" >&2
            return 1
        }
    fi

    if [[ ! -w "$log_dir" ]]; then
        echo "Error: Cannot write to log directory '$log_dir'" >&2
        return 1
    fi

    if [[ "$log_name" != *.* ]]; then
        LOG_FILE="${LOG_FILE}.log"
        echo "Info: No extension specified, using '$LOG_FILE'" >&2
    fi

    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE" 2>/dev/null || {
            echo "Error: Cannot create log file '$LOG_FILE'" >&2
            return 1
        }
        echo "Info: Created log file '$LOG_FILE'" >&2
    fi

    if [[ ! -w "$LOG_FILE" ]]; then
        echo "Error: Log file '$LOG_FILE' is not writable" >&2
        return 1
    fi

    return 0
}
validate_log_file || exit 1

trap flush_log_buffer EXIT INT TERM

should_log() {
    local level="$1"
    [[ -n "${LOG_LEVELS[$level]}" ]] || { echo "Invalid log level: $level" >&2; return 1; }
    local level_num="${LOG_LEVELS[$level]}"
    [[ "$level_num" -ge "$LOG_LEVEL" ]]
}
log_sanitize() {
    local input="$*"

    # Remove ANSI, OSC sequences, control characters
    sanitized=$(printf '%s' "$input" | sed -E '
        s/\x1B\[[0-9;]*[mGKHJfABCD]//g
        s/\x1B\][^\a]*\a//g
        s/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]//g
    ' | head -c 4096)

    # Trim leading/trailing whitespace using Bash
    sanitized="${sanitized#"${sanitized%%[![:space:]]*}"}"
    sanitized="${sanitized%"${sanitized##*[![:space:]]}"}"

    printf '%s' "$sanitized"
}

# Buffering-logics

buffer_log() {
    LOG_BUFFER+=("$1")
    if [[ ${#LOG_BUFFER[@]} -ge $LOG_BUFFER_SIZE ]]; then
        flush_log_buffer
    fi
}
flush_log_buffer() {
    [[ -z "$LOG_FILE" ]] && return
    [[ ${#LOG_BUFFER[@]} -eq 0 ]] && return

    if ! printf '%s\n' "${LOG_BUFFER[@]}" >> "$LOG_FILE"; then
        echo "Error: Failed to flush log buffer to '$LOG_FILE'" >&2
        return 1
    fi

    LOG_BUFFER=()
}

_log_print() {
    local level="$1" color="$2"; shift 2
    should_log "$level" || return

    local sanitized timestamp log_line output_line caller_context
    sanitized=$(log_sanitize "$@")
    [[ -z "$sanitized" ]] && sanitized="No message provided"

    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    caller_context=$(detect_caller_context)

    if [[ "$LOG_JSON" == "true" ]]; then
        local esc_msg esc_script
        esc_msg="$(json_escape "$sanitized")"
        esc_script="$(json_escape "$caller_context")"
        log_line="{\"level\":\"$level\",\"timestamp\":\"$timestamp\",\"context\":\"$esc_script\",\"message\":\"$esc_msg\"}"
        output_line="$log_line"
    else
        if [[ "${LOG_SHOW_CONTEXT:-true}" == "true" ]]; then
            log_line="[$level] $timestamp [$caller_context] $sanitized"
        else
            log_line="[$level] $timestamp $sanitized"
        fi

        if [[ "$LOG_USE_COLOR" == "true" ]]; then
            output_line="${color}[$level]${LOG_RESET} $timestamp [$caller_context] $sanitized"
        else
            output_line="$log_line"
        fi
    fi

    if [[ "$level" == "INFO" || "$level" == "DEBUG" ]]; then
        echo -e "$output_line" >&1
    else
        echo -e "$output_line" >&2
    fi

    if [[ -n "$LOG_FILE" ]]; then
        if needs_rotation; then
            rotate_log
        fi
        buffer_log "$log_line"
    fi
}

# Replace existing log_rotation_status function
log_rotation_status() {
    echo "=== Log Rotation Status ==="
    echo "Rotation enabled: $LOG_ROTATION"
    echo "Rotation type: $LOG_ROTATION_TYPE"
    echo "Max size: $LOG_MAX_SIZE"
    echo "Keep days: ${LOG_KEEP_DAYS:-"Not set"}"
    echo "Current log file: ${LOG_FILE:-"Not configured"}"
    
    if [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]]; then
        echo "Current size: $(log_get_size)"
        
        local last_mod
        if command -v stat >/dev/null 2>&1; then
            last_mod=$(stat -f%Sm "$LOG_FILE" 2>/dev/null || stat -c%y "$LOG_FILE" 2>/dev/null || echo "Unknown")
        else
            last_mod="Unknown"
        fi
        echo "Last modified: $last_mod"
        
        local log_dir log_basename count
        log_dir="$(dirname "$LOG_FILE")"
        log_basename="$(basename "$LOG_FILE")"
        count=0
        for rotated_file in "$log_dir"/"$log_basename".* ; do
            [[ -f "$rotated_file" ]] && ((count++))
        done
        echo "Rotated files: $count"
    fi
    echo "=========================="
}

log_debug() { _log_print "DEBUG" "$LOG_BLUE" "$@"; }
log_info()  { _log_print "INFO" "$LOG_GREEN" "$@"; }
log_warn()  { _log_print "WARN" "$LOG_YELLOW" "$@"; }
log_error() { _log_print "ERROR" "$LOG_RED" "$@"; }
log_fatal() { _log_print "FATAL" "${LOG_BOLD}${LOG_BRIGHT_RED}" "$@"; flush_log_buffer; exit 1; }

log_set_script_name() {
    [[ -n "$1" ]] || { echo "Error: Script name cannot be empty" >&2; return 1; }
    LOG_SCRIPT_NAME="$1"
}
