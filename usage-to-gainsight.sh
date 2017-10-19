#!/bin/bash
#  Perfecto Mobile, Inc.
#  Last modified: 11-October-2017
#  Version: 1.0.5
#  Bash shell script that collects usage data from hosted MCMs and uploads to Gainsight

uploadToGainsight() {
  lines=$((`cat $1 | wc -l` - 1))
  if [ $lines -gt 0 ]; then
    response=`curl -s -S -X POST -H "Content-Type: multipart/form-data" -H "loginName: $loginName" -H "appOrgId: $appOrgId" -H "accessKey: $accessKey" --form "file=@$1" --form "jobId=$jobId" https://app.gainsight.com/v1.0/admin/connector/job/bulkimport`
    case $response in
      *":true"*) printf ",$lines"
        PGPASSWORD=$dbpass psql -q -h localhost -U postgres -d eventrecords -c "UPDATE cloudslist SET last_sync = '$end' WHERE lower(url) = '$fqdn';"
      ;;
      #*"GS_7571"*) printf ",No Usage"; ;;
      *) printf ",Error $1"
        failed=true
      ;;
    esac
  else
    printf ",0"
  fi
  if [ "$failed" != true ]; then
    rm -f "$1"
  fi
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
  startTime=`date`

  cd "$csvDir"

  printf "Start: $startTime.\n"
  clouds=`PGPASSWORD=$dbpass psql -q -h localhost -U postgres -d eventrecords -c "COPY(SELECT DISTINCT lower(url) AS fqdn, mcm_ip_address AS ip, tz, last_sync FROM cloudslist WHERE validity = 'Y' AND sfname <> 'Perfecto Mobile' AND env_stat = 'production' ORDER BY fqdn) TO STDOUT CSV NULL '' ENCODING 'UTF8'"`
  for currentCloud in $clouds; do
    fqdn=`echo $currentCloud | cut -d, -f1`
    ip=`echo $currentCloud | cut -d, -f2`
    tz=`echo $currentCloud | cut -d, -f3`
    start=`echo $currentCloud | cut -d, -f4`
    printf "\n$fqdn,$ip,$tz,$start,$end"
    usageFile="$fqdn.csv"
    PGPASSWORD=$dbpyass psql -h $ip -U postgres -d nexperience -t -f "/opt/scripts/usage-to-gainsight.sql" -v fqdn="'$fqdn'" -v start="'$start'" -v end="'$end'" -v tz="'$tz'" > $usageFile
    sed -i '1d' $usageFile
    outputSize="$(wc -c <"$usageFile")"
    if [ $outputSize -lt $maxUploadSize ]; then
      uploadToGainsight $usageFile
    else
      split --line-bytes=$maxUploadSize "$usageFile" "$fqdn-" -d --additional-suffix=.csv
      currentChunk=1
      head -1 $usageFile > "$fqdn-header.csv"
      for f in "$fqdn-"* ; do
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
  finishTime=`date`
  printf "\n\nFinished: $finishTime\n"
}

main
