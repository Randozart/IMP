#!/bin/bash
# IMP SystemVerilog Verifier - Lints generated SV files
#     Copyright (C) 2026 Randy Smits-Schreuder Goedheijt
#
# verify_sv.sh - Verify SystemVerilog files are correct
# Usage: ./verify_sv.sh <file.sv> [file2.sv] ...
#
# When multiple files provided, lints them together (required for testbenches
# that instantiate modules from other files).
# Runs verilator --lint-only and reports errors vs warnings.
# Warnings are expected and acceptable.
# Exit code 0 means no compile errors (warnings are OK).

set -e

LINT_FAILED=0

if [ $# -eq 0 ]; then
    echo "Usage: $0 <file.sv> [file2.sv] ..."
    exit 1
fi

# Check all files exist
for FILE in "$@"; do
    if [ ! -f "$FILE" ]; then
        echo "Error: File '$FILE' not found"
        exit 1
    fi
done

echo "=== Linting $# files together ==="

# Run verilator on all files together (handles testbenches with modules)
# Use --no-timing for testbenches with delay statements (#5, #10, etc)
OUTPUT=$(verilator -Wall --no-timing --lint-only "$@" 2>&1 || true)

# Check for actual compilation errors (not warning summary lines)
# Real errors have location info like "filename.sv:123:45:"
ACTUAL_ERRORS=$(echo "$OUTPUT" | grep "^%Error:.*:[0-9]*:" || true)

if [ -n "$ACTUAL_ERRORS" ]; then
    echo "FAILED: Files have errors"
    echo "$ACTUAL_ERRORS" | head -20
    LINT_FAILED=1
else
    # Count warnings (excluding the "Exiting due to N warning(s)" summary)
    WARN_COUNT=$(echo "$OUTPUT" | grep "^%Warning:" | wc -l)
    if [ "$WARN_COUNT" -gt 0 ]; then
        echo "PASSED (with $WARN_COUNT warnings)"
    else
        echo "PASSED: No warnings or errors"
    fi
fi

if [ $LINT_FAILED -eq 0 ]; then
    echo "=== All files passed lint ==="
else
    echo "=== Some files failed lint ==="
fi

exit $LINT_FAILED