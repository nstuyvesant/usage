# Perfecto Usage Data Collection

The scripts in this project collect usage data from PostgreSQL running on Perfecto's MCMs, create
a CSV file then upload it to Gainsight. If the CSVs go over the Gainsight 80MB limit, they are
split into multiple files. Once each upload is finished, the CSV files are deleted.

There is a bash shell script for collecting usage data from hosted clouds. This script runs within
Perfecto's internal hosting network. It runs on the latest version of Ubuntu.

The PowerShell script is designed to be run on the Windows-based MCM used in on-premises installations.
Directions for its setup can be found on On-Prem Usage Setup.docx.

Both the bash shell and PowerShell scripts use a parameterized SQL query found in usage-to-gainsight.sql.

## Prerequisites
- For hosted usage collection, you must have access to an Ubuntu Server 14.10+ that can reach the MCM's PostgreSQL databases.
- For on-premises, you must be able to Remote Desktop to the MCM as an Administrator.
- Both the bash and Powershell scripts must be updated with values for: pgPassword, accessKey, loginName, appOrgId, and jobId.