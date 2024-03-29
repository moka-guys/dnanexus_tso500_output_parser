# tso500_output_parser_v1.2.1

## What does this app do?
This app takes a jobid from the TSO500 docker app and sets off additional dx run commands including fastqc, coverage calculations, sompy (for HD200 commercial control samples) and multiqc.

## What are typical use cases for this app?
This app runs after the the applet TSO500_v1.3+. It is used to set off QC steps for specific files output by this job using existing applets (which are set up to process one file at a time)

## What inputs are required for this app to run?
* project_name - human readable DNANexus project name (eg 002_YYMMDD...) in which to set off the dx run commands
* project_id - stable project id (eg project-abc123) in which to set off the dx run commands
* tso500_jobid - the jobid running the TSO500 applet (in the format job-123)
* coverage_bedfile_id - the id of the BED file used for coverage project-abc:file123
* coverage_app_id - the id of the coverage app used in format project-abc:applet123
* fastqc_app_id - the id of the fastqc app used in format project-abc:applet123
* sompy_app_id - the id of the sompy app used in format project-abc:applet123
* multiqc_app_id - the id of the multiqc app used in format project-abc:applet123
* upload_multiqc_app_id - the id of the upload_multiqc app used in format project-abc:applet123
* coverage_commands - any extra commands for coverage (eg -iadditional_sambamba_flags and -iadditional_filter_commands)
* coverage_level - the required read depth to be used for the coverage calculation (string)
* multiqc_coverage_level - the required read depth to be used in multiQC (string)

## How does this app work?
The app takes the job id from the TSO500 applet and parses the `fastqs`, `bams_for_coverage` and `results_vcfs` outputs.
dx describe functions are called on each output and used to extract the fileids and build dx run commands.

The fastqc app is run for each fastq.gz file in the output and the jobid from the resulting job captured.

The sambamba_chanjo coverage app is run for each pair of bam/bai files in the bams_for_coverage output.

The sompy app is run for an sample with "HD200" in the sample name, comparing it with the HD200 known variants to generate recall statistics.

The "MergedSmallVariants.genome.vcf" is zipped with bgzip and indexed with tabix. These files are saved in the sample folder in analysis_folder/Results. Indexing the vcf allows it to be viewed in the igv web app.

Finally a dx run command for MultiQC is built, as the fastqc jobids used in the --depends-on flag to delay the start until all fastqc jobs have finished sucessfully.

These commands are built using arguments and inputs provided to this app.

All dx run commands are written to a logfile.

The environment variables within the worker are reset to ensure the jobs and outputs run in the given project.

## What does this app output
The logfiles output contains two files:
`$project_name.output_parser.log` - A logfile detailing the files processed
`$project_name.dx_run_cmds.sh` - all dx run commands

These are output to /logfiles

## This app was made by Viapath Genome Informatics
