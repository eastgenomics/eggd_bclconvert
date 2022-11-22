#!/bin/bash
set -exo pipefail


_download_files () {
  : '''
  Download tar/rar/zips of run data
  '''
  # either a run archive or a sentinel record must be provided as an input
  if [ -n "${run_archive}" ]; then
    for i in ${!run_archive_name[@]}; do
      # check format and decompress
      name="${run_archive_name[${i}]}"

      if [[ "${name}" == *.tar.gz ]] || [[ "${name}" == *.tgz ]]; then
        dx cat "${run_archive[${i}]}" | tar zxf - --no-same-owner

      elif [ "${name}" == *.zip ]; then
        dx download "${run_archive[$i]}" -o "${name}"
        unzip "${name}"

      elif [ "${name}" == *.rar ]; then
        dx download "${run_archive[${i}]}" -o "${name}"
        unrar x "${name}"

      else
        dx-jobutil-report-error "ERROR: The input was not a .rar, .zip, .tar.gz or .tgz"
        exit 1
      fi
    done

  elif [ -n "${upload_sentinel_record}" ]; then
    # get the tar.gzs linked to the record and uncompress them in the order they were created
    file_ids=$(dx get_details "${upload_sentinel_record}" | jq -r '.tar_file_ids | .[]')

    # check first tar to see if they are compressed (should be)
    first_tar=($file_ids)
    name=$(dx describe --json $first_tar | jq -r '.name')
    extn="${name##*.}"

    SECONDS=0
    if [[ "${extn}" == "gz" ]]; then
      echo $file_ids | sed 's/ /\n/g' \
        | xargs -P ${THREADS} -n1 -I{} sh -c "dx cat {} | tar xzf - --no-same-owner --absolute-names -C ./"
    elif [[ "${extn}" == "tar" ]]; then
      echo $file_ids | sed 's/ /\n/g' \
        | xargs -P ${THREADS} -n1 -I{} sh -c "dx cat {} | tar xf - --no-same-owner --absolute-names -C ./"
    else
        dx-jobutil-report-error "The upload_sentinel_record doesn't contain tar or tar.gzs"
        exit 1
    fi
    duration=$SECONDS

    echo "Downloading and unpacking took $(($duration / 60))m$(($duration % 60))s."

  else
    dx-jobutil-report-error "No sentinel record or run data provided as input"
  fi
}


_upload_all_output(){
  : '''
  Upload all data in /home/dnanexus/out/output
  '''
  echo "Total files to upload: $(find /home/dnanexus/out/output -type f | wc -l)"
  SECONDS=0

  # upload all output files in parallel and add to output spec
  export -f _upload_single_file 
  find "$OUTDIR" -type f  | xargs -P ${THREADS} -n1 -I{} bash -c "_upload_single_file {}"

  duration=$SECONDS
  echo "Uploading took $(($duration / 60))m$(($duration % 60))s."
}


_upload_single_file(){
  : '''
  Uploads single file with dx upload and associates uploaded file ID to output spec
  '''
  local file=$1
  local remote_path=$(sed s'/\/home\/dnanexus\/out\/output//' <<< "$file")

  echo "file: ${file}"

  file_id=$(dx upload -p "$file" --path "$remote_path" --brief)
  dx-jobutil-add-output output_files "$file_id" --array
}


_find_samplesheet () {
  : '''
  Ensure a samplesheet is present in the home dir, either a user provided one, from
  the run data or associated to the sentinel file
  '''
  if [ "${sample_sheet}" ]; then
    echo "Using user provided samplesheet"
    dx download -f "${sample_sheet}" -o SampleSheet.csv

  elif [[ $(find ./ -regextype posix-extended  -iregex '.*sample[-_ ]?sheet.csv$') ]]; then
    # Sample sheet not given, try finding it in the run folder
    # Use regex to account for anything named differently
    # e.g. run-id_SampleSheet.csv, sample_sheet.csv, Sample Sheet.csv, sampleSheet.csv etc.
    samplesheet=$(find ./ -regextype posix-extended  -iregex '.*sample[-_ ]?sheet.csv$')
    echo "Using sample sheet in run directory: $samplesheet"
    mv "$samplesheet" /home/dnanexus/SampleSheet.csv

  elif [ -n "${upload_sentinel_record}" ]; then
    # Samplesheet not present in run data, check if linked to sentinel record
    sample_sheet_id=$(dx get_details "${upload_sentinel_record}" | jq -r .samplesheet_file_id)
    if [ "${sample_sheet_id}" ]; then
      echo "Using samplesheet from sentinel record"
      dx download -f "${sample_sheet_id}" -o SampleSheet.csv
    fi
  else
      dx-jobutil-report-error "No SampleSheet could be found."
      exit 1
  fi
}


main() {
  THREADS=$(nproc --all)  # control how many operations to open in parallel
  OUTDIR=/home/dnanexus/out/output && mkdir -p ${OUTDIR}

  mark-section "Downloading input files"
  _download_files

  mark-section "Preparing samplesheet"
  _find_samplesheet

  mark-section "Running bcl-convert"
  SECONDS=0

  /usr/bin/time -v /usr/bin/bcl-convert \
    --bcl-input-directory /home/dnanexus \
    --output-directory /home/dnanexus/Output \
    -f $advanced_opts

  duration=$SECONDS
  echo "Running bcl-convert took $(($duration / 60))m$(($duration % 60))s."

  mark-section "Formatting output for uploading"
  # tar InterOp and Logs directories for single file uploads
  tar -czf InterOp.tar.gz InterOp/
  tar -czf Logs.tar.gz Logs/

  # move all files and dirs to output/ to be uploaded
  mv -t ${OUTDIR}/ Output/ Config/ Recipe/
  mv -t ${OUTDIR}/ InterOp.tar.gz Logs.tar.gz
  mv R*.* ${OUTDIR}/ # RTAComplete.{txt/xml}. RTA3.cfg, RunInfo.xml, RunParameters.xml
  mv S*.* ${OUTDIR}/ # SampleSheet.csv and SequenceComplete.txt

  mark-section "Uploading output"
  _upload_all_output

  # check usage to monitor usage of instance storage
  echo "Total file system usage"
  df -h

  # tag job with usage to easily see what is being used
  mark-section "Tagging job"
  usage=$(df -h | grep "/dev/mapper/md0-crypt" | tr -s ' ')
  used=$(cut -d' ' -f3 <<< "$usage")
  total=$(cut -d' ' -f2 <<< "$usage")
  pct=$(cut -d' ' -f5 <<< "$usage")
  dx tag $DX_JOB_ID "Instance storage used: ${pct} (${used}/${total})"

  mark-success
}
