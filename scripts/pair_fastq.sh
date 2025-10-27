#!/usr/bin/env bash

# Check for required arguments
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Error: Missing required arguments" >&2
    echo "Usage: $0 --dir <directory> --pairFormat <r1,r2> --out <output_file>" >&2
    exit 1
fi

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --dir)
            DIR="$2"
            shift 2
            ;;
        --pairFormat)
            PAIR_FORMAT="$2"
            shift 2
            ;;
        --out)
            OUT="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown argument $1" >&2
            exit 1
            ;;
    esac
done

# Validate all arguments are set
if [ -z "$DIR" ] || [ -z "$PAIR_FORMAT" ] || [ -z "$OUT" ]; then
    echo "Error: All arguments (--dir, --pairFormat, --out) are required" >&2
    exit 1
fi

# Check if directory exists
if [ ! -d "$DIR" ]; then
    echo "Error: Directory $DIR does not exist" >&2
    exit 1
fi

# Parse pair format
R1=$(echo "$PAIR_FORMAT" | cut -d',' -f1)
R2=$(echo "$PAIR_FORMAT" | cut -d',' -f2)

# Escape special characters for sed
R1_ESCAPED=$(printf '%s\n' "$R1" | sed 's/[.[\*^$()+?{|]/\\&/g')
R2_ESCAPED=$(printf '%s\n' "$R2" | sed 's/[.[\*^$()+?{|]/\\&/g')

# Clear output file
> "$OUT"

# Find all R1 files
find "$DIR" -type f \( -name "*$R1.fq" -o -name "*$R1.fastq" -o -name "*$R1.fq.gz" -o -name "*$R1.fastq.gz" \) | sort | while IFS= read -r r1_file; do
    # Generate R2 filename by replacing R1 with R2
    r2_file=$(printf '%s' "$r1_file" | sed "s/$R1_ESCAPED/$R2_ESCAPED/")

    # Check if R2 file exists
    if [ -f "$r2_file" ]; then
        # derive sample name from r1 filename (strip .gz, .fastq/.fq and the R1 suffix)
        fname=$(basename "$r1_file")
        base="$fname"
        # remove .gz if present
        case "$base" in
            *.gz) base="${base%.gz}" ;;
        esac
        # remove extensions
        case "$base" in
            *.fastq) base="${base%.fastq}" ;;
            *.fq) base="${base%.fq}" ;;
        esac
        # remove R1 suffix if present at end
        # use sed with escaped pattern to avoid regex issues
        sample=$(printf '%s' "$base" | sed "s/${R1_ESCAPED}$//")

        # write SAMPLE_NAME <tab> R1 <tab> R2
        printf '%s\t%s\t%s\n' "$sample" "$r1_file" "$r2_file" >> "$OUT"
    fi
done

echo "Paired files written to $OUT"
