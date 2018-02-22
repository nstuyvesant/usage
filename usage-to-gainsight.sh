#!/bin/bash
#  Perfecto Mobile, Inc.
#  Last modified: 22-Feb-2018
#  Version: 1.0.6
#  Bash shell script that collects usage data from hosted MCMs and uploads to Gainsight

uploadToGainsight() {
  lines=$((`cat $1 | wc -l` - 1))
  if [ $lines -gt 0 ]; then

    sed -i '1 i\'$headers $1
    response=`curl -s -S -X POST -H "Content-Type: multipart/form-data" -H "loginName: $loginName" -H "appOrgId: $appOrgId" -H "accessKey: $accessKey" --form "file=@$1" --form "jobId=$jobId" https://app.gainsight.com/v1.0/admin/connector/job/bulkimport`
    case $response in
      *":true"*) echo "Uploaded $1,$lines"
        rm -f "$1"
      ;;
      #*"GS_7571"*) printf ",No Usage"; ;;
      *) echo "Upload Error $1,0"
        uploadFailed=true
      ;;
    esac
  else
    printf "Nothing to Upload,0"
  fi
}

main() {
  # These values must be changed
  dbpass="replace with password"
  accessKey="replace with accessKey"
  loginName="replace with loginName"
  appOrgId="replace with appOrgId"
  jobId="replace with jobId"

  uploadFailed=false
  csvDir="/data/tmp"
  usageFile="usage.csv"
  maxUploadSize=79999500
  end=`date +%Y-%m-%d`
  startTime=`date`
  headers="fqdn,usage_type,event_time,hour_of_day,day,duration_hours,location,device_id,manufacturer,model,os,os_version,os_and_version,os_major_version,device_roles,organization,group_name,username,user_roles"

  cd "$csvDir"

  echo "====== Start: $startTime ====== "
  # Iterate through the clouds in the local PostgreSQL database and dump usage to file
  clouds=`PGPASSWORD=$dbpass psql -q -h localhost -U postgres -d eventrecords -c "COPY (SELECT DISTINCT lower(url) AS fqdn, mcm_ip_address AS ip, tz, last_sync FROM cloudslist WHERE validity = 'Y' AND sfname <> 'Perfecto Mobile' AND env_stat = 'production' ORDER BY fqdn) TO STDOUT WITH (FORMAT csv, NULL '', HEADER false, ENCODING 'UTF8')"`
  for currentCloud in $clouds; do
    fqdn=`echo $currentCloud | cut -d, -f1`
    ip=`echo $currentCloud | cut -d, -f2`
    tz=`echo $currentCloud | cut -d, -f3`
    start=`echo $currentCloud | cut -d, -f4`
    echo "$fqdn,$ip,$tz,$start,$end"
    # Pass parameters to SQL script and omit headers
    PGPASSWORD=$dbpass psql -h $ip -U postgres -d nexperience -t -f "/opt/scripts/usage-to-gainsight.sql" -v fqdn="'$fqdn'" -v start="'$start'" -v end="'$end'" -v tz="'$tz'" >> $usageFile
  done

  # Upload file if under max size otherwise in chunks
  outputSize="$(wc -c <"$usageFile")"
  if [ $outputSize -lt $maxUploadSize ]; then
    uploadToGainsight $usageFile
  else
    split --line-bytes=$maxUploadSize "$usageFile" "usage-" -d --additional-suffix=.csv
    currentChunk=1
    for f in "usage-"* ; do
      uploadToGainsight $f
      ((currentChunk++))
    done
  fi
  rm -f "$usageFile"

  # Update last sync in PostgreSQL if no upload errors
  if [ "$uploadFailed" != true ]; then
    PGPASSWORD=$dbpass psql -q -h localhost -U postgres -d eventrecords -c "UPDATE cloudslist SET last_sync = '$end';"
  fi

  finishTime=`date`
  echo "====== Finished: $finishTime ====== "
}

main
