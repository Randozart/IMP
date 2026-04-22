#!/bin/bash
# IMP SystemVerilog Verifier - Lints generated SV files
#     Copyright (C) 2026 Randy Smits-Schreuder Goedheijt
#
# verify_sv.sh - Verify SystemVerilog files are correct
# Usage: ./verify_sv.sh <file.sv> [file2.sv] ...
#
# Runs verilator --lint-only and reports errors vs warnings.
# Warnings are expected and acceptable.
# Exit code 0 means no compile errors (warnings are OK).

set -e

LINT_FAILED=0

for FILE in "$@"; do
    if [ ! -f "$FILE" ]; then
        echo "Error: File '$FILE' not found"
        LINT_FAILED=1
        continue
    fi

    echo "=== Linting $FILE ==="

    # Run verilator and capture output
    # Use 2>&1 to capture both stdout and stderr
    # The output goes to stdout with prefix "%Error:" or "%Warning:"
    OUTPUT=$(verilator -Wall --lint-only "$FILE" 2>&1 || true)

    # Check for actual compilation errors (not warning summary lines)
    # Real errors have location info like "filename.sv:123:45:"
    ACTUAL_ERRORS=$(echo "$OUTPUT" | grep "^%Error:.*:[0-9]*:" || true)

    if [ -n "$ACTUAL_ERRORS" ]; then
        echo "FAILED: $FILE has errors"
        echo "$ACTUAL_ERRORS" | head -10
        LINT_FAILED=1
    else
        # Count warnings (excluding the "Exiting due to N warning(s)" summary)
        WARN_COUNT=$(echo "$OUTPUT" | grep "^%Warning:" | wc -l)
        if [ "$WARN_COUNT" -gt 0 ]; then
            echo "PASSED (with $WARN_COUNT warnings): $FILE"
        else
            echo "PASSED: $FILE"
        fi
    fi
    echo ""
done

if [ $LINT_FAILED -eq 0 ]; then
    echo "=== All files passed lint ==="
else
    echo "=== Some files failed lint ==="
fi

exit $LINT_FAILED