<#
  Perfecto Mobile, Inc.
  Last modified: 22-August-2017
  Version: 1.0.4

  Powershell script to create CSV and upload to Gainsight via HTTPS for on-prem MCMs
  Enables CSM to provide customers advanced usage reports
  NOTE: You must Set-ExecutionPolicy Unrestricted in PowerShell manually before running
#>

# These values must be changed
$tz = "US/Eastern" # Change to match where the primary customer is located
$dbpass = "replace with password" # PostgreSQL password for postgres user
$accessKey = "replace with accessKey"
$loginName = "replace with loginName"
$appOrgId = "replace with appOrgId"
$jobId = "replace with jobId"

$psqlPath = "C:\Program Files (x86)\PostgreSQL\9.3\bin\psql.exe" # Adjust if different version or path
#$psqlPath = "C:\Program Files\PostgreSQL\9.6\bin\psql.exe" # Testing
$outputDir = "C:\Temp" # Where query results are saved (CSVs)
$scriptDir = "C:\Users\Administrator\Documents" # where scripts are stored
$sqlFile = "$scriptDir\usage-to-gainsight.sql" # SQL script
$settingsFile = "C:\nexperience\user\conf\admin-common.local.properties" # need np.host value
$outputBase = "usage" # base name for files we create
$lastSyncFile = "$outputDir\$outputBase-last-sync.txt" # file that retains last sync date
$outputFile = "$outputDir\$outputBase.tmp.csv" # Output file before chunking
[int]$maxUploadSize = 79000000 # Gainsight can handle up to 80 MB uploads. Use 1000000 for testing chunking.
[int]$avgRowSize = 392 # Average number of bytes per row of usage data
[int]$maxRows = $maxUploadSize / $avgRowSize # Max rows per file to stay < 80 MB
$fqdn = Get-Content -Path $settingsFile | Where-Object { $_ -match 'np.host=' } | %{$_.split('=')[1]} # Read from settings
$end = Get-Date -UFormat "%Y-%m-%d" # Today's date in PostgreSQL-friendly format
$uploaded = $true # Any negatives along the way prevent update to $lastSyncFile 

Function ConvertFrom-JsonPS2 {
  param(
    $json,
    [switch]$raw  
  )
  Begin
  {
    $script:startStringState = $false
    $script:valueState = $false
    $script:arrayState = $false	
    $script:saveArrayState = $false

    function scan-characters ($c) {
      switch -regex ($c)
      {
        "{" { 
          "(New-Object PSObject "
          $script:saveArrayState=$script:arrayState
          $script:valueState=$script:startStringState=$script:arrayState=$false				
            }
        "}" { ")"; $script:arrayState=$script:saveArrayState }

        '"' {
          if($script:startStringState -eq $false -and $script:valueState -eq $false -and $script:arrayState -eq $false) {
            '| Add-Member -Passthru NoteProperty "'
          }
          else { '"' }
          $script:startStringState = $true
        }

        "[a-z0-9A-Z@. ]" { $c }

        ":" {" " ;$script:valueState = $true}
        "," {
          if($script:arrayState) { "," }
          else { $script:valueState = $false; $script:startStringState = $false }
        }	
        "\[" { "@("; $script:arrayState = $true }
        "\]" { ")"; $script:arrayState = $false }
        "[\t\r\n]" {}
      }
    }
    
    function parse($target)
    {
      $result = ""
      ForEach($c in $target.ToCharArray()) {	
        $result += scan-characters $c
      }
      $result 	
    }
  }

  Process { 
    if($_) { $result = parse $_ } 
  }

  End { 
    If($json) { $result = parse $json }

    If(-Not $raw) {
        $result | Invoke-Expression
    } else {
        $result 
    }
  }
}

if (Test-Path $lastSyncFile) { #lastSyncFile exists
  $start = [IO.File]::ReadAllText($lastSyncFile) # Read last sync date
}
else {
  $start = "2017-01-01" # Use as earliest date
}

# Generate CSV by passing parameters to SQL script
$env:PGPASSWORD = $dbpass;
& $psqlPath -h localhost -U postgres -d nexperience -f "$sqlFile" -v fqdn="'$fqdn'" -v start="'$start'" -v end="'$end'" -v tz="'$tz'" > $outputFile

# Cleanup CSV and break into pieces < 80 MB (if necessary)
$source = New-Object System.IO.StreamReader $outputFile # file output by psql
try {
  $trash = $source.ReadLine() # throw away first line (output from SET command)
  [int]$rowCount = 0 # counter to determine whether to start a new file
  [int]$chunk = 1 # number added to chunk filename
  $hasRows = $False # whether there's any usage data to upload to Gainsight
  while(!$source.EndOfStream) {
    $currentLine = $source.ReadLine()
    $rowCount++
    switch ($rowCount) {
      1 { # first row, time to create a chunk and retain header so it can be added to later chunks
        $target = New-Object System.IO.StreamWriter "$outputDir\$outputBase$chunk.csv"
        $header = $currentLine
      }
      2 { # there's at least one row of data
        $hasRows = $True
      }
      $maxRows { # time to create a new chunk and reset the rowCount to 2 (since we'll add header)
        $target.Close()
        $chunk++
        $target = New-Object System.IO.StreamWriter "$outputDir\$outputBase$chunk.csv"
        $target.WriteLine($header)
        $rowCount = 2
      }
    }
    $target.WriteLine($currentLine)
  }
}
finally {
  $source.Close()
  $target.Close()
}

if ($hasRows) {
  echo "Cloud: $fqdn, Time Zone: $tz"
  for ($i=1; $i -le $chunk; $i++) {
    $usageFile = "$outputDir\$outputBase$i.csv"
    echo "Attempting to upload from $fqdn..."

    # Start of curl substitute
    $boundary = [guid]::NewGuid().ToString()
    $uri = "https://app.gainsight.com/v1.0/admin/connector/job/bulkimport"
    $filebody = [System.IO.File]::ReadAllBytes($usageFile)
    $enc = [System.Text.Encoding]::GetEncoding("utf-8")
    $filebodytemplate = $enc.GetString($filebody)
    [System.Text.StringBuilder]$contents = New-Object System.Text.StringBuilder
    [void]$contents.AppendLine()
    [void]$contents.AppendLine("--$boundary")
    [void]$contents.AppendLine("Content-Disposition: form-data; name=""file""; filename=""$($usageFile.Name)""")
    [void]$contents.AppendLine("Content-Type: text/csv; charset=utf-8")
    [void]$contents.AppendLine()
    [void]$contents.AppendLine($filebodytemplate)
    [void]$contents.AppendLine("--$boundary")
    [void]$contents.AppendLine("Content-Disposition: form-data; name=""jobId""")
    [void]$contents.AppendLine()
    [void]$contents.AppendLine("$jobId")
    [void]$contents.AppendLine("--$boundary--")
    $template = $contents.ToString()
    $body = [byte[]][char[]]$template;
    $request = [System.Net.WebRequest]::Create($uri) #was HttpWebRequest and CreateHttp
    $request.Timeout = 60000
    $request.ContentType ="multipart/form-data;boundary=$boundary"
    $request.Method = "POST"
    $request.Headers.Add("appOrgId","$appOrgId")
    $request.Headers.Add("accessKey","$accessKey")
    $request.Headers.Add("loginName","$loginName")
    try {
      [System.IO.StreamWriter]$requestStream = $request.GetRequestStream()
      $requestStream.Write($body, 0, $body.Length)
      $requestStream.Close()
      [System.Net.WebResponse]$response = $request.GetResponse()
      if ($response.StatusCode -eq "OK") {
        echo "Gainsight responded."
        $sr = New-Object System.IO.StreamReader $response.GetResponseStream()
        $gainsightResponse = $sr.ReadToEnd() | ConvertFrom-JsonPS2
        if ($gainsightResponse.result) {
          echo "Successfully uploaded $usageFile."
        }
        else {
          $uploaded = $false
          echo "Upload not accepted by Gainsight: either no data to send or CSV was improperly formatted."
        }
      }
    }
    catch [Exception] {
      $exception = $_.ErrorDetails | ConvertFrom-JsonPS2
      echo "Failed: $($exception)"
      $uploaded = $false
    }
    finally {
      if ($null -ne $streamWriter) { $streamWriter.Dispose() }
      if ($null -ne $requestStream) { $requestStream.Dispose() }
      if ($response) {
        $response.Close()
        Remove-Variable response
      }
    }
    # End of curl replacement
  } # for loop

  if ($uploaded) {
    echo $end > $lastSyncFile # save date to lastSyncFile as our next starting point
    echo "Updated last sync date."
  }
} # hasRows
else {
  echo "No usage to upload."
}

Remove-Item "$outputDir\$outputBase*.csv" # cleanup generated CSV files
echo "Done."
