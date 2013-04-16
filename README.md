nagios-failover
===============

script to failover  nagios servers if and when their down - automtically done via bash fail over script that will require some ground work to be done in order to achieve the end result of each nagios server looking out for one another.
 

I have also done a few other things


cd /etc/;

ln -s /usr/local/nagios/etc  ./nagios

cd /etc/nagios;

ln -s  /usr/local/nagios/libexec ./plugins



Requirements. 

1. Actual nagios cfg files - 

CMS (configuration Management System - puppet,chef or cfengine)

I have used puppet and used the recursive folder plugin to push all the actual cfg files to nagios nodes:

# You could use the unison protocol and add /usr/local/nagios/etc/objects/$company as a folder to also be synchronised and bypass all this CMS requirements.
# You would need to move :

       commands.cfg
       admin.cfg
       timeperiods.cfg
       templates.cfg
       to :  /usr/local/nagios/etc/objects/$company  and update the reference in nagios.cfg accordingly
       
       
# CMS Way puppet config
  
  
        $objects="/usr/local/nagios/etc/objects"
        $company_objects="$objects/company"

        file { "$company_objects":
                ensure => directory, # so make this a directory
                recurse => true, # enable recursive directory management
                purge => true, # purge all unmanaged junk
                force => true, # also purge subdirs and links etc.
                owner => "nagios",
                group => "nagios",
                mode => 0644, # this mode will also apply to files from the source directory
                # puppet will automatically set +x for directories
                source => "puppet:///modules/nagios/company",
        }


so inside:
files/company I have currently two data centres:
in each of these data centres

    files/company/datacentre1
       - files/company/datacentre1/prod
          -- files/company/datacentre1/prod/hosts
          -- files/company/datacentre1/prod/services

     pwd
     /usr/local/nagios/etc/objects
     
     tree
     .
     |-- admin.cfg
     |-- commands.cfg
     |-- generic-host.cfg
     |-- generic-service.cfg
     |-- company_folder
     |   |-- README
     |   |-- datacentre1
     |   |   |-- development
     |   |   |   |-- hosts
     |   |   |   |   `-- development-servers.cfg
     |   |   |   `-- services
     |   |   |       |-- development-sources.cfg
     |   |   |       `-- generic-development.cfg
     |   |   |-- uat
     |   |   |   |-- hosts
     |   |   |   |   `-- uat-servers.cfg
     |   |   |   `-- services
     |   |   |       |-- apache-uat.cfg
     
     
     
and so on


on my nagios 3.5 servers I have defined the path to each datacentre:

Nagios server 1

     # Datacentre1 servers - services
     cfg_dir=/etc/nagios/objects/company/datacentre1




Nagios server 2

     # Datacentre1 servers - services
     cfg_dir=/etc/nagios/objects/company/datacentre2


Nagios will then read all the files within the sub folders of each datacentre  recursivly on each nagios host... (this simplify definition of each config file etc and makes it a lot easier to script this solution.


So once you have puppet pushing out the configuration which in short all nagios hosts have all the configrations but only load up the relevant datacentre folder for what it is supposed to monitor:





2. unison protocol to synchronise amongst nagios hosts

yum install unison or apt-get install unison 


3.  A shared folder amongst all nagios servers

In the script I have defined /opt/nagios-sync

    mkdir /opt/nagios-sync
    mkdir /opt/nagios-sync/config_backup
    touch /opt/nagios-sync/status.log
    chown -R nagios:nagois /opt/nagios-sync



3. Nagios user with sudoers access to restart nagios and access files in /opt/nagois-sync
sudo -i 

visudo

nagios ALL = NOPASSWD: /etc/init.d/nagios

:wq


4. ssh-keygen and ssh-copy-id across all nagios hosts so nagios can ssh from any nagios host to any other without a password as the nagios user.





5. in /etc/nagios/nagios.cfg on all hosts you will need to add:
under the main configuration loading up current data centres

     # AUTOMATION ADD HERE





That should be all that is needed to get it going now refer to the script

