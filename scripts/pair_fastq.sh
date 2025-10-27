#!/usr/bin/env bash
# pair_fastq.sh
# Find paired FASTQ files in the current directory (or given dir) and print TSV: sample<TAB>R1<TAB>R2
# Supports common conventions: .1.fq .2.fq, _1.fq _2.fq, _R1.fastq(.gz) / _R2
# Usage: pair_fastq.sh [--dir DIR] [--out FILE] [--interactive] [--dry-run]

set -euo pipefail

usage(){
  cat <<'USAGE'
Usage: pair_fastq.sh [--dir DIR] [--out FILE] [--interactive] [--dry-run]

Options:
  --dir DIR         Directory to scan (default: current directory)
  --out FILE        Write TSV pairs to FILE (default: stdout)
  --interactive     Prompt to confirm each detected pair
  --dry-run         Print pairs but do not write output file
  -h, --help        Show this help

The script detects pairs using common filename patterns:
  sample.1.fq(.gz) / sample.2.fq(.gz)
  sample_1.fastq(.gz) / sample_2.fastq(.gz)
  sample_R1.fastq(.gz) / sample_R2.fastq(.gz)
It is tolerant of .fq / .fastq and .gz compressed files.
USAGE
}

DIR="."
OUT="-"
INTERACTIVE=0
DRYRUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) DIR="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --interactive) INTERACTIVE=1; shift;;
    --dry-run) DRYRUN=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [[ ! -d "$DIR" ]]; then
  echo "Directory not found: $DIR" >&2
  exit 2
fi

# Find candidate FASTQ files
mapfile -t files < <(find "$DIR" -maxdepth 1 -type f -regextype posix-extended -iregex '.*\.(fq|fastq)(\.gz)?$' -printf "%f\n" | sort)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No FASTQ files found in $DIR" >&2
  exit 0
fi

# Normalise names and keys for pairing
declare -A r1map
declare -A r2map
declare -A seen

for f in "${files[@]}"; do
  name="$f"
  # Determine R1 vs R2 using common tokens
  # Patterns tested (case-insensitive): _R1, _R2, _1, _2, .1, .2
  lname=$(echo "$name" | tr '[:upper:]' '[:lower:]')
  if [[ "$lname" =~ (_r1|_r1\.|_r1_|\_1\.|\_1_|\.1\.|\.1$|\.1\.) ]]; then
    key=$(echo "$name" | sed -E 's/(_R1|_r1|_1|\.1)(\.|_|$)/\2/1' )
  fi

  # Simpler pattern matching approach:
  case "$lname" in
    *"_r1"*|*"_r1."*|*"_r1_"*|*"_r1."*|*"_r1.fastq"*|*"_r1.fq"*|*"_r1.fastq.gz"* )
      base=${name//[Rr]1/}
      r1map["$base"]="$name";;
    *"_r2"*|*"_r2."*|*"_r2_"*|*"_r2.fastq"*|*"_r2.fq"*|*"_r2.fastq.gz"* )
      base=${name//[Rr]2/}
      r2map["$base"]="$name";;
    *"_1"*|*"_1."*|*"_1_"*|*"_1.fastq"*|*"_1.fq"*|*"_1.fastq.gz"* )
      base=${name/_1/}
      r1map["$base"]="$name";;
    *"_2"*|*"_2."*|*"_2_"*|*"_2.fastq"*|*"_2.fq"*|*"_2.fastq.gz"* )
      base=${name/_2/}
      r2map["$base"]="$name";;
    *".1."*|*".1" )
      base=$(echo "$name" | sed -E 's/\.1(\.|$)/\1/')
      r1map["$base"]="$name";;
    *".2."*|*".2" )
      base=$(echo "$name" | sed -E 's/\.2(\.|$)/\1/')
      r2map["$base"]="$name";;
    *)
      # not matched; leave as singletons
      seen["$name"]="single"
      ;;
  esac
done

# Build list of pairs
pairs=()
singles=()
for k in "${!r1map[@]}"; do
  if [[ -n "${r2map[$k]:-}" ]]; then
    pairs+=("$k:::${r1map[$k]}:::${r2map[$k]}")
  else
    singles+=("${r1map[$k]}")
  fi
done
for k in "${!r2map[@]}"; do
  if [[ -z "${r1map[$k]:-}" ]]; then
    singles+=("${r2map[$k]}")
  fi
done

# Output handling
write_output(){
  local outpath="$1"
  if [[ "$outpath" == "-" ]]; then
    out=/dev/stdout
  else
    out="$outpath"
  fi
  {
    echo -e "sample\tR1\tR2"
    for p in "${pairs[@]}"; do
      IFS=':::' read -r sample r1 r2 <<< "$p"
      echo -e "${sample}\t${r1}\t${r2}"
    done
    if [[ ${#singles[@]} -gt 0 ]]; then
      echo "";
      echo "# Singletons (unpaired / ambiguous)";
      for s in "${singles[@]}"; do
        echo -e "SINGLE\t${s}\t-"
      done
    fi
  } > "$out"
}

if [[ $INTERACTIVE -eq 1 ]]; then
  echo "Detected the following pairs:"
  for p in "${pairs[@]}"; do
    IFS=':::' read -r sample r1 r2 <<< "$p"
    echo "Sample: $sample"; echo "  R1: $r1"; echo "  R2: $r2"; echo
    read -r -p "Keep this pair? [Y/n] " ans
    ans=${ans:-Y}
    if [[ "$ans" =~ ^([yY]) ]]; then
      keep_pairs+=("$p")
    else
      echo "Skipping $sample"
    fi
  done
  # replace
  pairs=("${keep_pairs[@]:-}")
fi

if [[ $DRYRUN -eq 1 ]]; then
  write_output -
  exit 0
fi

if [[ "$OUT" == "-" ]]; then
  write_output -
else
  write_output "$OUT"
  echo "Wrote pairs to $OUT"
fi
