#!/usr/bin/env bash
set -u

# constant input file (edit if needed)
INPUT_FILE="pairs.txt"

# check inputs
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: INPUT_FILE not found: $INPUT_FILE" >&2
    exit 1
fi

if [ ! -x "./run_one_sample.sh" ]; then
    echo "Error: ./run_one_sample.sh not found or not executable" >&2
    exit 1
fi

# read tab-separated pairs, skip empty lines and comments, run sequentially
tr -d '\r' < "$INPUT_FILE" | while IFS=$'\t' read -r f1 f2 _; do
    # skip blank/comment lines
    [ -z "${f1:-}" ] && continue
    case "$f1" in \#*) continue ;; esac

    if [ -z "${f2:-}" ]; then
        echo "Warning: missing pair for '$f1', skipping" >&2
        continue
    fi

    if [ ! -f "$f1" ]; then
        echo "Warning: file not found: $f1, skipping" >&2
        continue
    fi

    if [ ! -f "$f2" ]; then
        echo "Warning: file not found: $f2, skipping" >&2
        continue
    fi

    echo "Running: ./run_one_sample.sh -f1 '$f1' -f2 '$f2'"
    ./run_one_sample.sh -f1 "$f1" -f2 "$f2"
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "Error: run_one_sample.sh failed for '$f1'/'$f2' (exit $rc)" >&2
        exit $rc
    fi
done

echo "All done."
