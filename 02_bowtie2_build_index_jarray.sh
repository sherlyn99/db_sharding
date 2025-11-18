#!/bin/bash
#SBATCH -J mopp
#SBATCH -p short
#SBATCH -N 1
#SBATCH -c 8
#SBATCH --mem 50g
#SBATCH -o slurm-%x-%A-%a-%j-%N.out
#SBATCH -e slurm-%x-%A-%a-%j-%N.err
#SBATCH --export ALL
#SBATCH --mail-type=ALL
#SBATCH --mail-user=y1weng@ucsd.edu ### update account email
#SBATCH --array=1-4 ### update array number

# Author: Sherlyn Weng
# Last Updated: 2025-11-17

set -x
set -e

export TMPDIR=/ddn_scratch/y1weng/
mkdir -p $TMPDIR
export TMPDIR=$(mktemp -d)
function cleanup {
  echo "Removing $TMPDIR"
  rm -r $TMPDIR
  unset TMPDIR
}
trap cleanup EXIT

source /home/y1weng/miniconda3/etc/profile.d/conda.sh
conda activate /home/y1weng/mambaforge/envs/mopp_dev_sherlyn ### update conda env

# Define directories
input_dir="./test/output/split_fnas" ### update input path
output_dir="./test/output/bt2_index" ### update output path
mkdir -p "$output_dir"

# Select the N-th file for this job
fna_file=$(ls "$input_dir"/*.fna | sed -n "${SLURM_ARRAY_TASK_ID}p")
base_name=$(basename "$fna_file" .fna)

# Run indexing (bowtie2 for example)
bowtie2-build "$fna_file" "$output_dir/${base_name}" --large-index --threads 8

conda deactivate
