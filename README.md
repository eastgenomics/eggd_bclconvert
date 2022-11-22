# eggd_bclconvert
DNAnexus app of bclconvert v4.0.3

## What does this app do?
Runs bcl-convert to demultiplex sequencing data uploaded from an Illumina sequencer

## What are typical use cases for this app?
This app may be executed as a standalone app or as part of an analysis pipeline.
Used as the first step when sequencing data is streamed from the sequencer to DNAnexus before bioinformatics analysis can begin.

The default instance (`mem2_ssd1_v2_x32`) has 32 cores, 125GB RAM and 1116GB of storage.
For large flowcells it may be necessary to use a larger instance with more storage (such as `mem3_ssd2_v2_x32`).

## What data are required for this app to run?
This app requires
* SampleSheet.csv (included in the run data, associated to the sentinel file or provided with `-isample_sheet`)
* upload sentinel record OR array of tar.gz containing the output packets from the sequencer

Optional input parameters:
* advanced options for running bcl-convert

## What does this app output?
* uploads all data from the sequencer (except for bcl files)
* all files in `Logs/` are uploaded to a single tar (`Logs.tar.gz`)
* all files in `InterOp/` are uploaded to a single tar (`InterOp.tar.gz`)
* uploads all output files from bcl-convert (written to `Output/`)

## Dependencies
The app depends on the bcl-convert asset built to DNAnexus.

### This app was made by East GLH