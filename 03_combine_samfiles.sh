#!/usr/bin/env bash

# Author: Sherlyn Weng
# Last Updated: 2025-11-17

set -euo pipefail

usage() {
cat <<EOF
Usage: $(basename "$0") -i input_dir [-o output_dir] [-m memory]

Merge and sort SAM files by read ID (QNAME).

Behavior:
  • Files with names like:
        SAMPLE_index1*.sam, SAMPLE_index2*.sam, ...
    are merged by SAMPLE (prefix before "_index") into:
        <output_dir>/merged/SAMPLE.sam
    then sorted by read ID into:
        <output_dir>/merged_sorted/SAMPLE_sortbyreadid.sam

  • For sorting (merged or individual SAMs):
      - If file has a SAM header (@HD, @SQ, @PG, etc):
            samtools sort -n -O SAM
        is used (header preserved).
      - If file has NO header:
            sort -k1,1 -T <output_dir>/tmp -S <memory>
        is used (lexicographical QNAME sorting).

  • Any *.sam file WITHOUT "_index" in its name is sorted individually into:
        <output_dir>/<name>_sortbyreadid.sam

Options:
  -i   Input directory containing *.sam files            (required)
  -o   Output directory (default: input_dir)
  -m   Memory for headerless GNU sort (default: 64G)
  -h   Show this help message and exit

Examples:
  ./$(basename "$0") -i samfiles_original
  ./$(basename "$0") -i samfiles_original -o samfiles_processed
  ./$(basename "$0") -i samfiles_original -o samfiles_processed -m 32G

Outputs:
  • SAMPLE_index*_*.sam  →  merged/SAMPLE.sam → merged_sorted/SAMPLE_sortbyreadid.sam
  • other.sam            →  other_sortbyreadid.sam in <output_dir>

Notes:
  • Temp directory for headerless sorting is:
        <output_dir>/tmp
  • Requires: samtools >= 1.x, GNU sort
  • WARNING: If output directories exist, they will be removed and recreated!
EOF
}

indir=""
outdir=""
mem="64G"   # default

# Parse options
while getopts ":i:o:m:h" opt; do
  case "$opt" in
    i) indir="$OPTARG" ;;
    o) outdir="$OPTARG" ;;
    m) mem="$OPTARG" ;;
    h) usage; exit 0 ;;
    \?) echo "Error: Unknown option -$OPTARG" >&2; usage; exit 1 ;;
    :)  echo "Error: Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
  esac
done

# Validation
if [[ -z "$indir" ]]; then
  echo "Error: -i input directory is required." >&2
  usage
  exit 1
fi

if [[ ! -d "$indir" ]]; then
  echo "Error: Input directory '$indir' does not exist." >&2
  exit 1
fi

if [[ -z "${outdir:-}" ]]; then
  outdir="$indir"
fi

# Define subdirs: tmp, merged, merged_sorted
tmpdir="$outdir/tmp"
merged_dir="$outdir/merged"
merged_sorted_dir="$outdir/merged_sorted"

# Remove and recreate directories if they exist
if [[ -d "$tmpdir" ]]; then
  echo "Removing existing directory: $tmpdir"
  rm -rf "$tmpdir"
fi

if [[ -d "$merged_dir" ]]; then
  echo "Removing existing directory: $merged_dir"
  rm -rf "$merged_dir"
fi

if [[ -d "$merged_sorted_dir" ]]; then
  echo "Removing existing directory: $merged_sorted_dir"
  rm -rf "$merged_sorted_dir"
fi

# Create fresh directories
mkdir -p "$outdir"
mkdir -p "$tmpdir" "$merged_dir" "$merged_sorted_dir"

# Tool checks
if ! command -v samtools >/dev/null 2>&1; then
  echo "Error: samtools not found in PATH." >&2
  exit 1
fi

if ! command -v sort >/dev/null 2>&1; then
  echo "Error: sort not found in PATH." >&2
  exit 1
fi

echo "Processing SAM files in '$indir'..."
echo "Output directory            : $outdir"
echo "Temp directory (headerless) : $tmpdir"
echo "Merged SAMs directory       : $merged_dir"
echo "Merged & sorted directory   : $merged_sorted_dir"
echo "Memory for GNU sort         : $mem"

shopt -s nullglob

# 1) Identify samples that have index-split SAMs and merge them into outdir/merged
declare -A indexed_samples=()

for f in "$indir"/*.sam; do
  fname=$(basename "$f")
  if [[ "$fname" == *_index* ]]; then
    sample=${fname%%_index*}   # everything before first "_index"
    indexed_samples["$sample"]=1
  fi
done

if (( ${#indexed_samples[@]} > 0 )); then
  echo "Merging index-part SAMs by sample into '$merged_dir'..."
  for sample in "${!indexed_samples[@]}"; do
    merged="$merged_dir/${sample}.sam"
    echo "  → Merging ${sample}_index*.sam → $(basename "$merged")"
    cat "$indir"/"${sample}"_index*.sam > "$merged"
  done
else
  echo "No *_index*.sam files detected; skipping merge step."
fi

# Helper function to sort one SAM file into target
sort_one_sam() {
  local in_sam="$1"
  local out_sam="$2"

  if grep -q '^@' "$in_sam"; then
    echo "  → $(basename "$in_sam") (header detected) → samtools sort -n → $(basename "$out_sam")"
    samtools sort -n -O SAM -o "$out_sam" "$in_sam"
  else
    echo "  → $(basename "$in_sam") (NO header) → sort -k1,1 (tmp: $tmpdir) → $(basename "$out_sam")"
    sort -k1,1 -T "$tmpdir" -S "$mem" "$in_sam" > "$out_sam"
  fi
}

# 2) Sort merged per-sample files into outdir/merged_sorted
for merged in "$merged_dir"/*.sam; do
  # If no merged files, this loop just doesn't run (nullglob)
  mbase=$(basename "$merged" .sam)
  out="$merged_sorted_dir/${mbase}_sortbyreadid.sam"
  sort_one_sam "$merged" "$out"
done

# 3) Sort any remaining SAMs that were NOT part of *_index* groups
echo "Sorting non-index SAMs (if any) into '$outdir'..."
for f in "$indir"/*.sam; do
  fname=$(basename "$f")
  # Skip files that were part of index groups
  if [[ "$fname" == *_index* ]]; then
    continue
  fi
  
  base=$(basename "$f" .sam)
  out="$outdir/${base}_sortbyreadid.sam"
  
  # Remove existing output file if it exists
  if [[ -f "$out" ]]; then
    echo "  → Removing existing: $(basename "$out")"
    rm -f "$out"
  fi
  
  sort_one_sam "$f" "$out"
done

echo "Done! All SAM files processed."