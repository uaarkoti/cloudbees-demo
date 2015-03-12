#!/bin/bash

# this script deploys using the tar.gz found in environments folder
#
# If there is no such file, then it writes a message to this effect to stdout.
# It then drops any firewall rules on the master vagrant box (this is
# typically handled by the seteam demo code).
#
# (This results in a stock PE environment with no demo code or modules.)

function test_for_initial_puppet_run(){
  PUPPET_RUNNING=$(ps -ef | grep 'waitforcert' | grep -v grep | wc -l)
}

# Make sure that a puppet agent run happens on the master
# after classifying it with the necessary platform support classes.
function wait_for_initial_puppet_run(){
  echo "Waiting for initial puppet run to complete,"
  echo "to ensure that platform supporting classes are in place."

  test_for_initial_puppet_run

  if [ $PUPPET_RUNNING == "0" ]
  then
    echo "Sleeping for 30 seconds to allow initial puppet run to begin."
    sleep 30
    test_for_initial_puppet_run

    if [ $PUPPET_RUNNING == "0" ]
    then
      echo "Puppet run not initiated after 30 seconds."
      echo "Triggering puppet run."
      /opt/puppet/bin/puppet agent -t
    else
      while [ $PUPPET_RUNNING == "1" ]
      do
        echo "Puppet run is in progress."
        echo "Sleeping for 30 seconds..."
        sleep 30
        test_for_initial_puppet_run
      done
    fi
  fi

  echo "Puppet run is complete."
}

ENV_VERSION=$(find /vagrant -name seteam-production*.tar.gz)

if [ -z ${ENV_VERSION} ]
then
  echo "The seteam demo tarball was not found."
  echo "Removing firewall rules to allow agents to communicate with the master."
  
  # GMS: I know, I know. I'm a little ashamed, too.
  #
  #      But since this is specifically the case where we're setting up a vanilla PE master
  #      with no additional modules, I'm just using bash to remove the firewall rules on 
  #      the puppetlabs/centos-6.5-64-nocm vagrant box.
  iptables -F
  /sbin/service iptables save

  # In the case where there is no seteam demo tarball,
  # classify the master with the platform support classes necessary
  # to support all of the agent VMs
  /opt/puppet/bin/ruby /vagrant/scripts/add_platform_classes_to_master.rb

  # Wait for the initial puppet run to complete on the master before proceeding.
  # This will ensure that the support classes are evaluated before we try
  # to create any agent VMs.
  wait_for_initial_puppet_run
else
  tar xzf $ENV_VERSION -C /etc/puppetlabs/puppet/environments/production/ --strip 1

  #we are staging the agent files before we do anything else
  /bin/bash /vagrant/scripts/stage_agents.sh

  /bin/bash /etc/puppetlabs/puppet/environments/production/scripts/deploy.sh
fi

echo "PATH=/opt/puppet/bin:$PATH" >> /root/.bashrc

cat << EOF > /etc/r10k.yaml
---
:cachedir: /var/cache/r10k
:sources:
  :local:
    remote: https://github.com/ccaum/cloudbees-demo-site
    basedir: /etc/puppetlabs/puppet/environments
EOF

/opt/puppet/bin/r10k deploy environment
