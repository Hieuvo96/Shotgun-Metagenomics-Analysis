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

sample=$1

# Create comma-delimited list of interleaved fastq for megahit
interleaved=$(ls ./Target_reads/*${sample}*.interleaved.extracted.fq.gz | tr '\n' , | sed 's/,$//')

#megahit will terminate with exit status 1 if outdir exists. If dir exists, use a dir with timedata to ensure uniqueness. 
outdir=./Assembly/${sample}

if [ -d "$outdir" ]
then
  dt=`date '+%d-%m-%Y_%H:%M:%S'`
  outdir=./Assembly/${sample}_${dt}
fi

megahit \
        --12 $interleaved \
        -o $outdir \
        -t $NCPUS \
        --out-prefix $sample


