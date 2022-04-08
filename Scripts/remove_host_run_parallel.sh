#!/bin/bash

#########################################################
#
# Platform: NCI Gadi HPC
# Description: see https://github.com/Sydney-Informatics-Hub/Shotgun-Metagenomics-Analysis
#
# Author/s: Cali Willet
# cali.willet@sydney.edu.au
#
# If you use this script towards a publication, please acknowledge the
# Sydney Informatics Hub (or co-authorship, where appropriate).
#
# Suggested acknowledgement:
# The authors acknowledge the scientific and technical assistance
# <or e.g. bioinformatics assistance of <PERSON>> of Sydney Informatics
# Hub and resources and services from the National Computational
# Infrastructure (NCI), which is supported by the Australian Government
# with access facilitated by the University of Sydney.
#
#########################################################

#PBS -P <project>
#PBS -N remhost
#PBS -l walltime=08:00:00
#PBS -l ncpus=144
#PBS -l mem=570GB
#PBS -q normal
#PBS -W umask=022
#PBS -l wd
#PBS -o ./Logs/remove_host.o
#PBS -e ./Logs/remove_host.e
#PBS -lstorage=scratch/<project>

module load openmpi/4.0.2
module load nci-parallel/1.0.0
module load bbtools/37.98

set -e

SCRIPT=./Scripts/remove_host.sh  
INPUTS=./Inputs/remove_host.inputs
 
NCPUS=12 

mkdir -p Target_reads ./Logs/Remove_host

#########################################################
# Do not edit below this line  
#########################################################

if [[ $PBS_QUEUE =~ bw-exec ]]; then CPN=28; else CPN=48; fi
M=$(( CPN / NCPUS )) #tasks per node

sed "s|^|${SCRIPT} |" ${INPUTS} > ${PBS_JOBFS}/input-file

mpirun --np $((M * PBS_NCPUS / CPN)) \
        --map-by node:PE=${NCPUS} \
        nci-parallel \
        --verbose \
        --input-file ${PBS_JOBFS}/input-file





