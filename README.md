# Shotgun Metagenomics Analysis
Analysis of metagenomic shotgun sequences including assembly, speciation, ARG discovery and more

## Description
The input for this analysis is paired end next generation sequencing data from metagenomic samples. The workflow is designed to be modular, so that individual modules can be run depending on the nature of the metagenomics project at hand. More modules will be added as we develop them - this repo is a work in progress!

These scripts have been written specifically for NCI Gadi HPC, wich runs PBS Pro, however feel free to use and modify for another system if you are not a Gadi user. 

### Part 1. Setup and QC
Download the repo. You will see directories for `Scripts`, `Fastq`, `Inputs` and `Logs`. You will need to copy or symlink your fastq to `Fastq` and sample configuration file (see below) to `Inputs`. All work scripts are in `Scripts` and all logs (PBS and software logs) are written to `Logs`.
 

#### 1.1 Fastq inputs
The scripts assume all fastq files are paired, gzipped, and all in the one directory named 'Fastq'. If your fastq are within a convoluted directory structure (eg per-sample directories) or you would simply like to link them from an alternate location, please use the script `setup_fastq.sh`, or else just copy your fastq files to `workdir/Fastq`.

To use this script, parse the path name of your fastq directory as first argument on the command line, and run the script from the base working directory (<your_path>/Shotgun-Metagenomics-Analysis) which will from here on be referred to as `workdir`. Note that **the scripts used in this workflow look for `f*q.gz` files** (ie fastq.gz or fq.gz) - if yours differ in suffix, the simplest solution is to rename them.

```
bash ./Scripts/setup_fastq.sh </path/to/your/parent/fastq/directory>
```

#### 1.2 Configuration/sample info
The only required input configuration file should be named `<cohort>.config`, where `<cohort>` is the name of the current batch of samples you are processing, or some other meaningful name to your project; it will be used to name output files. The config file should be placed inside the `workdir/Inputs` directory, and include the following columns, in this order:

```
1. Sample ID - used to identify the sample, eg if you have 3 lanes of sequencing per sample, each of those 6 fastq files should contain this ID that is in column 1
2. Lab Sample ID - can be the same as column 1, or different if you have reason to change the IDs eg if the seq centre applies an in-house ID. Please make sure IDs are unique within column 1 and unique within column 2
3. Platform - should be Illumina; other sequencing platforms are not tested on this workflow
4. Sequencing centre name
5. Group - eg different time points or treatment groups. If no specific group structure is relevant, can be left blank 
```

Please **ensure your sample IDs are unique within column 1 and unique within column 2**, and do not have spaces in any of the values for the config file.

The number of rows in the config file should be the number of samples plus 1 (for the header, which should start with a `#` character). Ie, even if your samples have multiple input fastq files, you still only need one row per sample, as the script will identify all fastq belonging to each sample based on the ID in column 1. 


#### 1.3 General setup

All scripts will need to be updated to reflect your NCI project code at the `-P <project>` and `-l <storage>` directive. Running the script `create_project.sh` and following the prompts will complete some of the setup for you. 

Note that you will need to manually edit the PBS resource requests for each PBS script depending on the size of your input data; guidelines/example resources will be given at each step to help you do this. As the `sed` commands within this script operate on `.sh` files, this setup script has been intentionally named `.bash`.

Remember to submit all scripts from your `workdir`. 

Run the below command and follow the prompts:

```
bash ./Scripts/create_project.sh
```

For jobs that execute in parallel, there are 3 scripts: one to make the 'inputs' file listing the details of each parallel task, one job execution shell script that is run over each task in parallel, and one PBS launcher script. The process is to submit the make input script, check it to make sure your job details are correct, edit the resources directives depending on the number and size of your parallel tasks, then submit the PBS launcher script with `qsub`. 

The parallel launcher script has been set up to make the workflow efficient and scalable. You can request parts of a node, a whole node, or multiple whole nodes. For example, to run the same task over 40 samples, instead of submitting 40 separate jobs, or running one long job with each sample running in serial (one after the other), we can submit the 40 jobs in parallel with the launcher script. If each sample was to use 12 CPUs, that's 40 x 12 CPUs = 480 CPUs, which is 10 of the 'normal' nodes on Gadi (see [Gadi queue structure](https://opus.nci.org.au/display/Help/Queue+Structure) and [Gadi queue limits](https://opus.nci.org.au/display/Help/Queue+Limits)). If a sample needed 1 hour to run, we could run the entire job in 1 hour walltime, rather than the serial approach which would require 40 hours. To reduce the number of nodes required, we could for example request only 5 nodes, but increase the walltime to 2 hours. This flexibility enables us to take full advtantage of Gadi's resources for larger datasets, while still being applicable to smaller datasets, simply by adjusting the nodes, memory and walltime requested.  

#### 1.4 QC

Run fastQC over each fastq file in parallel. Adjust the resources as per your project. To run all files in parallel, set the number of CPUS requested equal to the number of fastq files (remember that Gadi can only request <1 node or multiples of whole nodes,not for example 1.5 nodes). The make input script sorts the fastq files largest to smallest, so if you have a discrepancy in file size, optimal efficiency can be achieved by requesting less CPUs than the total required to run all your fastq in parallel.

FastQC does not multithread on a single file, so CPUs per parallel task is set to 1. Example walltimes on Gadi 'normal' queue:  one 1.8 GB fastq = 4 minutes; one 52 GB fastq file = 69.5 minutes. Allow 4 GB RAM per CPU requested. 

Please note that if you have symlinked fastq files from another project storage area on Gadi, you will need to ensure that project storage space is specified at the `-l storage` directive, otherwise FastQC will return an error "Skipping '<fastq file name>' which didn't exist, or couldn't be read". 

Make the fastqc parallel inputs file by running (from `workdir`):
```
bash ./Scripts/fastqc_make_inputs.sh
```

Edit the resource requests in `fastqc_run_parallel.pbs` according to your number of fastq files and their size. Eg for 30 fastq files, set ncpus=30 and mem=120 (4 GB per CPU on the `normal` queue), then submit:
```
qsub ./Scripts/fastqc_run_parallel.pbs
```

**For all jobs in this workflow, check that the job was successful through multiple measures:**

- Check the expected output exists, in this case fastQC output for each fastq file within the `workdir/FastQC` directory
- Check that the ".o" PBS log file shows an exit status of zero, and that the resources used are in line with expectations
- Check that each sub-task completed with an exit status of zero, by running this command: 
	- `grep "exited with status 0" Logs/fastqc.e | wc -l
	- The number returned should equal the number of parallel tasks run by the job

To ease manual inspection of the fastQC output, running `multiqc` is recommended. This will collate the individual FastQC reports into one report. This can be done on the login node for small sample numbers, or using the below script for larger cohorts. 


For small numbers, run the 3 commands below on the login node. Eg for 30 fastq files of 1 - 3 GB each, the run time is < 30 seconds:

```
module load multiqc/1.9
mkdir -p ./MultiQC
multiqc -o ./MultiQC ./FastQC
```

For larger cohorts, edit the PBS directives, then run:

```
qsub ./Scripts/multiqc.pbs
```

Save a copy of `./MultiQC/multiqc_report.html` to your local disk then open in a web browser to inspect the results. 

#### 1.5 Quality filtering and trimming

Will be added at a later date. This is highly dependent on the quality of your data and your individual project needs so will be a guide only. 

### Part 2. Removal of host DNA contamination 

If you have metagenomic data extracted from a host (eg tissue, saliva), you will need a copy of the host reference genome sequence in order to remove any DNA sequences belonging to the host. Even if your wetlab protocol included a host removal step, it is still important to run bioinformatic host removal, as lab-based host removal is rarely perfect.


#### 2.1 Prepare the reference
If you ran `create_project.sh` you would have been asked for the full path to your host reference genome. This will add the reference to the `bbmap_prep.pbs` script below. If you did not run `create_project.sh` you will need to manually add the full path to your host reference fasta sequence in the below BBtools scripts.

This step repeat-masks the reference and creates the required BBtools index. If you are unsure whether your genome is already repeat-masked, you can run the script as-is, as there is no problem caused by running bbmask over an already-masked reference.

This workflow requires BBtools (tested with version 37.98). As of writing, **BBtools is not available as a global app on Gadi. Please install locally** and make "module loadable", or else edit the scripts to point directly to your local BBtools installation.

BBtools repeat masking will use all available threads on machine and 85% of available mem by default. 

To run:
```
qsub ./Scripts/bbmap_prep.pbs
```

The BBtools masked reference and index will be created in `./ref`. Don't be alarmed if you observe that the number of contigs/chromosomes in your reference are not represented in the BBmap output file names. For example, the human genome will typically show 7 'chroms'. View the BBmap `info.txt` and `summary.txt` files to see that many contigs are combined together to create fewer contigs of more equal size.  

#### 2.2 Host contamination removal

Run host contamination removal over each fastq pair in parallel. 

The below script assumes your R1 fastq files match the following pattern: ` *_R1*.f*q.gz`. Please check, and if this pattern does not apply to your data, please edit the corresponding line within the make inputs script.

Make the remove_host parallel inputs file by running (from `workdir`):
```
bash ./Scripts/remove_host_make_input.sh
```

The number of remove host tasks to run should be equal to the number of fastq pairs that you have (ie, fastq files divided by 2, NOT the total number of samples in the cohort). If this is not the case, please check 1) that the above pattern matches your fastq filenames, or 2) that your fastq files are all within (or symlinked to) ./Fastq, with no fastq files nested within subdirectories.

View the file `Inputs/remove_host.inputs`. It should be a list of file pair prefixes, ie the unique prefix of each fastq pair, without the R1|R2 designation or fastq.gz suffix.

Edit the resource requests in `remove_host_run_parallel.pbs` according to your number of fastq file pairs, data size and host: 

- 12 CPUs and 48 GB RAM per task is the minimum required for mammalian host
- BBmap scales well, so increasing the CPUs per task will decrease walltime efficiently 
- The run script defaults to 24 CPU per sample and 12 hours walltime. Most samples with ~ 6 GB input gzipped fastq will complete in less than 6 hours, but the odd sample will die on walltime. These can be collected and resubmitted with `remove_host_find_failed`. 
- Tasks that fail on walltime should be resubmitted with 48 CPU per sample
- Example: 40 pairs fastq.gz, each file = 2 GB ( 4 GB per fastq pair), mammalian host = 24 CPU per task, total 40 x 24 =  960 CPUs (20 nodes) for 6 hours to run all samples in parallel, or 480 CPUs (10 nodes) at 12 hours walltime. 15 fastq pairs would require 8 nodes (384 CPUs), as 15 x 24 = 360 which is 7.5 nodes, and Gadi requires whole nodes for multi-node jobs. This method of determining walltime and nodes can be applied to all of the steps which use the "run_parallel" method.  

Then submit:
```
qsub ./Scripts/remove_host_run_parallel.pbs
```

Some samples may need additional walltime compared to others of a similar input size. After this job has completed, run the below script to find failed tasks needing to be resubmitted with longer walltime. In future releases, we will include an option to split and parallelise the remove host step, as this is one of the slowest parts of the workflow.

```
bash ./Scripts/remove_host_find_failed_tasks.sh
```
 
Update the resource requests in `remove_host_failed_run_parallel.pbs`, ensuring to increase the NCPUs per parallel task to 48, and double the walltime (or more, depending on your data), then submit with `qsub`.

The output of remove host will be interleaved fastq in `./Target_reads` that has the host-derived DNA removed, leaving only putative microbial reads for downstream analysis. 


After the completion of this step, you can continue directly to steps 3, 4 or 9. Step 9 is straightforward but has a long run time, so skiping ahead to run this step before contonuing with step 3 can help save analysis time. Step 4 can be run on target reads or filtered assemblies (or both). 

### Part 3. Metagenome assembly

#### 3.1 Assemble target reads

This analysis takes the target (host-removed) reads and assembles them into contigs with Megahit. Later, contigs are used as input to other parts of the workflow. Not all analyses require contigs (for example Bracken abundance estimation and Humann2 functional profiling take reads as input) so you may omit assembly depending on your particular analytical needs.

The number of parallel tasks is equal to the number of samples. A sample may have multiple pairs of input fastq. The `assemble.sh` script will find all fastq pairs belonging to a sample using the sample ID. So it is critical that your sample IDs are unique within the cohort (see note in  'Configuration/sample info' section above).

Megahit assembler will exit if the specified output directory exists. The script `assemble.sh` uses output directory `./workdir/Assembly/<sample>`. If the script finds this directory already exists, it will assume you are resuming a previously failed run for that sample (eg died on walltime) and apply the `--continue` flag to Megahit. 

Samples with 3-4 GB total target read fastq.gz using 24 CPU should complete in approximately 1.75 hours.

Make inputs file:
```
bash ./Scripts/assemble_make_inputs.sh
```

Adjust resource requests and then submit:
```
qsub ./Scripts/assemble_run_parallel.pbs
```

The output of this analysis will be fasta assemblies for each sample within the `Assembly` directory, eg the assembled contigs for Sample1 will be `./Assembly/Sample1/Sample1.contigs.fa`.

#### 3.2 Align target reads to assemblies

Mapping the target reads back to the assembled contigs is a useful way of assessing the read support for each contig. We use this method to filter away contigs with very low mapping support.

The number of parallel tasks is equal to the number of samples. A sample may have multiple pairs of input fastq. The `align_reads_to_contigs.sh` script will find all fastq pairs belonging to a sample using the sample ID. So it is critical that your sample IDs are unique within the cohort (see note in 'Configuration/sample info' section above).

Metadata is added to the BAM from 2 places: 1) Platform and sequencing centre are derived from the config, and 2) flowcell and lane are derived from the fastq read IDs. The method of extracting flowcell and lane assumes standard Illumina read ID format (flowcell in field 3 and lane in field 4 of a colon (:) delimited string. If this is not correct, please update the method of extracting flowcell and lane within part 3 'Align' in `align_reads_to_contigs.sh`.

Make the inputs:
```
bash ./Scripts/align_reads_to_contigs_make_input.sh
```

Adjust the resources depending on the number of parallel tasks and sample size. Example of 3-4 GB target fastq.gz per sample requires 35 minutes on 12 CPU. Submit:
```
qsub ./Scripts/align_reads_to_contigs_run_parallel.pbs
```

Output will be created in `./Align_to_assembly/<sampleDir>`. 

#### 3.3 Calculate contig read coverage

This step computes the read coverage metrics across the contigs from the sorted BAM files created in the preceding step.

Running the make_input script will ask the user to input the minimum base and mapping quality scores to use for coverage calculation. Values of 20 for both is a fair start. It is not recommended to use values below 20, however you may wish to use higher values for more stringent filtering. 

The coverage calculation takes ~ 2.5 minutes for a 3.5 GB BAM file.

Make the inputs file, entering your chosen quality values when prompted:
```
bash ./Scripts/contig_coverage_make_input.sh
```

Adjust the resources, then submit:
```
qsub ./Scripts/contig_coverage_run_parallel.pbs
```

The output coverage file will be sent to the same output directory as above, and will be used to filter away contigs with low mapping support at the next step.

#### 3.4 Filter contigs

Contigs with low mapping support are filtered away here. You can customise this filtering step depending on how strict you want your final assembly to be. The included script defaults to a lenient approach to filtering, simply removing contigs where the mean mapping depth/sequence coverage across the contig is less than 1.

The script `./Scripts/filter_contigs.sh` can be customised to filter on any of the following parameters (from SAMtools coverage `man` page): 

| Column | Description                                          |
| ------ | ---------------------------------------------------- |
| 1      | Reference name / chromosome                          |
| 2      | Start position                                       |
| 3      | End position (or sequence length)                    |
| 4      | Number reads aligned to the region (after filtering) |
| 5      | Number of covered bases with depth >= 1              |
| 6      | Proportion of covered bases \[0..1\]                 |
| 7      | Mean depth of coverage                               |
| 8      | Mean baseQ in covered region                         |
| 9      | Mean mapQ of selected reads                          |

The default filter uses the following `awk` syntax to apply the read depth 1 filter:
```
awk '$7>=1' $cov
```

This takes all rows from the file $cov (where each row represents a contig) where the value in column 7 is greater than or equal to 1. To expand the filter to include for example only contigs of length at least 10,000 bp, adjust the `awk` command to this:
```
awk '$7>=1 && $3>=10000' $cov
```

Add as many filters as desired. 

There is no need to make an inputs file for this step, as the inputs made for the contig coverage step above will be used. 

Adjust the resource requests depending on the number of samples and their data size. Assemblies of around 300 MB take only 10 seconds to filter, however with large numbers of samples this can add up so running on the login node is not recommended.

Then submit:
```
qsub ./Scripts/filter_contigs_run_parallel.pbs
```

The output will be a new filtered contig fasta file in the `Assembly directory`, eg for Sample1,  the output will be `./Assembly/Sample1/Sample1.filteredContigs.fa`.

#### 3.5 Create target read and assembly summaries

This analysis summarises the number of raw and target reads, % host contamnination, number of contigs (raw and filtered), contig size and N50 values for each smaple into one TSV file. 

There is no need to create an inputs file as the inputs sample list from the assembly step will be used.

Adjust the resources then submit:
```
qsub ./Scripts/target_reads_and_assembly_summaries_run_parallel.pbs
```

This job will create a temp file `./Assembly/<sample>/<sample>.summary.txt` for each sample that will be deleted at the next step, which collates these into one per-cohort summary TSV, with one sample per row.

Collate the summaries:
```
bash ./Scripts/target_reads_and_assembly_summaries_collate.sh
```


### Part 4. Speciation and abundance
This analysis determines the species present within each sample, and their abundance. The analysis can be performed on the target read (host removed) data, or on the filtered contigs from Part 3 Assembly, or both. Abundance estimation with Bracken is usually performed on reads, as per the guidelines for that software. Performing speciation on contigs is useful for Part 6. Antimicrobial resistance genes and Part 9. Insertion sequence elements, as it enables us to assign a species to genes/elements detected on the contigs. 

This part requires kraken2 (tested with v.2.0.8-beta), bracken2 (tested with v.2.6.0) and kronatools (tested with v.2.7.1) (as well as BBtools, used earlier). At the time of writing, **kraken2, bracken2, kronatools and BBtools are not global apps on Gadi** so please self-install and make "module loadable" or update the scripts to use your local installation. 


#### 4.1 Build the Kraken2 database

The included script builds the 'standard' database, which includes NCBI taxonomic information and all RefSeq complete genomes for bacteria, archaea, virus, as well as human and some known vectors. Given the memory capacity of Gadi, the use of 'MiniKraken' database is not recommended. 

Since the NCBI RefSeq collection is constantly updated, the build date is included in the database name. 

The database will be created in `./kraken2_standard_db_build_<date>`. Please ensure you have ample disk space (~ 150 GB required at the time of writing). Change the path to specify a different database location if desired.   

Ensure your `module load kraken2` command works before running the below script: 
```
qsub ./Scripts/kraken2_build_db.pbs
```


#### 4.2 Speciation 

This step uses the above database to identify which species each of the target reads ("reads" step) or filtered contigs ("contigs" step) likely belongs to. Because many bacteria contain identical or highly similar sequences, reads cannot always be assigned to the level of species - in such cases, kraken2 assigns the read to the lowest common ancestor of all species that share that sequence.

Kraken2 does multithread, however benchmarking on Gadi revealed the threading was very inefficient (eg E < 10% for 24 CPU per task on normal queue). However, each task requires more RAM than can be provided by a single CPU, so more than 1 CPU per task must be assigned in order to avoid task failures due to insufficient memory. The 'memory mapping' parameter of kraken2 is not recommended here - it uses less memory, however is vastly slower (by AT LEAST 20 times).

For the 'standard' database created in the step above, a minimum of ~ 60 GB is required - this can be achieved with 2 x `hugemem` queue CPUs per sample, 16 x `normal` queue CPUs per sample, or 7 x `normalbw` queue (256 GB nodes) CPUs per sample. The `hugemem` queue yields the optimal CPU efficiency (~87%) however if the other queues have more availability at the time of job submission, setting up for the less utilised queues is preferable. 

Kraken2 is fast - walltimes on the above tested CPU/queue values were < 15 minutes for samples with ~6 GB input target gzipped fastq. 

##### 4.2.1 Speciation (reads)

Target reads have been output as interleaved, for compatibility with humann2 (functional profiling step). Reformat the reads into paired with BBtools for compatibility with kraken2: 

Make inputs (a sample list, sorted by sample input fastq largest to smallest to aid improved parallel efficiency):
```
bash ./Scripts/deinterleave_target_reads_make_input.sh
```

The following script uses BBtools to reformat the interleaved reads to paired and pigz to gzip the output. The reformat step does not multithread but the pigz compression step does, and is the slower part. A sample with 2 pairs of fastq totalling ~ 6 GB takes ~12 minutes and 16 GB RAM on 4 'normal' CPUs and ~ 9 minutes and 18 GB  RAM on 6 CPUs. The output will be sent to `Target_reads_paired`. For samples with multiple lanes of fastq, they retain multiple lanes of fastq (ie, we do not concatenate them). Kraken2 can accept multiple pairs of fastq as input by listing them concurrently. All fastq files containing the ID used in column 1 of the sample config file will be collected into a list as total input for that sample, so if you haven't done so by now, please check that these IDs are unique among the samples and among the fastq file names. 

Edit the resource directives, then submit:
```
qsub ./Scripts/deinterleave_target_reads_run_parallel.pbs
```

There is no need to make a new inputs file for kraken2, as the same size-sorted list used in the above deinterlave step will be used.  

Edit the script `./Scripts/speciation_reads.sh` to the name of your database created at step 4.1. 


Adjust the resources, noting the RAM and CPU examples described above. Request all of the jobfs for the whole nodes you are using. Then submit:
```
qsub ./Scripts/speciation_reads_run_parallel.pbs
```

Output will be in the `Speciation_reads` directory, with per-sample directories containing Kraken2 output, report, and Krona plot html file that can be viewed interactively in a web browser.  

##### 4.2.2 Speciation (contigs)

The inputs file sorts the samples in order of their asembly size, largest to smallest. This is to increase parallel job efficiency, if the number of consecutively running tasks is less than the total number of tasks. 

```
bash speciation_contigs_make_input.sh
```

Edit the script `./Scripts/speciation_reads.sh` to the name of your database created at step 4.1.

Adjust the resources, noting the RAM and CPU notes described above. Request all of the jobfs for the whole nodes you are using. Then submit:
```
qsub ./Scripts/speciation_contigs_run_parallel.pbs
```

Output will be in the `Speciation_contigs` directory, with per-sample directories containing Kraken2 output, report, and Krona plot html file that can be viewed interactively in a web browser.  


##### 4.2.3 Collate speciation output

Format Kraken2 output into one file for all samples in cohort. 

The below script creates a single TSV file of the Kraken2 output for all samples in the cohort. It collects column 1 ("Percentage of fragments covered by the clade rooted at this taxon") and column 6 (scientific name). Column headings are sample IDs and row headings are scientific names. The sample ID in column 2 of the config is used to name the samples. Collating the Kraken2 output in this way makes downstream customised analysis and interrogation more straightforward. 

The script can collate Kraken2 output from either reads or contigs analysis, by parsing these as variable names on the command line.

Collate Kraken2 'reads' output:

```
perl ./Scripts/collate_speciation.pl reads
```

Collate Kraken2 'contigs' output:

```
perl ./Scripts/collate_speciation.pl contigs
```
The output will be an 'allSample.txt' file within the Speciation_reads or Speciation_contigs directory. 

If the cohort has groups (eg treatment groups or timepoints) and these are specified in column 5 of the sample config file, the below script can be run to additionally create a per-group TSV of the Kraken2 output. Provide the name of the collated output file as the first and only command line argument:


Collate Kraken2 'reads' output into per-group files:
```
perl ./Scripts/collate_speciation_or_abundance_with_groups.pl ./Speciation_reads/Kraken2_reads_allSamples.txt
```

Collate Kraken2 'contigs' output into per-group files:

```
perl ./Scripts/collate_speciation_or_abundance_with_groups.pl ./Speciation_contigs/Kraken2_contigs_allSamples.txt
```
The output will be a per-group collated Kraken2 TSV file within the `./Speciation_reads` or `./Speciation_contigs` directory.



#### 4.3 Abundance

Abundance estimation generates a profile of the microbiota per patient. Since the number of reads classified to species level is far lower than the total reads, Kraken2 cannot indicate the abundance of species in the sample. Bracken2 probabilistically redistributes reads in the taxonomic tree as classified by Kraken2, so make sure to run Kraken2 step first. 
Bracken2 uses Bayes theorem to redistribute reads that have not been assigned to the level of species by Kraken2. Reads assigned above the level of species are distributed down to species, and reads below the level of species (eg strain level) are distributed up to species. 


##### 4.3.1 Generate the Bracken2 database

Update the script `bracken_db_build.pbs` with the name and path of your Kraken2 database created at step 4.1. 

The following Bracken2 parameters are set by default in the script - please update these to values better suited to your data if required:
```
KMER_LEN=35
READ_LEN=150
```

Ensure your `module load` commands work before running the below script:

```
qsub ./Sripts/bracken_db_build.pbs
```

##### 4.3.2 Abundance (reads)

Compute species abundance estimates using target reads as input with Bracken2. This step is very fast (~ 2 seconds per sample with 'standard' database and ~ 6 GB traget fastq.gz) so abundance is computed per sample in series rather than in parallel.

The following Bracken2 parameters are set by default in the script - please update these to values better suited to your data if required:

```
KMER_LEN=35
READ_LEN=150
CLASSIFICATION_LVL=S 
THRESHOLD=10 
```

Update the script  with the name and path of your Kraken2 database created at step 4.1, ajust the walltime depending on your number of samples, then submit:

```
qsub ./Scripts/bracken_est_abundance.pbs
```


##### 4.3.3 Abundance (contigs)

Note the tool was written to estimate abundance using read data not contig data; however depending on the nature of your research project, estimating the abundance based on assembled contigs may be meaningful.

There is no separate script for this step, so either copy the script and `sed` the copy, or `sed` the original script to run the analysis on Kraken2 contig data:

```
sed -i 's/reads/contigs/g' ./Scripts/bracken_est_abundance.pbs
qsub ./Scripts/bracken_est_abundance.pbs
```

##### 4.3.4 Collate abundance output

Format Bracken2 output into one file for all samples in cohort.

The below script creates a single TSV file of the Bracken2 output for all samples in the cohort. It collects column 1 (scientific name) and column 7 (fraction total reads). Column headings are sample IDs and row headings are scientific names. The sample ID in column 2 of the config is used to name the samples. Collating the Bracken2 output in this way makes downstream customised analysis and interrogation more straightforward. 

The script can collate Bracken2 output from either reads or contigs analysis, by parsing these as variable names on the command line.

Collate Bracken2 'reads' output:

```
perl ./Scripts/collate_abundance.pl reads
```

Collate Braken2 'contigs' output:

```
perl ./Scripts/collate_abundance.pl contigs
```

The output will be an 'allSample.txt' file within the `./Abundance_reads` or `./Abundance_contigs` directory. 


If the cohort has groups (eg treatment groups or timepoints) and these are specified in column 5 of the sample config file, the below script can be run to additionally create a per-group TSV of the Bracken2 output. Provide the name of the collated output file as the first and only command line argument:


Collate Bracken2 'reads' output into per-group files:
```
perl ./Scripts/collate_speciation_or_abundance_with_groups.pl ./Abundance_reads/Bracken2_reads_allSamples.txt
```

Collate Bracken2 'contigs' output into per-group files:

```
perl ./Scripts/collate_speciation_or_abundance_with_groups.pl ./Abundance_contigs/Bracken2_contigs_allSamples.txt
```
The output will be a per-group collated Bracken2 TSV file within the `Abundance_reads` or `Abundance_contigs` directory.

### Part 5. Functional profiling
Profile the presence/absence and abundance of microbial pathways in the metagenomes using HUMAnN 2 and metaphlan2. 

HUManN2 has extremely variable run times that cannot be predicted by eg data size, so samples are run via a loop rather than using parallel mode. Working space utilises `jobfs` (up to 300 GB per ~ 6 GB sample during testing) and copies the key output files to `<workdir>/Functional_profiling` before the job ends. Humann2 does not consider pairing information for paired read data, and accepts only one input file, so interleaved or concatenated paired input is required. For samples with >1 fastq file input, the script will concatenate the temp input data using jobfs.  

Humann2 does have a `resume` flag, however this necessitates that temp files are not written to jobfs, which is wiped upon job completion. If you encounter a sample that dies on walltime very much longer than the other samples, it may be worth resubmitting that sample without utilising jobfs (by editing the script to write to workdir rather than jobfs) so that resume can be utilised for potential further failed runs.


#### 5.1 Software and database setup
 
HUMAnN 2 and metaphlan2 are not global apps on Gadi, so please install these and make them 'module load-able'. 

Then [download the Chocophlan and Uniref90 databases](https://github.com/biobakery/humann/tree/2.9#5-download-the-databases) into the `<path>/humann2/<version>` directory.

First, check that your module load commands work:

```
module load metaphlan2/2.7.8 
module load humann2/2.8.2
```

If these commands do not function, check your install and module setup.

Humann2 expects python3 to be within its `bin` directory. Check, and if not present, run the following from within the humann2 `bin` directory:

```
ln -s /apps/python3/3.7.4/bin/python3 python3
```

Run the following commands (update the value of `<path>`), which changes the shebang line from `#!/usr/bin/env python` to `#!/usr/bin/env python3`:

```
for file in <path>/humann2/2.8.2/bin/*; do sed -i '/python/c\#!/usr/bin/env python3' $file; done
for file in <path>/metaphlan2/2.7.8/utils/*; do sed -i '/python/c\#!/usr/bin/env python3' $file; done
```

Run the below to verify that humann2 is working correctly:

```
humann2 -v
```

If these commands do not function, check your install and module setup. 

Finally, check that your databases are in the location expected by `functional_profiling.pbs`: 

```
base=$(which humann2)
uniref=${base/%bin\/humann2/uniref90_diamond}
choco=${base/%bin\/humann2/chocophlan}
du -hs $uniref
du -hs $choco
```

#### 5.2 Run functional profiling

Once the modules and databases have been checked and any issues rectified, submit the serial per-sample PBS jobs using the loop script:

``` 
bash ./Scripts/functional_profiling_run_loop.sh
```

Output will be in per-sample directories within `./Functional_profiling`, with humann2 and PBS logs written to `./Logs/humann2`.


### Part 6. Antimicrobial resistance genes

This step annotates putative antimicrobial resistance genes (ARGs) on to the filtered contigs using Abricate tool with the following databases:
* [NCBI AMRFinder Plus](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6811410)
* [Resfinder](https://www.ncbi.nlm.nih.gov/pubmed/22782487) 
* [Comprehensive Antibiotic Resistance Database (CARD)](https://www.ncbi.nlm.nih.gov/pubmed/27789705)

ARGs are reformatted, reads mapping to the ARGs are counted and normalised, and the final output produced is ARGs with read count and species data formulated as a comprehensive TSV for downstream investigation and bespoke analysis. The final output makes use of a manually curated ARG list (`./workdir/Inputs/curated_ARGs_list.txt`) which is used to assign all genes with multiple synonyms to one unified gene name. 


#### 6.1 Annotate ARGs 
There is no need to create an inputs file as the inputs sample list from the assembly step will be used. Samples with ~ 6 GB input gzipped fastq should complete in less than 20 minutes using 4 CPU per sample. 

You will ned to install abricate and make 'module loadable'. Tested with version 0.9.9.

Update the resources in the below script, then submit:

```
qsub ./Scripts/annotate_ARGs_run_parallel.pbs
```

Output will be in per-sample directories within `./workdir/ARGs/Abricate`. Each sample will have a `.tab` file containing genes identified from the NCBI, Resfinder and CARD databases. The following steps will manipulate these raw outputs.

 
#### 6.2 Reformat ARGs

This step combines the output of the 3 databases into one file per sample, removing any exact duplicate gene entries, and one file per cohort. This cohort-level file should be used to create a curated gene list at the next step.  

```
bash reformat_ARGs_remove_dups.sh
```

The output is one additional file in each of the sample directories within `./workdir/ARGs/Abricate`, named `<sample>.ARGs.txt`, as well as a coort-level file `./workdir/ARGs/Abricate/<cohort>.ARGs.txt` that should be used to curate a gene list (see 5.3).  


#### 6.3 Curated ARG list

This is a mandatory input file consisting of at least 4 tab-delimited columns. The mandatory columns are, in order:


| Column | Heading                   | Description                                                            | 
|--------|---------------------------|------------------------------------------------------------------------|
| 1      |  Curated_gene_name        | The name that will be used to describe all gene synonyms for this gene | 
| 2      |  Resistance_Mechanism     | Mechanism of antibiotic resistance                                     | 
| 3      |  Drug_Class               | Class of drugs the gene confers resistance to                          | 
| 4      |  Gene_names_variation     | Gene name variant / synonym for this gene                              |  

Column 4 contains a variant name for the gene listed in column 1. If there are no synonyms, the name of the gene in column 1 is listed. Genes with multiple synonyms can have as many columns as required, starting from column 5. 

A curated list generated from processing 572 samples has been provided with this repository. Please note that alternate datasets will generate different gene lists, and a manual curation step should be performed using the output from step 5.2 (file `./workdir/ARGs/Abricate/<cohort>.ARGs.txt`). 

Please ensure that the column orders match the above described requirement to ensure that all gene synonyms are incorporated. Loss of a column = loss of gene counts!


#### 6.4 Count reads mapping to ARGs

Counting the number of reads mapping to the ARGs provides insight into the abundance of ARGs in the microbiome.  

##### 6.4.1 Mark duplicate reads in the previously created BAM files

Mark dulicate reads in the BAM files created during step 3.2, to improve accuracy of ARG read counting. 

For samples with ~ 6 GB input gzipped fastq, a minimum of 2 hugemem CPUs worth of RAM per sample are required for RAM. MarkDuplicates tool is assigned 30 GB RAM per CPU assigned to a task within the `markdups.sh` script, ie this script is written for the hugemem nodes which have 32 GB RAM per CPU. If using on different queue, please update the value of '30' within the `mem` variable assignment.  You can increase the number of CPUs per task to make better use of the memory on the nodes depending on your number of samples, eg if you have 10 samples, use 4 CPU per task rather than 2 as set as the default for the script. This will improve the walltime and RAM efficiency, but not the CPU efficiency, as MarkDuplicates does not multithread. Samples with ~ 6 GB input gzipped fastq using 3 hugemem CPU worth of RAM should complete in under 1 hour. 

There is no need to create an inputs file as the inputs sample list from the assembly step will be used.

Update the resources as discussed above, then submit:

```
qsub ./Scripts/markdups_run_parallel.pbs
```

Output will be a duplicate-marked BAM in the previously created `./workdir/Align_to_assembly` per-sample directories.  


##### 6.4.2 Convert Abricate ARG output to GFF

Convert abricate 'tab' output format to gene feature format (GFF) for compatibility with htseq-count. During the conversion to GFF, the curated ARG list is read, so that the GFF contains only one entry per gene with multiple synonyms per contig location. Ie if a gene is annotated at multiple locations in the assembly, each discrete location will be kept, assigning the chosen gene name to all discrete location entries. If a gene is annotated to one location of the assembly with multiple different gene symbols, only one entry will be kept, using the gene name specified as default in the curated list. 

```
perl ./Scripts/convert_ARG_to_gff.pl
```

The output will be per-sample GFF files in `./workdir/ARGs/Curated_GFF`, with only the curated entries as described above present in the GFF files. 


##### 6.4.3 Count reads mapping to ARGs with HTseq count

This step uses HTSeq-count to count reads that map to the putative curared ARG locations. Before running, you will need to install HTSeq-count:

```
module load python3/3.8.5
pip install HTSeq
```

The counting options applied in `ARG_read_count.sh` are:
```
--stranded no 
--minaqual 20 
--mode union 
--nonunique none 
--secondary-alignments ignore 
--supplementary-alignments score 
```

HTseq-count does not multithread and is fairly slow. Future releases will improve the parallelism here, but for now, allow 3 hours per sample on 1 Broadwell CPU, based on samples with ~ 6 GB input fastq.gz. Update the resources then submit:

```
qsub ./Scripts/ARG_read_count_run_parallel.pbs
```
The output will be per-sample counts files in ./ARGs/ARG_read_counts.


##### 6.4.4 Normalise

##### 6.4.4.1 Reformat the ARG read count data for easy parsing 

This will convert the HTseq-count output into a 3-column text file per sample (ID, gene length, raw count), with the ID field containing the gene name, contig ID, start and end positions concatenated with a colon delimiter. 

It will also check that the ARGs counted matches the number of ARGs in the the input GFF, printing a fatal error if a mismatch is found. 

```
bash reformat_ARG_read_counts.sh
```

Output files are `./ARGs/ARG_read_counts/<sample>.curated_ARGs.reformat.counts` and are used as input to the normalisation step. 

##### 6.4.4.2

Normalise the ARG read count data with transcript per million (TPM) and reads per kilobase million (RPKM).

```
perl normalise_ARG_read_counts.pl
```

Output is `./ARGs/ARG_read_counts/<sample>.curated_ARGs.counts.norm` per sample as well as `./ARGs/ARG_read_counts/<cohort>_allSamples.curated_ARGs.counts.norm` containing all samples in cohort. 

If the cohort has groups (eg treatment groups or timepoints) and these are specified in column 5 of the sample config file, the below script can be run to additionally create a per-group output. Note that 'allSamples' in the cohort-level file name will be replaced by the group name in the output:

```
perl collate_normalised_ARG_read_counts_by_groups.pl
```

Output will be a separate normalised counts file for every group, `./ARGs/ARG_read_counts/<cohort>_<group>.curated_ARGs.counts.norm`.

##### 6.4.5 Assign species to normalised ARG data

For every curated ARG, find the contig that that gene resides on and print out new TSV with gene, species, contig, number of reads mapping to that contig as well as normalised count data. 
 
```
perl reformat_norm_ARG_with_species.pl
```
 
Output will be `./ARGs/Curated_ARGs/<sample>.curated_ARGs.txt` for each sample, and a cohort level file `./ARGs/Curated_ARGs/<cohort>_allSamples.curated_ARGs.txt`.
  
If the cohort has groups (eg treatment groups or timepoints) and these are specified in column 5 of the sample config file, the below script can be run to additionally create a per-group output. Note that 'allSamples' in the cohort-level file name will be replaced by the group name in the output:

```
perl reformat_norm_ARG_with_species_by_groups.pl
```

Output will be a separate TSV file for every group, `./ARGs/Curated_ARGs/<cohort>_<group>.curated_ARGs.txt`.


##### 6.4.6 Descriptive statistics  

Print descriptive stats of curated-ARG-containing contigs. 

```
perl ARG_contig_length_stats.pl
```
Output is a single file for all samples in cohort, containing the count, mean, standard deviation, min and max lengths for all contigs and for ARG-containing contigs, `./ARGs/Curated_ARGs/<cohort>_allSamples_curated_ARGs_contig_length_stats.txt`. 

##### 6.4.7 Filter ARGs by coverage and identity

For each curarted ARG, filter by >=70% coverage and >=80% identity. To change these thresholds, please edit the variable assignments for `$cover` and `$identity` within the below perl script.


Reports a separate R-compatible dataframe for TPM normalised and raw counts. Column headings are gene names and row headings are sample IDs. 


```
perl filter_ARGs_by_coverage_and_identity.pl

```
Outputs are `./ARGs/Curated_ARGs/<cohort>_allSamples_curated_ARGs_rawCount_Rdataframe.txt` and `./ARGs/Curated_ARGs/$cohort\_allSamples_curated_ARGs_TPM_Rdataframe.txt`. 

  
If the cohort has groups (eg treatment groups or timepoints) and these are specified in column 5 of the sample config file, the below script can be run to additionally create a per-group output. Note that 'allSamples' in the cohort-level file name will be replaced by the group name in the output:

```
perl filter_ARGs_by_coverage_and_identity_by_groups.pl
```

Output will be a separate R-compatible dataframe for TPM normalised and raw counts per group, also within the `./ARGs/Curated_ARGs` directory. 


### Part 7. Gene prediction

#### 7.1 Predict coding sequences

Predict coding sequences within the filtered contigs using Prodigal

#### 7.2 Annotate genes

Annotate gene names to coding sequences using NCBI NR database and Diamond


### Part 8. Resistome calculation

#### 8.1 Correspond ARGs to gene annotations

#### 8.2 Calculate resistome

Calculate resistome


### Part 9. Insertion seqeunce (IS) elements
This step annotates putative insertion sequence elements on the filtered assemblies using [Prokka annotation tool](https://github.com/tseemann/prokka) and [ISfinder sequence database](https://github.com/thanhleviet/ISfinder-sequences).

#### 9.1 Download the IS database

First, download the ISfinder database to your workdir:
```
git clone https://github.com/thanhleviet/ISfinder-sequences.git
```

At the time of writing, Prokka is not a global app on Gadi so please install and test. Run `prokka --depends` to ensure you have all dependencies. During testing, we found two required perl modules not globally installed (XML::Simple and bioperl) so if you are using a self-install Prokka app, ensure to also install these Perl modules and add them to the path in the '.base' module load file. 

You may also need to manually update the `tbl2asn` file, which NCBI has set to expire. See [known issue](https://github.com/tseemann/prokka/issues/139) for discussion and solution. 

#### 9.2 Annotate IS on filtered contigs 

Prokka multithreads but the CPU efficiency is low when all samples are run in a parallel job (7-13% during testing at 12-24 CPU per task). Walltimes can be unpredictably long - up to 11 hours for ~ 6 GB input fastq.gz samples. This is because Prokka was not designed to annotate large metagenomes. To increase overall efficiency, a serial submission loop is utilised rather than the parallel mode.  

Submit all samples with:
 
``` 
bash IS_annotation_run_loop.sh
```

Output will be Prokka annotation files in per-sample directories within `./Insertion_sequences` with PBS logs written to `./Logs/IS`.

The following scripts will annotate the putative IS seqeunces with contig ID and species, filtering for only the passenger or transposase genes from the Prokka GFF file.

Create new per-sample and per-cohort output with contig and species: 

```
perl collate_IS_annotation_with_species.pl
```

If the cohort has groups (eg treatment groups or timepoints) and these are specified in column 5 of the sample config file, the below script can be run to additionally create a per-group TSV of the IS annotation with species output:

```
perl collate_IS_annotation_with_species_by_groups.pl
```

Output will be TSV files in `./Insertion_sequences/Filtered_IS_with_species`, per sample, per cohort, and per group if relevant. 




### Software used
* [abricate/0.9.9](https://github.com/tseemann/abricate)
* [bbtools/37.98](https://jgi.doe.gov/data-and-tools/software-tools/bbtools/)
* [bracken/2.6.0](https://github.com/jenniferlu717/Bracken)
* [bwa/0.7.17](https://github.com/lh3/bwa) 
* [fastqc/0.11.7](https://github.com/s-andrews/FastQC)
* [gatk/4.1.5.0](https://github.com/broadinstitute/gatk)
* [humann2/2.8.2](https://github.com/biobakery/humann)
* [kraken2/2.0.8-beta](https://github.com/DerrickWood/kraken2)
* [kronatools/2.7.1](https://github.com/marbl/Krona)
* [megahit/1.2.8](https://github.com/voutcn/megahit)
* [metaphlan2/2.7.8](https://github.com/biobakery/MetaPhlAn2)
* [multiqc/1.9](https://github.com/ewels/MultiQC)
* [nci-parallel/1.0.0a](https://opus.nci.org.au/display/Help/nci-parallel)
* [openmpi/4.1.0](https://github.com/open-mpi)
* [prokka/1.14.6](https://github.com/tseemann/prokka)
* [python3](https://github.com/python/cpython)
* [sambamba/0.7.0](https://github.com/biod/sambamba)
* [samtools/1.10](https://github.com/samtools/samtools)
* [seqtk/1.3](https://github.com/lh3/seqtk)




 
 
 
 
 
 
 
======= 

## Cite us to support us!

Willet, C.E., Martinez, E., Sukumar, S., Alder, C., Lydecker, H., Wang, F., Chew, T., & Sadsad, R. Shotgun-Metagenomics-Analysis (Version 1.0) [Computer software]. https://doi.org/10.48546/workflowhub.workflow.327.1
>>>>>>> 6a80c0ccaa37868ba8638a9998cc833f406a0e9c
