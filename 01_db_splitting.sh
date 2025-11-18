#!/usr/bin/env bash

# Author: Sherlyn Weng
# Last Updated: 2025-11-17

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") -i input_fasta[.xz] -o output_dir [-n partitions] [-s seed]

Randomly shard a FASTA file into N parts while keeping the number of records
in each partition as equal as possible. Supports multi-line FASTA records.

Options:
  -i  Input FASTA file (.fna/.fa/.fasta or .xz-compressed)
  -o  Output directory (will be created if it does not exist)
  -n  Number of partitions (default: 4)
  -s  Random seed (default: 1234)
  -h  Show this help message and exit

Notes:
  * A "record" is:
        >header
        sequence line(s)...
  * Algorithm:
      - Pass 1: count number of records R.
      - Compute per-partition quotas so that each split gets either
        floor(R/N) or ceil(R/N) records.
      - Pass 2: stream records, and for each new record, randomly choose
        a partition that still has remaining capacity.
  * Summary of how many records went to each split is written to:
        output_dir/split_record_counts.tsv

Example:
  ./$(basename "$0") -i all.fna.xz -o shards -n 4 -s 1234
EOF
}

# Defaults
n=4
seed=1234
input=""
outdir=""

# Parse args
while getopts ":i:o:n:s:h" opt; do
  case "$opt" in
    i) input="$OPTARG" ;;
    o) outdir="$OPTARG" ;;
    n) n="$OPTARG" ;;
    s) seed="$OPTARG" ;;
    h) usage; exit 0 ;;
    \?) echo "Error: Unknown option -$OPTARG" >&2; usage; exit 1 ;;
    :)  echo "Error: Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
  esac
done

# Validation
if [[ -z "$input" || -z "$outdir" ]]; then
  echo "Error: -i input file and -o output dir are required." >&2
  usage
  exit 1
fi

if [[ ! -f "$input" ]]; then
  echo "Error: Input file '$input' does not exist." >&2
  exit 1
fi

if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n <= 0 )); then
  echo "Error: -n partitions must be a positive integer." >&2
  exit 1
fi

if ! [[ "$seed" =~ ^-?[0-9]+$ ]]; then
  echo "Error: -s seed must be an integer." >&2
  exit 1
fi

# Tools
if [[ "$input" == *.xz ]] && ! command -v xzcat >/dev/null 2>&1; then
  echo "Error: Input is .xz but 'xzcat' is not available." >&2
  exit 1
fi
if ! command -v awk >/dev/null 2>&1; then
  echo "Error: 'awk' is required but not found in PATH." >&2
  exit 1
fi

mkdir -p "$outdir"
rm -f "$outdir"/split_*.fna

summary_file="$outdir/split_record_counts.tsv"
rm -f "$summary_file"

# Reader helper
if [[ "$input" == *.xz ]]; then
  reader_cmd=(xzcat -- "$input")
else
  reader_cmd=(cat -- "$input")
fi

echo "Counting records in '$input'..."

# Pass 1: count number of FASTA records (lines starting with '>')
total_records=$(
  "${reader_cmd[@]}" | awk '/^>/{c++} END{print c+0}'
)

if (( total_records == 0 )); then
  echo "Error: No FASTA records found in '$input' (no lines starting with '>')." >&2
  exit 1
fi

echo "Total records: $total_records"

# Compute per-partition quotas: each gets floor(R/N) or ceil(R/N)
base=$(( total_records / n ))
rem=$(( total_records % n ))

quotas=""
for ((i=1; i<=n; i++)); do
  if (( i <= rem )); then
    q=$(( base + 1 ))
  else
    q=$base
  fi
  quotas+="$q "
done

echo "Sharding (random but quota-balanced) into '$outdir'..."

# Pass 2: stream again and randomly assign records to partitions
"${reader_cmd[@]}" \
  | awk -v n="$n" -v out="$outdir" -v seed="$seed" -v quotas="$quotas" -v summary_file="$summary_file" '
      BEGIN {
        srand(seed + 0)

        # Initialize capacities (cap[i]) and usage counters (used[i])
        split(quotas, tmp, " ")
        for (i = 1; i <= n; i++) {
          cap[i]  = ((i in tmp) ? tmp[i] : 0)
          used[i] = 0
        }
        current_file = ""
      }

      # Choose a random partition among those with remaining capacity
      function choose_partition(   have_capacity, idx, i) {
        have_capacity = 0
        for (i = 1; i <= n; i++) {
          if (cap[i] > 0) {
            have_capacity = 1
            break
          }
        }
        if (!have_capacity) {
          # Should not happen if quotas sum to total_records
          return 1
        }

        # Keep sampling until we hit a partition with remaining capacity
        while (1) {
          idx = int(1 + rand() * n)
          if (cap[idx] > 0) {
            cap[idx]--
            used[idx]++
            return idx
          }
        }
      }

      /^>/ {
        # New record: pick partition and set current_file
        part = choose_partition()
        current_file = out "/split_" part ".fna"
      }

      {
        # Print all lines (headers + sequence lines) to chosen file
        if (current_file != "") {
          print >> current_file
        }
      }

      END {
        # Write summary: split_X.fna \t record_count
        for (i = 1; i <= n; i++) {
          printf("split_%d.fna\t%d\n", i, used[i]) >> summary_file
        }
      }
    '

echo "Done."
echo "Outputs : $outdir/split_*.fna"
echo "Summary : $summary_file"
