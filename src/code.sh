#!/bin/bash
# The following line causes bash to exit at any point if there is any error
# and to output each line as it is executed -- useful for debugging
set -e -x -o pipefail

# make output folder
mkdir -p /home/dnanexus/out/logfiles/logfiles/ /home/dnanexus/out/vcf_index/
vcf_index_output=/home/dnanexus/out/vcf_index

# Store the API key. Grants the script access to DNAnexus resources    
API_KEY=$(dx cat project-FQqXfYQ0Z0gqx7XG9Z2b4K43:mokaguys_nexus_auth_key)

# print the arguments to the app to the logfile
printf "projectname $project_name\nprojectid $project_id\ntso500_jobid $tso500_jobid\ncoverage_bedfile_id $coverage_bedfile_id\ncoverage_app_id $coverage_app_id\nfastqc_app_id $fastqc_app_id\nsompy_app_id $sompy_app_id\nmultiqc_app_id $multiqc_app_id\n" >> /home/dnanexus/out/logfiles/logfiles/$project_name.output_parser.log

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
        # get the pannumber
        pannumber=$(echo $bamfile_name | grep -o -E "Pan[0-9]{1,5}")
        # record the filename and fileids for the bam and bam index
        printf "\nbamfile name: $bamfile_name bamindex name $bai bamid $bam_id bai_id $bai_id\n" >> /home/dnanexus/out/logfiles/logfiles/$project_name.output_parser.log
        # create dx run command, using the inputs
        dx_run_cmd="dx run $coverage_app_id --detach -y --brief --name=$bamfile_name -ibam_index=$bai_id -ibamfile=$bam_id -icoverage_level=$coverage_level -isambamba_bed=$coverage_bedfile_id $coverage_commands --dest=$project_id:/coverage/$pannumber --auth-token $API_KEY"
        # copy the dx run command to the dx_run_cmds.sh
        echo $dx_run_cmd >> /home/dnanexus/out/logfiles/logfiles/$project_name.dx_run_cmds.sh
        # run the command
        $dx_run_cmd
    done 

### run sompy on HD200 sample if present
printf "\nVCFs to be searched for HD200 sample and sompy run if present\nVCF indexes created at this stage\n" >> /home/dnanexus/out/logfiles/logfiles/$project_name.output_parser.log
# create a array of results vcf names
# parse the dx describe output for all outputs in the results_vcfs output
# collapse the jsob for each output into a single line, filter for genome.vcf (the merged small variants vcf file) and return the file names
vcfs_array=$(dx describe --json --multi $tso500_jobid:results_vcfs | jq -c '.[]'  | grep genome.vcf)
#loop through vcfs to find control and build dx run command for sompy
for genome_vcf in $vcfs_array
    do 
        # for each input (a json) return the id field and filename
        fileid=$(jq -r '.id' <<< $genome_vcf)
        filename=$(jq -r '.name' <<< $genome_vcf)
        
        if [[ "$filename" =~ .*"HD200".* ]]; 
            then
            # build sompy command using the provided appid
            sompy_command="dx run $sompy_app_id  --detach -y --brief --name=$filename -itruthVCF=project-ByfFPz00jy1fk6PjpZ95F27J:file-G7g9Pfj0jy1f87k1J1qqX83X -iqueryVCF=$fileid -iTSO=true -iskip=false --dest=$project_name:/ --auth-token $API_KEY" 
            # write cmd to file and to stdout
            echo $sompy_command
            echo "jobid=($sompy_command)" >> /home/dnanexus/out/logfiles/logfiles/$project_name.dx_run_cmds.sh
            #execute the command and capture jobid to delay multiqc
            jobid=$($sompy_command)
            depends_list="${depends_list} -d ${jobid}"
        fi

        # create indexed vcfs
        # use project and file ids to download the vcf
        projectid=$(jq -r '.project' <<<$genome_vcf)
        vcf_id=$projectid:$fileid
        dx download $vcf_id
        # create path for bgzipped vcf
        echo "creating indexed vcf for file name $filename file ID $vcf_id"
        # get path for vcf to put gzipped vcf- taking the folder where the vcf is located from the json output from dx describe above. filefolder format ~=/analysis_folder/Results/*sample_ID*
        # this allows the bgzipped vcf and index to be put in the correct sample folder in analysis_folder/Results
        filefolder=$(jq -r '.folder' <<< $genome_vcf)
        # create output folder for bgzipped vcf and index
        gzip_vcf_path=$vcf_index_output$filefolder
        mkdir -p $gzip_vcf_path
        # bgzip the vcf and output the .vcf.gz file to the sample folder in Results
        gzip_vcf=$gzip_vcf_path/$filename.gz
        bgzip -c $filename > $gzip_vcf
        # move in to the sample folder (where the bgzipped file is saved)
        cd $gzip_vcf_path
        # index the vcf.gz file with tabix
        tabix -p vcf $gzip_vcf
        # move back to /home/dnanexus
        cd ~
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
