#!/usr/bin/env bash

set -e

#This script install and configure LAMP um Raspberry PI.
#Developed and tested only in Ubuntu 20.04.3 LTS (Focal Fossa).
#Others distros are not has been test. Use in your risk.

#Exporting DebconfNoninteractive resources 
export DEBIAN_FRONTEND="noninteractive"

#Script Configurations
#Table collors
    # Set these values so the installer can still run in color
    COL_NC='\e[0m' # No Color
    COL_LIGHT_GREEN='\e[1;32m'
    COL_LIGHT_RED='\e[1;31m'
    TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
    CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
    INFO="[i]"
    # shellcheck disable=SC2034
    DONE="${COL_LIGHT_GREEN} done!${COL_NC}"
    OVER="\\r\\033[K"

##Variables
	#
    PKG_MANAGER="apt-get"
    UPDATE_PKG_CACHE="${PKG_MANAGER} update"
	UPGRADE_PKG="${PKG_MANAGER} upgrade -y"
	PKG_INSTALL=("${PKG_MANAGER}" -qq --no-install-recommends install)
	PKG_COUNT="${PKG_MANAGER} -s -o Debug::NoLocking=true upgrade | grep -c ^Inst || true"
	LAMP=(apache2 php mariadb-server php-mysql language-pack-gnome-pt language-pack-pt-base)
	phpmyadmin=(phpmyadmin)
	PKG_CACHE="/var/lib/apt/lists/"
	ARGONONE='https://raw.githubusercontent.com/meuter/argon-one-case-ubuntu-20.04/master/argon1.sh'
##Taskel Variables
TASKEL_INSTALL="samba-server"
CMD_TASKEL="tasksel install"
SMB_FOLDER="/etc/samba/"
SMB="smb.conf"

#------------------#

#Config Functions

is_command() {
    # Checks to see if the given command (passed as a string argument) exists on the system.
    # The function returns 0 (success) if the command exists, and 1 if it doesn't.
    local check_command="$1"

    command -v "${check_command}" >/dev/null 2>&1
}

smb_Server(){

install_dependent_packages "tasksel"
tasksel install samba-server

#Security copy to smb config file
	cp "${SMB_FOLDER}""${SMB}" "${SMB_FOLDER}""${SMB}.backup" 
	bash -c 'grep -v -E "^#|^;" /etc/samba/smb.conf.backup | grep . > /etc/samba/smb.conf'
	
	smbpasswd -a ${install_user}
#Add config in smb.conf

echo '[WWW]' >> /etc/samba/smb.conf
echo 'comment = WWW folder' >> /etc/samba/smb.conf
echo 'path = /var/www/html' >> /etc/samba/smb.conf
echo 'browseable = yes' >> /etc/samba/smb.conf
echo 'read only = no' >> /etc/samba/smb.conf
echo 'writable = yes' >> /etc/samba/smb.conf	

chown -R ${install_user}:${install_user} /var/www/html
systemctl restart smbd

    local str="Restarting smb service..."
    printf "  %b %s..." "${INFO}" "${str}"
    # Create a command from the package cache variable
    if systemctl restart smbd &> /dev/null; then
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    else
        # Otherwise, show an error and exit
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        printf "  %bError: Unable to restart samba service. Please restart system"${COL_NC}""
        return 1
    fi
    
#Overclock Rpi4 Ubuntu
UBUNTU=$(lsb_release -ds)
	if ["$USUARIO" == "Ubuntu 20.04.3 LTS"]; then
	str="Wait a minute... The system will be configured to overclock 2,0GHz".
	sleep 3
		echo "over_voltage=8" >> /boot/firmware/config.txt
		echo "arm_freq=2147" >> /boot/firmware/config.txt
		echo "gpu_freq=750" >> /boot/firmware/config.txt
		printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
	else
		str="This system is not Ubuntu, or the version not Ubuntu 20.04.3 LTS. Skipping Overclock RPI."
			# Otherwise, show an error and exit
		printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
		return 1
	fi
	

}

install_dependent_packages() {

    # Install packages passed in via argument array
    # No spinner - conflicts with set -e
    declare -a installArray

    # Debian based package install - debconf will download the entire package list
    # so we just create an array of packages not currently installed to cut down on the
    # amount of download traffic.
    # NOTE: We may be able to use this installArray in the future to create a list of package that were
    # installed by us, and remove only the installed packages, and not the entire list.
    if is_command apt-get ; then
        # For each package, check if it's already installed (and if so, don't add it to the installArray)
        for i in "$@"; do
            printf "  %b Checking for %s..." "${INFO}" "${i}"
            if dpkg-query -W -f='${Status}' "${i}" 2>/dev/null | grep "ok installed" &> /dev/null; then
                printf "%b  %b Checking for %s\\n" "${OVER}" "${TICK}" "${i}"
            else
                printf "%b  %b Checking for %s (will be installed)\\n" "${OVER}" "${INFO}" "${i}"
                installArray+=("${i}")
            fi
        done
        # If there's anything to install, install everything in the list.
        if [[ "${#installArray[@]}" -gt 0 ]]; then
            test_dpkg_lock
            printf "  %b Processing %s install(s) for: %s, please wait...\\n" "${INFO}" "${PKG_MANAGER}" "${installArray[*]}"
            printf '%*s\n' "$columns" '' | tr " " -;
            "${PKG_INSTALL[@]}" "${installArray[@]}"
            printf '%*s\n' "$columns" '' | tr " " -;
            return
        fi
        printf "\\n"
        return 0
    fi
}

    # This function waits for dpkg to unlock, which signals that the previous apt-get command has finished.
test_dpkg_lock() {
        i=0
        # fuser is a program to show which processes use the named files, sockets, or filesystems
        # So while the lock is held,
        while fuser /var/lib/dpkg/lock >/dev/null 2>&1
        do
            # we wait half a second,
            sleep 0.5
            # increase the iterator,
            ((i=i+1))
        done
        # and then report success once dpkg is unlocked.
        return 0
}

update_package_cache_old() {
    # Running apt-get update/upgrade with minimal output can cause some issues with
    # requiring user input (e.g password for phpmyadmin see #218)

    # Update package cache on apt based OSes. Do this every time since
    # it's quick and packages can be updated at any time.

    # Local, named variables
    local str="Update local cache of available packages"
    printf "  %b %s..." "${INFO}" "${str}"
    # Create a command from the package cache variable
    if eval "${UPDATE_PKG_CACHE}" &> /dev/null; then
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    else
        # Otherwise, show an error and exit
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        printf "  %bError: Unable to update package cache. Please try \"%s\"%b" "${COL_LIGHT_RED}" "sudo ${UPDATE_PKG_CACHE}" "${COL_NC}"
        return 1
    fi
}




notify_package_updates_available() {
    # Local, named variables
    local str="Checking ${PKG_MANAGER} for upgraded packages"
    printf "\\n  %b %s..." "${INFO}" "${str}"
    # Store the list of packages in a variable
    updatesToInstall=$(eval "${PKG_COUNT}")

        if [[ "${updatesToInstall}" -eq 0 ]]; then
            printf "%b  %b %s... up to date!\\n\\n" "${OVER}" "${TICK}" "${str}"
        else
			
		if eval "${UPGRADE_PKG}"; then
		local str='Wait... Updating System.'
			printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
		else
			# Otherwise, show an error and exit
			printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
			printf "  %bError: Unable to update package cache. Please try \"%s\"%b" "${COL_LIGHT_RED}" "sudo ${UPDATE_PKG_CACHE}" "${COL_NC}"
			return 1
		fi

        fi
}

DebConfphp(){

	echo "phpmyadmin phpmyadmin/internal/skip-preseed boolean true" | debconf-set-selections
	echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
	echo "phpmyadmin phpmyadmin/app-password-confirm password l30n40" | debconf-set-selections
	echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
	echo "phpmyadmin phpmyadmin/mysql/admin-user string root" | debconf-set-selections
	echo "phpmyadmin phpmyadmin/mysql/admin-pass password l30n40" | debconf-set-selections
	echo "phpmyadmin phpmyadmin/mysql/app-pass password l30n40" | debconf-set-selections

}

create_users(){
#Create user main TO PHPMYADMIN
	mysql --user=root -e "create user admin@localhost identified by 'l30n40';"
	mysql --user=root -e "grant all privileges on *.* to admin@localhost;"
	mysql --user=root -e "FLUSH PRIVILEGES;"

#create real admin user
	mysql --user=root -e "CREATE USER 'radmin'@'localhost' IDENTIFIED BY 'l30n40';"
	mysql --user=root -e "GRANT ALL PRIVILEGES ON *.* TO 'radmin'@'localhost' WITH GRANT OPTION;"
	mysql --user=root -e "FLUSH PRIVILEGES;"
}

update_package_cache() {
	local str="Update local cache of available packages"

  #Running apt-get update/upgrade with minimal output can cause some issues with
  #requiring user input

  #Check to see if apt-get update has already been run today
  #it needs to have been run at least once on new installs!
  timestamp=$(stat -c %Y ${PKG_CACHE})
  timestampAsDate=$(date -d @"${timestamp}" "+%b %e")
  today=$(date "+%b %e")


  if [ ! "${today}" == "${timestampAsDate}" ]; then
		#update package lists
	printf "  %b %s..." "${INFO}" "${str}"
    # Create a command from the package cache variable
    if eval "${UPDATE_PKG_CACHE}" &> /dev/null; then
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    else
        # Otherwise, show an error and exit
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        printf "  %bError: Unable to update package cache. Please try \"%s\"%b" "${COL_LIGHT_RED}" "sudo ${UPDATE_PKG_CACHE}" "${COL_NC}"
        return 1
    fi


  fi
}


chooseUser(){
		if [ -z "$install_user" ]; then
			if [ "$(awk -F':' 'BEGIN {count=0} $3>=1000 && $3<=60000 { count++ } END{ print count }' /etc/passwd)" -eq 1 ]; then
				install_user="$(awk -F':' '$3>=1000 && $3<=60000 {print $1}' /etc/passwd)"
				echo "::: No user specified, but only ${install_user} is available, using it"
			else
				echo "::: No user specified"
				exit 1
			fi
		else
			if awk -F':' '$3>=1000 && $3<=60000 {print $1}' /etc/passwd | grep -qw "${install_user}"; then
				echo "::: ${install_user} will hold your ovpn configurations."
			else
				echo "::: User ${install_user} does not exist, creating..."
				useradd -m -s /bin/bash "${install_user}"
				echo "::: User created without a password, please do sudo passwd $install_user to create one"
			fi
		fi
}

argon_script(){

sudo -u ${install_user} curl -sSL ${ARGONONE} | bash


}

main(){

   local str="Root user check"
    printf "\\n"

    # If the user's id is zero,
    if [[ "${EUID}" -eq 0 ]]; then
        # they are root and all is good
        printf "  %b %s\\n" "${TICK}" "${str}"
		update_package_cache || exit 1
		notify_package_updates_available
		
		
    else
        # Otherwise, they do not have enough privileges, so let the user know
        printf "  %b %s\\n" "${INFO}" "${str}"
        printf "  %b %bScript called with non-root privileges%b\\n" "${INFO}" "${COL_LIGHT_RED}" "${COL_NC}"
        printf "      Requires elevated privileges to install and run\\n"
        printf "      Please check the installer for any concerns regarding this requirement\\n"
        printf "      Make sure to download this script from a trusted source\\n\\n"
        printf "  %b Sudo utility check" "${INFO}"
		exit 1
        # If the sudo command exists, try rerunning as admin
        if is_command sudo ; then
            printf "%b  %b Sudo utility check\\n" "${OVER}"  "${TICK}"
		else
            printf "%b  %b Sudo utility check\\n" "${OVER}" "${CROSS}"
            printf "  %b Sudo is needed to install\\n\\n" "${INFO}"
            printf "  %b %bPlease re-run this installer as root${COL_NC}\\n" "${INFO}" "${COL_LIGHT_RED}"
            exit 1
			exit 1
		fi
	fi
	
	install_dependent_packages "${LAMP[@]}"
	mysql_secure_installation
	create_users
	
	#Configure debconf
	DebConfphp
		local str="restart apache service before install phpmyadmin"
		printf "  %b %s\\n" "${INFO}" "${str}"
		
		
		if service apache2 restart; then
			printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
		else
			printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
			printf "  %bError: Unable to restart service. Please try \"%s\"%b" "${COL_LIGHT_RED}" "sudo 'sudo service apache2 restart'" "${COL_NC}"
			return 1
		fi
		dpkg-reconfigure -f noninteractive locales
		install_dependent_packages "${phpmyadmin[@]}"
		
		chooseUser
		argon_script
#Install Samba Server

	smb_Server

 printf "%b  %b Wait. Overclocked and system will restart in 5 seconds.\\n" "${OVER}"  "${TICK}"
 sleep 5
 reboot now
	
}

if [[ "${PH_TEST}" != true ]] ; then
    main "$@"
fi
