#! /usr/bin/perl

#Copyright (C) 2022 Feiyu Du <fdu@genome.wustl.edu>
#              and Washington University The Genome Institute

#This script is distributed in the hope that it will be useful, 
#but WITHOUT ANY WARRANTY or the implied warranty of 
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
#GNU General Public License for more details.


use strict;
use warnings;

umask 002;

use JSON;
use IO::File;
use List::Util qw(first);

die "Provide myeloseq output dir" unless @ARGV and @ARGV == 1;
my $dir = $ARGV[0];

unless (-d $dir) {
    die "myeloseq output dir: $dir not existing";
}

my %group1 = (
    TOTAL_BASES   => 'MAPPING/ALIGNING SUMMARY: Total bases',
    TOTAL_READS   => 'MAPPING/ALIGNING SUMMARY: Total input reads',
    MISMATCH_RATE_1    => 'MAPPING/ALIGNING SUMMARY: Mismatched bases R1 (%)',
    MISMATCH_RATE_2    => 'MAPPING/ALIGNING SUMMARY: Mismatched bases R2 (%)',
    PCT_MAPPED_READS   => 'MAPPING/ALIGNING SUMMARY: Mapped reads (%)',
    MEAN_INSERT_SIZE   => 'MAPPING/ALIGNING SUMMARY: Insert length: mean',
    PCT_TARGET_ALIGNED_READS  => 'COVERAGE SUMMARY: Aligned reads in target region (%)',
    AVG_ALIGN_TARGET_COVERAGE => 'COVERAGE SUMMARY: Average alignment coverage over target region',
    PCT_UMI_DUPLICATE_READS   => 'UMI SUMMARY: Duplicate reads (%)',
);

my @headers = ('Case', (sort keys %group1));

my $out_file = $dir.'/QC_metrics.tsv';
my $out_fh = IO::File->new(">$out_file") or die "Failed to write to $out_file";
$out_fh->print(join "\t", @headers);
$out_fh->print("\n");

opendir(my $dir_h, $dir);

for my $case_name (readdir $dir_h) {
    next if $case_name =~ /^(\.|cromwell|dragen|demux|old|test|hugh)/;
    my $lib_dir = $dir .'/'.$case_name;
    next unless -d $lib_dir;

    my ($case_id) = $case_name =~ /^(\S+lib\d+)/;
    my $qc_json_file = $lib_dir."/$case_id.report.json";

    my $json_text = do {
        open(my $json_fh, "<:encoding(UTF-8)", $qc_json_file) or die "fail to open $qc_json_file for $case_name";
        local $/;
        <$json_fh>
    };

    my $json = JSON->new;
    my $data = $json->decode($json_text);

    my @values = ($case_id);

    for my $metric1 (sort keys %group1) {
        my $json_key = $group1{$metric1};
        my ($up_json_key) = $json_key =~ /^(\S+\sSUMMARY):\s/;
        my $value = $data->{QC}->{$up_json_key}->{$json_key};
        if ($metric1 eq 'PCT_LOW_COVERAGE_AMPLICON') {
            $value = sprintf("%.2f", $value); 
        }
        push @values, $value;
    }
 
    $out_fh->print(join "\t", @values);
    $out_fh->print("\n");
    print "$case_id done\n";
}

closedir $dir_h;
