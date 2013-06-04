#!/bin/bash
#############################################################################
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

# once you have got this working - you can disable or stop nagios on one host 
# and run script which should over take nagios config on thist host
# This can be run on many nagios servers all in one go that can be put in to look 
# out for each other 

# Simply add a cron entry (once it works) to then look out for when there is issues 
# with a specific datacentre
# */2 * * * * nagios /usr/local/bin/nagios-failover.sh >/dev/null 2>&1
##############################################################################
# REQUIREMENTS:
##############################################################################
# yum install unison or apt-get install unison
# timeout : (available on Debian/Ubuntu) on Centos:
# cp /usr/share/doc/bash-3.2/scripts/timeout /usr/bin/timeout
# chmod 755 /usr/bin/timeout

# mkdir /opt/nagios-sync
# chown -R nagios:nagios /opt/nagios-sync

# on 1 nagios host run ssh-keygen and 
# then scp .ssh folder to all the other nagios hosts 
# or ssh-keygen and ssh-copy-id from each host to another

# Finally run the script mannually to ensure it can ssh without a password 
# and gives you verbosity as to what is going on
##############################################################################




# Random id used to make temp files and back up configs agains
RAND=$$;

# current host running script
hostname=$(hostname -s)

# Actual nagios config files as well a master for fail safe - 
# simply back up nagios.cfg as nagios.cfg.master on regular basis
config_file="/etc/nagios/nagios.cfg"
master_file="/etc/nagios/nagios.cfg.master"


# Person or email to contact when fail overs happen
USERS='your_email@example.com'


# The user and script user that should execute - 
SCRIPTUSER=${USER}
# please update REQUIREDUSED to the user that should be running script
REQUIREDUSER="nagios"

# This is the main folder within nagios objects folder
# in my case I created our company name then each datacentre folder within it
# /etc/nagios/objects/$company/datacentre1
company="your_company";


# Shard folder used by unison to sync files - this holds the status file as well as configuration backup
# Can be set to anything but must exist on all nagios boxes and be accessible / writable / readable 
# by the user running this script
SYNC_PATH="/opt/nagios-sync"
status_file="$SYNC_PATH/status.log"
tmp_status="$SYNC_PATH/status.log.tmp"
conf_backup="$SYNC_PATH/config_backup"

# We will wait between 1 to 30  seconds before attempting to fail over 
# This value has been set to ensure multiple nagios servers attempt at different times rather than simulatinous failover 
FAILOVER_TIME=$((( $RANDOM % 30 )+1)); 
# FAILOVER_TIME=$(( $RANDOM % 10 + 30 )); 




#####################################
# Environments or Data Centres
s[1]="datacentre1";
s[2]="datacentre2";

# Hostnames of nagios boxes that is used to generate the URL as well as 
# used by unison to connect through to and sync shared folder files
u[1]="nagios1.example.com"
u[2]="nagios2.example.com"

# Nagios authentication details
up[1]="nagiosadmin:PASSWORD"
up[2]="nagiosadmin:PASSWORD"

nagios_url="/nagios/cgi-bin/status.cgi?hostgroup=all&style=hostdetail"

######################################


# add sudo to some commands - change over if sudo is required
#sudo_cmd="";
sudo_cmd="sudo "


# Ensure script is running as correct user
if  [[ ! $SCRIPTUSER =~ $REQUIREDUSER ]]; then
	echo "$SCRIPTUSER not valid -- script needs to be run by user: $REQUIREDUSER"
	exit 1;
fi


# Send email to users 
function sendemail () { 
	echo -e $msg|mail -s "$SUBJECT" $USERS
}

function restart_nag() { 
	sudo /etc/init.d/nagios restart
}

## This requires the script to be run as nagios 
## which in turn uses admin keys to ssh across
function sync_files() { 
	_unison=/usr/bin/unison
	for server in ${u[@]}; do
		if [[ $server =~ $hostname ]]; then 
			echo "ignoring $server matches $hostname";
		else
			for f in ${SYNC_PATH}; do
        			timeout 5 ${_unison} -batch "${f}"  "ssh://${server}/${f}"
			done
		fi
	done
}

function check_url() { 
			URL_WORKING=0;
			# Check out datacentre 
			echo "Health statistics of $datacentre"
			# Run a url http check
			echo "elinks --dump http://$userpass@$nagios_host/$nagios_url"
			timeout 10 elinks --dump "http://$userpass@$nagios_host/$nagios_url" | grep -q "Host Status Details" 
			# If return result is not 0 i.e. exist code if 0 has passed 
			if [[ $? -eq 0  ]]; then
				URL_WORKING=1;
			else
				msg=$msg" Nagios is down in $datacentre \n"
				URL_WORKKING=0;
			fi

}
function check_nagios() { 
	# synchronise logs admin folder
	sync_files;

	# Go through the server array 
	i=0;
        for datacentre in ${s[@]}; do
        	((i++))
        	nagios_host=${u[$i]};
		userpass=${up[$i]}

		# Check to see if the current nagios host matches this host
		# if it does no point in script checking itself and trying to take over its own config
		if [[ $nagios_host =~ $hostname ]]; then 
			echo "$nagios_host matches $hostname ignoring $datacentre"
		else

				check_url;
				if [[ $URL_WORKING -eq 0  ]]; then
				# Sleep for random seconds between 30-40 seconds to ensure 
				# there is no overlap between multiple nagios servers
				echo "Sleeping for $FAILOVER_TIME"
				sleep $FAILOVER_TIME
				echo "Checking URL Again";
				check_url;
				if [[ $URL_WORKING -eq 0 ]]; then
					# Now sync files again to ensure one Datacentre has not already taken over
					# synchronise logs admin folder
					sync_files;


					# Check to see if $datacentre is already in the status log file
					grep $datacentre $status_file > /dev/null
					# Exit code 0 - then it was found in status file
	  				if [ $? = 0 ]; then
						# return which host took over 
						thishost=$(grep $datacentre $status_file|awk '{print $2}')
						#random_file=$(grep $datacentre $status_file|awk '{print $3}')
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
							$sudo_cmd chown :nagios $conf_backup/nagios.cfg.$RAND
							# store environemnt current host running script and the random id to status file
							echo "$datacentre $hostname $RAND" >> $status_file

							# Add the extra config to this nagios.cfg
							config="# $datacentre servers - services\ncfg_dir=/etc/nagios/objects/$company/$datacentre"
							content=$(echo -e $config)
							line=$(grep -n "# AUTOMATION ADD HERE" $config_file|awk -F":" '{print $1}')
							# Above gets it all ready below adds entry
							edit=$($sudo_cmd ed -s $config_file << EOF
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
							# Restart nagios
							restart_nag
						fi
					fi
				else
					msg=msg" Datacenter URL has recovered"
				fi
			else

				# This else is where the nagios url was ok and running
				echo "$datacentre Nagios ok"
		
				# Check to see if config is in current config
				grep "$company/$datacentre" $config_file > /dev/null
				# status was 0 which means it was found
                		if [ $? = 0 ]; then
					# Look for the random id in the status file that matches current env and this hostname
					random_file=$(grep "$datacentre $hostname" $status_file|awk '{print $3}')
					# If it was found
					if [ "$random_file" != "" ]; then
						# Update email message 
						msg=$msg" Environment: $datacentre had been added to $status_file and exists in $config_file - resetting to correct configuration \n"
						# check to see if the actual file exists in shared mount point config backup folder
						if [ -f $conf_backup/nagios.cfg.$random_file ]; then 
							# Found the file so move it back
							msg=$msg" Moving  $conf_backup/nagios.cfg.$random_file as $config_file \n"
							$sudo_cmd mv $conf_backup/nagios.cfg.$random_file $config_file
							$sudo_cmd chown nagios:nagios $config_file
						else
							# Otherwise something has gone wrong so copy the nagios.cfg.master over nagios.cfg
							msg=$msg" Could not find $conf_backup/nagios.cfg.$random_file - copying $master_file to $config_file \n";
							cp $master_file $config_file
							$sudo_cmd chown nagios:nagios $config_file
						fi
						# Now clean up the status.log file and remove this entry 
						msg=$msg" Removing $datacentre $hostname $random_file from $status_file \n"
						grep -v "$datacentre $hostname $random_file"  $status_file > $tmp_status
						mv $tmp_status $status_file 
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
