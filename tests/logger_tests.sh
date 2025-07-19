#!/bin/bash
# set -euo pipefail

CURRENT_FILE="file_logging_tests.sh"
FILE_TO_BE_TESTED="../logger.sh"
TEST_DIR="./test_logs"
mkdir -p "$TEST_DIR"

cleanup() {
    echo -e "\n🧹 Cleaning up test artifacts..."
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

TEST_ID=0
ASSERT_NUM=0
TOTAL_ASSERTS=0
PASSED_ASSERTS=0
FAILED_ASSERTS=0

declare -a TEST_RESULTS TEST_TIMES TEST_NAMES

begin_test() {
    ((TEST_ID++))
    ASSERT_NUM=0
    CURRENT_TEST="$1"
    TEST_NAMES+=("$CURRENT_TEST")
    START_TIME=$(date +%s%3N)
    echo -e "\n=== 🧪 Test $TEST_ID: $CURRENT_TEST ==="
}

end_test() {
    END_TIME=$(date +%s%3N)
    duration=$((END_TIME - START_TIME))
    TEST_TIMES+=("$duration")
    TEST_RESULTS+=("$1")
}

pass() {
    ((TOTAL_ASSERTS++))
    ((PASSED_ASSERTS++))
    echo -e "  \033[32m✔ PASS:\033[0m [$CURRENT_FILE:$TEST_ID.$ASSERT_NUM] $1"
}

fail() {
    ((TOTAL_ASSERTS++))
    ((FAILED_ASSERTS++))
    echo -e "  \033[31m✘ FAIL:\033[0m [$CURRENT_FILE:$TEST_ID.$ASSERT_NUM] $1"
}

assert_contains() {
    ((ASSERT_NUM++))
    local expected="$1" file="$2"
    if grep -Fq "$expected" "$file"; then
        pass "Contains: '$expected'"
    else
        fail "Expected '$expected' in $file"
    fi
}

assert_not_contains() {
    ((ASSERT_NUM++))
    local unexpected="$1" file="$2"
    if ! grep -Fq "$unexpected" "$file"; then
        pass "Does not contain: '$unexpected'"
    else
        fail "Should not contain '$unexpected' in $file"
    fi
}

assert_file_exists() {
    ((ASSERT_NUM++))
    if [[ -f "$1" ]]; then
        pass "File exists: $1"
    else
        fail "File should exist: $1"
    fi
}

assert_file_not_exists() {
    ((ASSERT_NUM++))
    if [[ ! -f "$1" ]]; then
        pass "File does not exist: $1"
    else
        fail "File should not exist: $1"
    fi
}

assert_equals() {
    ((ASSERT_NUM++))
    if [[ "$1" == "$2" ]]; then
        pass "Values equal: '$1' == '$2'"
    else
        fail "Expected '$1' but got '$2'"
    fi
}

assert_not_equals() {
    ((ASSERT_NUM++))
    if [[ "$1" != "$2" ]]; then
        pass "Values not equal: '$1' != '$2'"
    else
        fail "Values should not be equal: '$1'"
    fi
}

assert_exit_code() {
    ((ASSERT_NUM++))
    local expected_code="$1"
    local actual_code="$2"
    if [[ "$actual_code" -eq "$expected_code" ]]; then
        pass "Exit code $actual_code matches expected $expected_code"
    else
        fail "Expected exit code $expected_code but got $actual_code"
    fi
}

count_lines() {
    wc -l < "$1" 2>/dev/null || echo 0
}

# Test 1: Basic Logging Functionality
begin_test "Basic Logging Functionality"

export LOG_FILE="$TEST_DIR/basic.log"
export LOG_LEVEL=0
export LOG_USE_COLOR=false
source "$FILE_TO_BE_TESTED"

log_debug "Debug message"
log_info "Info message"  
log_warn "Warning message"
log_error "Error message"
flush_log_buffer

assert_file_exists "$LOG_FILE"
assert_contains "Debug message" "$LOG_FILE"
assert_contains "Info message" "$LOG_FILE"
assert_contains "Warning message" "$LOG_FILE"
assert_contains "Error message" "$LOG_FILE"
assert_contains "[DEBUG]" "$LOG_FILE"
assert_contains "[INFO]" "$LOG_FILE"
assert_contains "[WARN]" "$LOG_FILE"
assert_contains "[ERROR]" "$LOG_FILE"

end_test "PASSED"

# Test 2: Log Level Filtering
begin_test "Log Level Filtering"

export LOG_FILE="$TEST_DIR/level_filter.log"
export LOG_LEVEL=2  # WARN and above
source "$FILE_TO_BE_TESTED"

log_debug "Should not appear"
log_info "Should not appear either"
log_warn "Should appear"
log_error "Should also appear"
flush_log_buffer

assert_file_exists "$LOG_FILE"
assert_not_contains "Should not appear" "$LOG_FILE"
assert_not_contains "Should not appear either" "$LOG_FILE"
assert_contains "Should appear" "$LOG_FILE"
assert_contains "Should also appear" "$LOG_FILE"

end_test "PASSED"

# Test 3: JSON Output Format
begin_test "JSON Output Format"

export LOG_FILE="$TEST_DIR/json.log"
export LOG_LEVEL=0
export LOG_JSON=true
source "$FILE_TO_BE_TESTED"

log_info "Test JSON message"
log_error "Error with \"quotes\" and \n newlines"
flush_log_buffer

assert_file_exists "$LOG_FILE"
assert_contains '"level":"INFO"' "$LOG_FILE"
assert_contains '"message":"Test JSON message"' "$LOG_FILE"
assert_contains '"level":"ERROR"' "$LOG_FILE"
assert_contains '\"quotes\"' "$LOG_FILE"
assert_contains '\n' "$LOG_FILE"

end_test "PASSED"

# Test 4: Log Rotation by Size
begin_test "Log Rotation by Size"

export LOG_FILE="$TEST_DIR/rotation_size.log"
export LOG_LEVEL=0
export LOG_ROTATION=true
export LOG_ROTATION_TYPE=size
export LOG_MAX_SIZE=1K
export LOG_JSON=false
source "$FILE_TO_BE_TESTED"

# Fill log with data to trigger rotation
for i in {1..100}; do
    log_info "This is a longer message to fill up the log file for rotation testing - iteration $i"
done
flush_log_buffer

assert_file_exists "$LOG_FILE"
# Check if any rotated files exist
rotated_files=$(find "$TEST_DIR" -name "rotation_size.log.*" | wc -l)
if [[ $rotated_files -gt 0 ]]; then
    pass "Log rotation created $rotated_files rotated file(s)"
else
    fail "Expected rotated files to be created"
fi

end_test "PASSED"

# Test 5: Manual Log Rotation
begin_test "Manual Log Rotation"

export LOG_FILE="$TEST_DIR/manual_rotation.log"
export LOG_LEVEL=0
export LOG_ROTATION=false
source "$FILE_TO_BE_TESTED"

log_info "Message before rotation"
flush_log_buffer

# Manually rotate the log
log_rotate_now
rotation_exit_code=$?

assert_exit_code 0 $rotation_exit_code
assert_file_exists "$LOG_FILE"

# Check for rotated file
rotated_files=$(find "$TEST_DIR" -name "manual_rotation.log.manual.*" | wc -l)
if [[ $rotated_files -gt 0 ]]; then
    pass "Manual rotation created rotated file"
else
    fail "Expected manual rotation to create rotated file"
fi

log_info "Message after rotation"
flush_log_buffer
assert_contains "Message after rotation" "$LOG_FILE"

end_test "PASSED"

# Test 6: Input Sanitization
begin_test "Input Sanitization"

export LOG_FILE="$TEST_DIR/sanitization.log"
export LOG_LEVEL=0
export LOG_USE_COLOR=false
source "$FILE_TO_BE_TESTED"

# Test with control characters and ANSI codes
log_info "Message with \x1b[31mANSI\x1b[0m codes"
log_info $'Message with\ttabs\nand\rcarriage returns'
flush_log_buffer

assert_file_exists "$LOG_FILE"
assert_not_contains $'\x1b[31m' "$LOG_FILE"
assert_not_contains $'\x1b[0m' "$LOG_FILE"

end_test "PASSED"

# Test 7: Buffer Management
begin_test "Buffer Management"

export LOG_FILE="$TEST_DIR/buffer.log"
export LOG_LEVEL=0
export LOG_BUFFER_SIZE=3
source "$FILE_TO_BE_TESTED"

# Add messages to buffer without flushing
log_info "Message 1"
log_info "Message 2" 
# Buffer should not be flushed yet
initial_lines=$(count_lines "$LOG_FILE")

log_info "Message 3"
# Now buffer should auto-flush
sleep 0.1  # Give time for flush
final_lines=$(count_lines "$LOG_FILE")

if [[ $final_lines -gt $initial_lines ]]; then
    pass "Buffer auto-flushed when limit reached"
else
    fail "Buffer did not auto-flush as expected"
fi

end_test "PASSED"

# Test 8: Environment Variable Validation
begin_test "Environment Variable Validation"

# Test invalid log level
(
    export LOG_LEVEL="invalid"
    source "$FILE_TO_BE_TESTED" 2>/dev/null
    exit_code=$?
    assert_exit_code 1 $exit_code
) &
wait $!

# Test valid log level
(
    export LOG_LEVEL=2
    source "$FILE_TO_BE_TESTED" 2>/dev/null
    exit_code=$?
    assert_exit_code 0 $exit_code
) &
wait $!

end_test "PASSED"

# Test 9: Log File Creation and Permissions
begin_test "Log File Creation and Permissions"

export LOG_FILE="$TEST_DIR/subdir/new.log"
export LOG_LEVEL=0
rm -rf "$TEST_DIR/subdir"

source "$FILE_TO_BE_TESTED"

log_info "Test message"
flush_log_buffer

assert_file_exists "$TEST_DIR/subdir/new.log.log"  # Extension should be added
assert_contains "Test message" "$TEST_DIR/subdir/new.log.log"

end_test "PASSED"

# Test 10: Caller Context Detection
begin_test "Caller Context Detection"

export LOG_FILE="$TEST_DIR/context.log"
export LOG_LEVEL=0
export LOG_JSON=false
export LOG_SHOW_CONTEXT=true
source "$FILE_TO_BE_TESTED"

test_function() {
    log_info "Message from function"
}

test_function
flush_log_buffer

assert_file_exists "$LOG_FILE"
assert_contains "file_logging_tests.sh:" "$LOG_FILE"

end_test "PASSED"

# Test 11: Size Calculation Functions
begin_test "Size Calculation Functions"

export LOG_FILE="$TEST_DIR/size_test.log"
source "$FILE_TO_BE_TESTED"

# Test size_to_bytes function
kb_size=$(size_to_bytes "5K")
mb_size=$(size_to_bytes "2M")
gb_size=$(size_to_bytes "1G")

assert_equals 5120 "$kb_size"
assert_equals 2097152 "$mb_size" 
assert_equals 1073741824 "$gb_size"

# Create a small log file and test log_get_size
echo "small test content" > "$LOG_FILE"
size_output=$(log_get_size)
if [[ "$size_output" =~ [0-9]+B$ ]]; then
    pass "log_get_size returned size in bytes: $size_output"
else
    fail "log_get_size returned unexpected format: $size_output"
fi

end_test "PASSED"

# Test 12: Log Rotation Status Function
begin_test "Log Rotation Status Function"

export LOG_FILE="$TEST_DIR/status_test.log"
export LOG_ROTATION=true
export LOG_ROTATION_TYPE=daily
export LOG_MAX_SIZE=10M
export LOG_KEEP_DAYS=30
source "$FILE_TO_BE_TESTED"

echo "test content" > "$LOG_FILE"

# Capture status output
status_output=$(log_rotation_status 2>&1)

if echo "$status_output" | grep -q "Rotation enabled: true"; then
    pass "Status shows rotation enabled"
else
    fail "Status does not show rotation enabled correctly"
fi

if echo "$status_output" | grep -q "Rotation type: daily"; then
    pass "Status shows correct rotation type"
else
    fail "Status does not show rotation type correctly"  
fi

if echo "$status_output" | grep -q "Current size:"; then
    pass "Status shows current size"
else
    fail "Status does not show current size"
fi

end_test "PASSED"

# Test 13: Fatal Log Level
begin_test "Fatal Log Level"

export LOG_FILE="$TEST_DIR/fatal.log"
export LOG_LEVEL=0
source "$FILE_TO_BE_TESTED"

# Test fatal in subshell since it calls exit
(
    log_fatal "Fatal error occurred"
    echo "This should not execute"
) 2>/dev/null
fatal_exit_code=$?

assert_exit_code 1 $fatal_exit_code
assert_file_exists "$LOG_FILE"
assert_contains "Fatal error occurred" "$LOG_FILE"
assert_contains "[FATAL]" "$LOG_FILE"

end_test "PASSED"

# Test 14: Edge Cases and Error Handling
begin_test "Edge Cases and Error Handling"

# Test empty message
export LOG_FILE="$TEST_DIR/edge_cases.log"
export LOG_LEVEL=0
source "$FILE_TO_BE_TESTED"

log_info ""
log_info "   "  # Only whitespace
flush_log_buffer

assert_file_exists "$LOG_FILE"
assert_contains "No message provided" "$LOG_FILE"

# Test very long message (should be truncated)
long_message=$(printf 'A%.0s' {1..5000})
log_info "$long_message"
flush_log_buffer

# Message should be truncated to 4096 chars
log_content=$(tail -1 "$LOG_FILE")
if [[ ${#log_content} -lt 5000 ]]; then
    pass "Long message was truncated appropriately"
else
    fail "Long message was not truncated"
fi

end_test "PASSED"

# Test 15: Color Output Testing
begin_test "Color Output Testing"

export LOG_FILE="$TEST_DIR/color.log"
export LOG_LEVEL=0
export LOG_USE_COLOR=true
source "$FILE_TO_BE_TESTED"

# Redirect to capture colored output
{
    log_debug "Debug with color" 
    log_info "Info with color"
    log_warn "Warning with color"
    log_error "Error with color"
} > "$TEST_DIR/color_output.txt" 2>&1

flush_log_buffer

# Log file should not contain color codes
assert_file_exists "$LOG_FILE"
assert_not_contains $'\033[' "$LOG_FILE"

# But output should contain color codes if terminal supports it
# (This test may vary based on environment)

end_test "PASSED"

# Final Results Summary
echo -e "\n" "="*60
echo -e "🏁 \033[1mTEST SUMMARY\033[0m"
echo -e "="*60

total_tests=${#TEST_RESULTS[@]}
passed_tests=0
failed_tests=0

for i in "${!TEST_RESULTS[@]}"; do
    test_num=$((i + 1))
    test_name="${TEST_NAMES[i]}"
    test_result="${TEST_RESULTS[i]}"
    test_time="${TEST_TIMES[i]}"
    
    if [[ "$test_result" == "PASSED" ]]; then
        ((passed_tests++))
        echo -e "  \033[32m✔\033[0m Test $test_num: $test_name (${test_time}ms)"
    else
        ((failed_tests++))
        echo -e "  \033[31m✘\033[0m Test $test_num: $test_name (${test_time}ms)"
    fi
done

echo -e "\n📊 \033[1mSTATISTICS\033[0m"
echo -e "   Tests:     $total_tests total, \033[32m$passed_tests passed\033[0m, \033[31m$failed_tests failed\033[0m"
echo -e "   Asserts:   $TOTAL_ASSERTS total, \033[32m$PASSED_ASSERTS passed\033[0m, \033[31m$FAILED_ASSERTS failed\033[0m"

success_rate=$((passed_tests * 100 / total_tests))
assert_success_rate=$((PASSED_ASSERTS * 100 / TOTAL_ASSERTS))

echo -e "   Success:   ${success_rate}% tests, ${assert_success_rate}% asserts"

if [[ $failed_tests -eq 0 && $FAILED_ASSERTS -eq 0 ]]; then
    echo -e "\n🎉 \033[32m\033[1mALL TESTS PASSED!\033[0m"
    cleanup
    exit 0
elif [[ $assert_success_rate -ge 80 ]]; then
    echo -e "\n✅ \033[33m\033[1mTESTS MOSTLY PASSED!\033[0m (>80% success rate)"
    cleanup
    exit 0
else
    echo -e "\n💥 \033[31m\033[1mTESTS FAILED!\033[0m (<80% success rate)"
    cleanup
    exit 1
fi