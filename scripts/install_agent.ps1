# This script installs the windows puppet agent on the windows seteam vagrant vms
#
# It first checks to see if there is a web server listening on port 80 on the puppet master.
# If there is, I assume that this is set up by the seteam demo code, and that the
# Windows installer is being served from the master. In this case, we install from the master.
#
# If there is no web server listening on port 80 on the master, then we install from aws.

# Accept the agent certname as an input parameter, since it's a pain to
# set the fqdn for vagrant windows guests.
param(
  [string] $puppet_agent_certname,
  [string] $pe_version
)

$puppet_master_server = 'master.inf.puppetlabs.demo'

# Determine whether a web server is listening on port 80 on the master
# If so, then assume that se demo code has set it up,
# and that it hosts the windows installer
$http_request = [System.Net.WebRequest]::Create("http://$puppet_master_server")

# This is mostly to keep the error text from cluttering the vagrant output
# if there is no web server listening on port 80 on the master.
Try {
  $http_response = $http_request.GetResponse()
  $http_status = $http_response.StatusCode
  $http_response.Close()
} Catch {
  $error_text = $error[0]
}

# If there is a webserver listening on port 80 the master, install the msi from the master,
# otherwise install from aws.
If ($http_status -eq 200) {
  $msi_source = "http://$puppet_master_server/installers/puppet-enterprise-$pe_version-x64.msi"
} Else {
  $msi_source = "http://s3.amazonaws.com/pe-builds/released/$pe_version/puppet-enterprise-$pe_version-x64.msi"
}

# Start the agent installation process and wait for it to end before continuing.
#
# NOTE: I can't for the life of me get this to work with start /wait directly from powershell,
#       so I'm using System.Diagnostics.Process.WaitForExit() instead. 
Write-Host "Installing puppet agent from $msi_source"

$msiexec_path = "C:\Windows\System32\msiexec.exe"
$msiexec_args = "/qn /i $msi_source PUPPET_MASTER_SERVER=$puppet_master_server PUPPET_AGENT_CERTNAME=$puppet_agent_certname"
$msiexec_proc = [System.Diagnostics.Process]::Start($msiexec_path, $msiexec_args)
$msiexec_proc.WaitForExit()
