#! /usr/bin/perl

#Copyright (C) 2021 Feiyu Du <fdu@wustl.edu>
#              and Washington University The Genome Institute

#This script is distributed in the hope that it will be useful, 
#but WITHOUT ANY WARRANTY or the implied warranty of 
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
#GNU General Public License for more details.


use strict;
use warnings;

umask 002;

use lib "/storage1/fs1/duncavagee/Active/SEQ/Chromoseq/process/perl5/lib/perl5";
use Spreadsheet::Read;
use JSON qw(from_json to_json);
use IO::File;
use File::Spec;

die "Provide rundir, excel sample spreadsheet, batch name in order" unless @ARGV == 3;

my ($rundir, $sample_sheet, $batch_name) = @ARGV;

die "$rundir is not valid" unless -d $rundir;
die "$sample_sheet is not valid" unless -s $sample_sheet;

my $dir = '/storage1/fs1/duncavagee/Active/SEQ/GatewaySeq/process/test';
#my $git_dir = File::Spec->join($dir, 'process', 'git', 'cle-gatewayseq');
my $git_dir = '/storage1/fs1/duncavagee/Active/SEQ/GatewaySeq/process/git/cle-gatewayseq';

my $conf = File::Spec->join($git_dir, 'application.conf');
my $wdl  = File::Spec->join($git_dir, 'Gatewayseq.wdl');
my $zip  = File::Spec->join($git_dir, 'imports.zip');
my $json_template = File::Spec->join($git_dir, 'Gatewayseq.json');

my $group  = '/cle/wdl/haloplex';
my $queue  = 'pathology';
my $docker = 'registry.gsc.wustl.edu/apipe-builder/genome_perl_environment:compute1-38';

my $user_group = 'compute-duncavagee';

my $out_dir = File::Spec->join($dir, $batch_name);
unless (-d $out_dir) {
    unless (mkdir $out_dir) {
        die "Failed to make directory $out_dir";
    }
}

#parse sample spreadsheet
my $data = Spreadsheet::Read->new($sample_sheet);
my $sheet = $data->sheet(1);

my $ds_str;
my $si_str;
my $seq_id = 2900000000;

my @cases_excluded;

for my $row ($sheet->rows()) {
    next if $row->[0] =~ /Run|Lane/i;
    unless ($row->[0] =~ /\d+/) {
        die "Lane number is expected, Check sample sheet spreadsheet";
    }
    my ($lane, $flowcell, $lib, $index, $exception) = @$row;

    $lib =~ s/\s+//g;
    my ($name) = $lib =~ /^(\S+)\-lib/;

    my ($index1, $index2) = $index =~ /([ATGC]{10})\-([ATGC]{10})/;
    my $fix_index2 = rev_comp($index2);
    
    $exception = 'NONE' unless $exception;
    
    $ds_str .= join ',', $lane, $lib, $lib, '', $index1, $fix_index2;
    $ds_str .= "\n";
    $si_str .= join "\t", $index1.'-'.$fix_index2, $lib, $seq_id, $flowcell, $lane, $lib, $name;
    $si_str .= "\n";

    $seq_id++;
}

## DRAGEN sample sheet
my $dragen_ss  = File::Spec->join($out_dir, 'demux_sample_sheet.csv'); 
my $ss_fh = IO::File->new(">$dragen_ss") or die "Fail to write to $dragen_ss";
$ss_fh->print("[Settings]\n");
$ss_fh->print("AdapterBehavior,trim\n");
$ss_fh->print("AdapterRead1,AGATCGGAAGAGCACACGTCTGAAC\n");
$ss_fh->print("AdapterRead2,AGATCGGAAGAGCGTCGTGTAGGGA\n");
$ss_fh->print("OverrideCycles,Y151;I10U9;I10;Y151\n");
$ss_fh->print("[Data]\n");
$ss_fh->print("Lane,Sample_ID,Sample_Name,Sample_Project,index,index2\n");
$ss_fh->print($ds_str);
$ss_fh->close;

## Sample Index
my $si = File::Spec->join($out_dir, 'sample_index');
my $si_fh = IO::File->new(">$si") or die "Fail to write to $si";
$si_fh->print($si_str);
$si_fh->close;

## Get RunInfoString
my $run_xml = File::Spec->join($rundir, 'RunParameters.xml');
unless (-s $run_xml) {
    die "RunParameters.xml $run_xml is not valid";
}
my $xml_fh = IO::File->new($run_xml) or die "Fail to open $run_xml";
my ($runid, $R1cycle, $R2cycle, $index1cycle, $index2cycle, $fcmode, $wftype, $instr, $side);

while (my $line = $xml_fh->getline) {
    if ($line =~ /<RunId>(\S+)<\/RunId>/) {
        $runid = $1;
    }
    elsif ($line =~ /<Read1NumberOfCycles>(\d+)<\/Read1NumberOfCycles>/) {
        $R1cycle = $1;
    }
    elsif ($line =~ /<Read2NumberOfCycles>(\d+)<\/Read2NumberOfCycles>/) {
        $R2cycle = $1;
    }
    elsif ($line =~ /<IndexRead1NumberOfCycles>(\d+)<\/IndexRead1NumberOfCycles>/) {
        $index1cycle = $1;
    }
    elsif ($line =~ /<IndexRead2NumberOfCycles>(\d+)<\/IndexRead2NumberOfCycles>/) {
        $index2cycle = $1;
    }
    elsif ($line =~ /<FlowCellMode>(\S+)<\/FlowCellMode>/) {
        $fcmode = $1;
    }
    elsif ($line =~ /<WorkflowType>(\S+)<\/WorkflowType>/) {
        $wftype = $1;
    }
    elsif ($line =~ /<InstrumentName>(\S+)<\/InstrumentName>/) {
        $instr = $1;
    }
    elsif ($line =~ /<Side>(\S+)<\/Side>/) {
        $side = $1;
    }
}
$xml_fh->close;

my $run_info_str = join ',', $runid, $instr, $side, $fcmode, $wftype, $R1cycle, $index1cycle, $index2cycle, $R2cycle; 

## Input JSON
my $inputs = from_json(`cat $json_template`);
$inputs->{'Gatewayseq.OutputDir'}        = $out_dir;
$inputs->{'Gatewayseq.IlluminaDir'}      = $rundir;
$inputs->{'Gatewayseq.SampleSheet'}      = $si;
$inputs->{'Gatewayseq.DemuxSampleSheet'} = $dragen_ss;
#$inputs->{'Gatewayseq.RunInfoString'}    = $run_info_str;

my $input_json = File::Spec->join($out_dir, 'Gatewayseq.json');
my $json_fh = IO::File->new(">$input_json") or die "fail to write to $input_json";

$json_fh->print(to_json($inputs, {canonical => 1, pretty => 1}));
$json_fh->close;

my $out_log = File::Spec->join($out_dir, 'out.log');
my $err_log = File::Spec->join($out_dir, 'err.log');

my $cmd = "bsub -g $group -G $user_group -oo $out_log -eo $err_log -q $queue -R \"select[mem>16000] rusage[mem=16000]\" -M 16000000 -a \"docker($docker)\" /usr/bin/java -Dconfig.file=$conf -jar /opt/cromwell.jar run -t wdl --imports $zip -i $input_json $wdl";

system $cmd;
#print $cmd."\n";

sub rev_comp {
    my $index = shift;
    my $revcomp = reverse $index;
    $revcomp =~ tr/ATGCatgc/TACGtacg/;

    return $revcomp;
}
