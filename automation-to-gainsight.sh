#!/bin/bash
#  Perfecto Mobile, Inc.
#  Last modified: 27-Nov-2018
#  Version: 1.0.4
#  Collects automation data from hosted clouds

# Get token for requests
requestToken() {
  url="$baseUrl/trigger?startExecutionTime=$2&endExecutionTime=$3"
  resultsToken=`curl -s -L -H "PERFECTO_AUTHORIZATION: $1" -X GET "$url"`
  echo "$resultsToken"
}

# Use token to get Automation CSV
retrieveAutomation(){
  url="$baseUrl?token=$2&format=csv"
  curl -s -L -H "PERFECTO_AUTHORIZATION: $1" -X GET "$url" > "$csvDir/$csvFile"
}

uploadToGainsight() {
  # Gainsight credentials
  accessKey="REPLACE WITH YOUR OWN"
  loginName="REPLACE WITH YOUR OWN"
  appOrgId="REPLACE WITH YOUR OWN"
  jobId="REPLACE WITH YOUR OWN"

  lines=$((`cat $1 | wc -l` - 1))
  if [ $lines -gt 0 ]; then
    response=`curl -s -S -X POST -H "Content-Type: multipart/form-data" -H "loginName: $loginName" -H "appOrgId: $appOrgId" -H "accessKey: $accessKey" --form "file=@$1" --form "jobId=$jobId" https://app.gainsight.com/v1.0/admin/connector/job/bulkimport`
    case $response in
      *":true"*) printf " Uploaded $lines records..."
        #rm -f "$1"
      ;;
      #*"GS_7571"*) echo "No Execution data"; ;;
      *) printf " Upload Error..."
        uploadFailed=true
      ;;
    esac
  else
    printf " Nothing to Upload..."
  fi
}

securityToken="REPLACE WITH YOUR OWN"
baseUrl="https://demo.reporting.perfectomobile.com/export/api/v1/test-executions/statistics/tenants"
# date command for macOS differs from Linux
if [[ `uname` == 'Darwin' ]]; then
  start=`date -j -v-1d +%s`000
else
  start=`date --date="1 day ago" +%s`000
fi
end=`date +%s`000
uploadFailed=false
csvDir="/tmp"
csvFile="automation.csv"

echo "Starting: `date`"

printf "Requesting token..."
requestToken $securityToken $start $end 
echo " [Done]"

printf "Waiting 2 minutes for Digitalzoom to compile results..."
# Wait for the automation stats to calculate (2 mins)
sleep 120
echo " [Done]"

printf "Retrieving automation statistics..."
retrieveAutomation $securityToken $resultsToken  
echo " [Done]"

printf "Uploading $csvDir/$csvFile to Gainsight..."
uploadToGainsight "$csvDir/$csvFile"
echo " [Done]"
echo "Finished: `date`"
