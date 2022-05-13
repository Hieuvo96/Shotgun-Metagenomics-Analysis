#!/usr/bin/env perl

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

use warnings;
use strict;

my $cohort = '<cohort>';
my $config = "./Inputs/$cohort\.config";

my $indir = './Insertion_sequences/Filtered_IS_with_species';
my $input = "$indir\/IS_$cohort\_allSamples.txt";

# Collect samples by group IDs
my $grouphash = {};
my @groups = '';
open (S, $config) || die "$! $config\n"; 
chomp (my $header = <S>);
while (my $line = <S>) {
	chomp $line; 
	my ($id, $sample, $platform, $centre, $group) = split(' ', $line); 
	if (!$grouphash->{$group}) {
		push @groups, $group; 	
	}
	$grouphash->{$group}->{$sample} = 1; 
} close S; 

# Print per-group output files
foreach my $group (sort keys %{$grouphash}) {
	print "Printing per-group output for group $group ";
	my $group_cat = '';
	foreach my $sample (sort keys %{$grouphash->{$group}}) {
		$group_cat .= " $indir\/$sample\.IS.txt";
	}
	my $group_out = $input;
	$group_out =~ s/allSamples/$group/; 
	print "to $group_out\n"; 	
	open (T, ">$group_out") || die "$! write $group_out\n"; 	
	print T "#Sample\tContig\tSpecies\tStart\tEnd\tName\tInference\tProduct\n"; 
	close T; 
	`cat $group_cat | sed '/^\#/d' | sort | uniq >> $group_out`;
}	
