#!/bin/bash

PE_RELEASE='3.7.1'
PE_URL="http://s3.amazonaws.com/pe-builds/released/$PE_RELEASE"
HOST_STAGE='/var/seteam-files/installers'
#Internal Build url: http://enterprise.delivery.puppetlabs.net/3.7/ci-ready/

function stage_installer () {
  if [ ! -f "${HOST_STAGE}/${1}" ]; then
    mkdir -p $HOST_STAGE
    cd $HOST_STAGE
    curl -O "${PE_URL}/${1}"
    chmod -R 755 $HOST_STAGE
  fi

  # if this is a tar.gz we should copy it to the masters /opt/staging/pe_repo
  
  str="${1}"
  n=2
  ext=${str:${#str} - $n}
  if [ "${ext}" == 'gz' ]; then
    cp ${HOST_STAGE}/${1} /opt/staging/pe_repo/
    chmod -R 755 /opt/staging/pe_repo
  fi
}





stage_installer puppet-enterprise-$PE_RELEASE-el-7-x86_64-agent.tar.gz

stage_installer puppet-enterprise-$PE_RELEASE-ubuntu-14.04-amd64-agent.tar.gz

stage_installer puppet-enterprise-$PE_RELEASE-ubuntu-12.04-amd64-agent.tar.gz

stage_installer puppet-enterprise-$PE_RELEASE-x64.msi
