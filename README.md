# DB Sharding
Partition large databases into manageable shards to enable processing of datasets that are otherwise computationally prohibitive

NB: These scripts are currently designed for internal use in the Knight Lab. Please do not hesitate to reach out if you find this helpful outside of KL. 


# Example Commands

## Script 1: split the fna file 
chmod +x ./01_db_splitting.sh
./01_db_splitting.sh -i ./test/input/all.fna -n 5 -o ./test/output/split_fnas



## Script 2: make index (using bowtie2 as an example)
# Since index buiding is usually resource intensive, this part is done using slurm job arrays
# Assume using slurm on barnacle2, first updated your email, conda env containing the index-building tool, input & output path, and job array number in 02_bowtie2_build_index_jarray.sh, then run 

sbatch 02_bowtie2_build_index_jarray.sh



## Script 3: combine samfiles post-alignment
# Make sure your input sams have no headers
# Requires: samtools >= 1.x
chmod +x ./03_combine_samfiles.sh
./03_combine_samfiles.sh -i ./test/input/sams_noheader -o ./test/output/sams_out
