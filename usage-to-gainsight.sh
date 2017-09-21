#!/bin/bash
#  Perfecto Mobile, Inc.
#  Last modified: 22-August-2017
#  Version: 1.0.4
#  Bash shell script that collects usage data from hosted MCMs and uploads to Gainsight

uploadToGainsight() {
  response=`curl -s -S -X POST -H "Content-Type: multipart/form-data" -H "loginName: $loginName" -H "appOrgId: $appOrgId" -H "accessKey: $accessKey" --form "file=@$1" --form "jobId=$jobId" https://app.gainsight.com/v1.0/admin/connector/job/bulkimport`
  case $response in
    *":true"*) printf "Success: Uploaded $1\n"
      PGPASSWORD=$dbpass psql -q -h localhost -U postgres -d eventrecords -c "UPDATE cloudslist SET last_sync = '$end' WHERE url = '$fqdn';"
    ;;
    *"GS_7571"*) printf "Info: No usage data to upload\n"; ;;
    *) printf "Error: $1 failed to upload\n"; ;;
  esac
  rm -f "$1"
  # To do it right, return true or false from upload() and keep track of transaction ids from Gainsight so we can undo uploads if there's a failure after the first of n chunks
  # For now, we'll use the light approach.
}

main() {
  # These values must be changed
  dbpass="replace with password"
  accessKey="replace with accessKey"
  loginName="replace with loginName"
  appOrgId="replace with appOrgId"
  jobId="replace with jobId"

  csvDir="/tmp"
  maxUploadSize=79000000
  end=`date +%Y-%m-%d`

  cd "$csvDir"

  printf "Run started.\n\n"
  clouds=`PGPASSWORD=$dbpass psql -q -h localhost -U postgres -d eventrecords -c "COPY(SELECT DISTINCT lower(url) AS fqdn, mcm_ip_address AS ip, tz, last_sync FROM cloudslist WHERE validity = 'Y' AND sfname <> 'Perfecto Mobile' AND env_stat = 'production' ORDER BY fqdn) TO STDOUT CSV NULL '' ENCODING 'UTF8'"`
  for currentCloud in $clouds; do
    fqdn=`echo $currentCloud | cut -d, -f1`
    ip=`echo $currentCloud | cut -d, -f2`
    tz=`echo $currentCloud | cut -d, -f3`
    start=`echo $currentCloud | cut -d, -f4`
    printf "Cloud: $fqdn, IP: $ip, Time Zone: $tz\n"
    usageFile="$fqdn.csv"
    PGPASSWORD=$dbpass psql -h $ip -U postgres -d nexperience -t -f "/opt/scripts/usage-to-gainsight.sql" -v fqdn="'$fqdn'" -v start="'$start'" -v end="'$end'" -v tz="'$tz'" > $usageFile
    sed -i '1d' $usageFile
    outputSize="$(wc -c <"$usageFile")"
    if [ $outputSize -lt $maxUploadSize ]; then
      uploadToGainsight $usageFile
    else
      avgRowSize=392
      rowsPerSegment=$(($maxUploadSize/$avgRowSize))
      split -l $rowsPerSegment "$usageFile" "$fqdn-chunk"
      for c in "$fqdn-chunk"* ; do
        mv $c ${c}.csv
      done
      currentChunk=1
      head -1 $usageFile > "$fqdn-header.csv"
      for f in "$fqdn-chunk"* ; do
        if [ $currentChunk -gt 1 ]; then
          cat "$fqdn-header.csv" "$f" > "$fqdn-temp.csv"
          rm "$f"
          mv "$fqdn-temp.csv" "$f"
        fi
        uploadToGainsight $f
        ((currentChunk++))
      done
      rm -f "$fqdn-header.csv"
      rm -f "$fqdn.csv"
    fi
  done
  printf "\nRun completed.\n"
}

main
