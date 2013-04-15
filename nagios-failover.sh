#!/bin/bash

##############################################################################
# Bash script written by Vahid Hedayati April 2013
##############################################################################
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
##############################################################################

# PLEASE REFER TO THE README

# once you have got this working - you can disable or stop nagios on one host and run script which should over take nagios config on thist host
# This can be run on many nagios servers all in one go that can be put in to look out for each other 

# Simply add a cron entry (once it works) to then look out for when there is issues with a specific datacentre
# */2 * * * * admin /usr/local/bin/nagios-failover.sh >/dev/null 2>&1


RAND=$$;
hostname=$(hostname -s)

# The server names of each nagios server
SYNC_SERVERS="nagios1 nagios2"
SYNC_PATH="/opt/nagios-sync"
share=$SYNC_PATH
status="$share/status.log"
tmp_status="$share/status.log.tmp"
conf_backup="$share/config_backup"


# Make a backup of the current working nagios.cfg as nagios.cfg.master
config_file="/etc/nagios/nagios.cfg"
master_file="/etc/nagios/nagios.cfg.master"


USERS='person_to_email@your_company.com'

# Define the script user and current running user
SCRIPTUSER=${USER}
REQUIREDUSER="nagios"

#This the main folder that the datacentres branch off of. refer to the notes
company="company";

#####################################
# Amount of arrays rows below
X=2;

# Environments or Data Centres
s[1]="datacentre1";
s[2]="datacentre2";

# URLS
u[1]="nagios1.example.com"
u[2]="nagios2.example.com"

# Nagios authentication details
up[1]="nagiosadmin:PASSWORD"
up[2]="nagiosadmin:PASSWORD"

# Set array to 0 or beginning
i=0

nagios_url="/nagios/cgi-bin/status.cgi?hostgroup=all&style=hostdetail"

######################################

# uncomment below and comment out the line after --  if you do are running as nagios user - otherwise other users may need to sudo in order to edit files etc
# sudoact="sudo ";
sudoact="";


# Ensure script is running as correct user
if  [[ ! $SCRIPTUSER =~ $REQUIREDUSER ]]; then
  echo "$SCRIPTUSER not valid -- script needs to be run by user: $REQUIREDUSER"
	exit 1;
fi


# Send email to users 
function sendemail () { 

	echo -e $msg|mail -s $SUBJECT $USERS

}


function restart_nag() { 
	sudo /etc/init.d/nagios restart
}

## This requires the script to be run as nagios 
## which in turn uses admin keys to ssh across
function sync_files() { 
	_unison=/usr/bin/unison
	for s in ${SYNC_SERVERS}; do
		if [[ $r =~ $hostname ]]; then 
			echo "ignoring $r matches $hostname";
		else
			for f in ${SYNC_PATH}; do
        			${_unison} -batch "${p}"  "ssh://${s}/${f}"
			done
		fi
	done
}


function check_nagios() { 
	# synchronise logs admin folder
	sync_files;

	# Go through the server array 
	while [ "$i" -lt "$X" ]; do
		let "i++"
		# For each array item expand members - these should map to each id above
		datacentre=${s[$i]};
		nagios_host=${u[$i]}
		userpass=${up[$i]}
		
		# Check to see if the current nagios host matches this host
		# if it does no point in script checking itself and trying to take over its own config
		if [[ $nagios_host =~ $hostname ]]; then 
			echo "$nagios_host matches $hostname ignoring $datacentre"
		else

			# Check out datacentre 
			echo "Health statistics of $datacentre"

			# Run a url http check
			#elinks --dump http://$userpass@$nagios_host/$nagios_url/ | grep "Nagios" >/dev/null 2>&1
			elinks --dump http://$userpass@$nagios_host/$nagios_url | grep "Host Status Details"  >/dev/null 2>&1

			# If return result is not 0 i.e. exist code if 0 has passed 
			if [ $? -ne 0 ] ; then
				msg=$msg" Nagios is down in $datacentre \n"

				# Check to see if $datacentre is already in the status log file
				grep $datacentre $status > /dev/null
				# Exit code 0 - then it was found in status file
	  			if [ $? = 0 ]; then
					# return which host took over 
					thishost=$(grep $datacentre $status|awk '{print $2}')
					#random_file=$(grep $datacentre $status|awk '{print $3}')
                        		#msg=$msg" $datacentre is down and being monitored by $thishost \n"
				else
					grep "$company/$datacentre" $config_file > /dev/null
					# check for config entry in config file and status 0 means found
					if [ $? = 0 ]; then
						grep "$company/$datacentre" $config_file
						msg=$msg" $datacentre has already been added to configuration - no need to set\n"
					else
						# this else is where config was not found and the host is down and was not in status file 
						# so preparing to take over failed nagios host
						msg=$msg" Backing up config to $conf_backup/nagios.cfg.$RAND \n"
						# Back up existing config file to shared mount point
						cp $config_file $conf_backup/nagios.cfg.$RAND
						$sudoact chown :nagios $conf_backup/nagios.cfg.$RAND
						# store environemnt current host running script and the random id to status file
						echo "$datacentre $hostname $RAND" >> $status

						# Add the extra config to this nagios.cfg
						config="# $datacentre servers - services\ncfg_dir=/etc/nagios/objects/$company/$datacentre"
						content=$(echo -e $config)
						line=$(grep -n "# AUTOMATION ADD HERE" $config_file|awk -F":" '{print $1}')
						# Above gets it all ready below adds entry
						edit=$($sudoact ed -s $config_file << EOF
$line
a
$content
.
w
q
EOF
)
						# Carry out work silently
						$edit  >/dev/null 2>&1
						# synchronise logs admin folder
        					sync_files;
						# Prepare further email content
						msg=$msg" Adding $config to $config_file \n"
						msg=$msg" Restarting Nagios\n"

						SUBJECT="$datacentre Nagios Failed over to $hostname"
						# Send email
						sendemail
						#Restart nagios
						restart_nag
					fi
				fi
			else

				# This else is where the nagios url was ok and running
				echo "$datacentre Nagios ok"
		
				# Check to see if config is in current config
				grep "$company/$datacentre" $config_file > /dev/null
				# status was 0 which means it was found
                		if [ $? = 0 ]; then
					# Look for the random id in the status file that matches current env and this hostname
					random_file=$(grep "$datacentre $hostname" $status|awk '{print $3}')
					# If it was found
					if [ "$random_file" != "" ]; then
						# Update email message 
						msg=$msg" Environment: $datacentre had been added to $status and exists in $config_file - resetting to correct configuration \n"
						# check to see if the actual file exists in shared mount point config backup folder
						if [ -f $conf_backup/nagios.cfg.$random_file ]; then 
							# Found the file so move it back
							msg=$msg" Moving  $conf_backup/nagios.cfg.$random_file as $config_file \n"
							$sudoact mv $conf_backup/nagios.cfg.$random_file $config_file
							$sudoact chown nagios:nagios $config_file
						else
							# Otherwise something has gone wrong so copy the nagios.cfg.master over nagios.cfg
							msg=$msg" Could not find $conf_backup/nagios.cfg.$random_file - copying $master_file to $config_file \n";
							cp $master_file $config_file
							$sudoact chown nagios:nagios $config_file
						fi
						# Now clean up the status.log file and remove this entry 
						msg=$msg" Removing $datacentre $hostname $random_file from $status \n"
						grep -v "$datacentre $hostname $random_file"  $status > $tmp_status
						mv $tmp_status $status 
						# synchronise logs admin folder
                                                sync_files;
						SUBJECT="$datacentre Nagios recovered - configuration from $hostname back to normal"
		 				msg=$msg" Restarting Nagios\n"
						sendemail
						restart_nag
					fi
				fi
			fi
		fi
	done
}

check_nagios
