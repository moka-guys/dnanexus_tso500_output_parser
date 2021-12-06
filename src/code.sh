#!/bin/bash
# The following line causes bash to exit at any point if there is any error
# and to output each line as it is executed -- useful for debugging
set -e -x -o pipefail

# make output folder
mkdir -p /home/dnanexus/out/logfiles/logfiles/

# Store the API key. Grants the script access to DNAnexus resources    
API_KEY=$(dx cat project-FQqXfYQ0Z0gqx7XG9Z2b4K43:mokaguys_nexus_auth_key)

# print the arguments to the app to the logfile
printf "projectname $project_name\nprojectid $project_id\ntso500_jobid $tso500_jobid\ncoverage_bedfile_id $coverage_bedfile_id\ncoverage_app_id $coverage_app_id\nfastqc_app_id $fastqc_app_id\nmultiqc_app_id $multiqc_app_id\n" >> /home/dnanexus/out/logfiles/logfiles/$project_name.output_parser.log

#Add a cautionary note to the dx_run_cmds.sh
printf "#note whilst these are the dx run commands used this script does not capture the jobids required to delay the multiqc app\n" >> /home/dnanexus/out/logfiles/logfiles/$project_name.dx_run_cmds.sh

# override app variables so the dx run commands can be run in the project
unset DX_WORKSPACE_ID
dx cd $DX_PROJECT_CONTEXT_ID:
source ~/.dnanexus_config/unsetenv
dx clearenv
dx login --noprojects --token $API_KEY
dx select $project_id

# set depends list variable - this delays the multiqc app from running
depends_list=''

#### set off fastqc jobs

# create a list of json descriptions of from the fastq outputs from the given job
# parse the output of dx describe and convert the json for each file into a compact json (collapsing the json onto one line) 
# filter the outputs so only return those with "fastq.gz" in the name.
fastq_outputs="$(dx describe --json --multi $tso500_jobid:fastqs | jq -c '.[]'  | grep fastq.gz)"

# loop through the fastq files produced by the app
for fastq in $fastq_outputs
    do 
        # for each input (a json) return the id field and filename
        fileid=$(jq -r '.id' <<< $fastq)
        filename=$(jq -r '.name' <<< $fastq)
        # build fastqc command using the provided appid
        fastqc_command="dx run $fastqc_app_id  --detach -y --brief --name=$filename -ireads=$project_id:$fileid --dest=$project_name:/ --auth-token $API_KEY" 
        # write cmd to file and to stdout
        echo $fastqc_command
        echo "jobid=($fastqc_command)" >> /home/dnanexus/out/logfiles/logfiles/$project_name.dx_run_cmds.sh
        #execute the command and capture jobid to delay multiqc
        jobid=$($fastqc_command)
        depends_list="${depends_list} -d ${jobid}"
    done 

### set of coverage jobs
# print a header into the logfile
printf "\nbams_for_coverage filtered for bam.bai\n" >> /home/dnanexus/out/logfiles/logfiles/$project_name.output_parser.log

# create a array of bam index names
# parse the dx describe output for all outputs in the bams_for_coverage output
# this includes bams, bam indexes, plus a range of stats and logs created when making the stiched-realigned files.
# collapse the jsob for each output into a single line, filter for bam indexes and return the file name
bai_array=$(dx describe --json --multi $tso500_jobid:bams_for_coverage | jq -c '.[]'  | grep .bam.bai | jq -r '.name')

# for rach bam index
for bai in $bai_array
    do 
        # repeat the dx describe step this time filtering for the bai filename, and returning the fileid for that file
        bai_id=$(dx describe --json --multi $tso500_jobid:bams_for_coverage | jq -c '.[]'  | grep $bai| jq -r '.id')
        # strip the extension from the bai filename to create the expected bam file name
        bamfile_name=$(echo $bai | sed 's/.bai//')
        # repeat dx describe command, and grep for the bamfile name to get the bamfile id, adding quotations to ensure we don't also return the bamindexes in grep
        bam_id=$(dx describe --json --multi $tso500_jobid:bams_for_coverage | jq -c '.[]'  | grep $bamfile_name\"| jq -r '.id')
        # record the filename and fileids for the bam and bam index
        printf "\nbamfile name: $bamfile_name bamindex name $bai bamid $bam_id bai_id $bai_id\n" >> /home/dnanexus/out/logfiles/logfiles/$project_name.output_parser.log
        # create dx run command, using the inputs
        dx_run_cmd="dx run $coverage_app_id --detach -y --brief --name=$bamfile_name -ibam_index=$bai_id -ibamfile=$bam_id -icoverage_level=$coverage_level -isambamba_bed=$coverage_bedfile_id $coverage_commands --dest=$project_id:/ --auth-token $API_KEY"
        # copy the dx run command to the dx_run_cmds.sh
        echo $dx_run_cmd >> /home/dnanexus/out/logfiles/logfiles/$project_name.dx_run_cmds.sh
        # run the command
        $dx_run_cmd
    done 

# create dx run command for multiqc - giving depends on list, echo it to file and execute
multiqc_cmd="dx run $multiqc_app_id --detach -y --brief $depends_list -iproject_for_multiqc=$project_name -icoverage_level=$multiqc_coverage_level --dest=$project_id:/ --auth-token $API_KEY" 
echo $multiqc_cmd >> /home/dnanexus/out/logfiles/logfiles/$project_name.dx_run_cmds.sh
jobid=$($multiqc_cmd)
# upload multiqc report
upload_multiqc_cmd="dx run $upload_multiqc_app_id -y  -imultiqc_html=$jobid:multiqc_report -imultiqc_data_input=$jobid:multiqc --project=$project_id --brief --auth-token $API_KEY" 
echo $upload_multiqc_cmd >> /home/dnanexus/out/logfiles/logfiles/$project_name.dx_run_cmds.sh
$upload_multiqc_cmd
# cat the dx run cmds so can be viewed in logfile in dnanexus
cat /home/dnanexus/out/logfiles/logfiles/$project_name.dx_run_cmds.sh

# upload all outputs
dx-upload-all-outputs --parallel
