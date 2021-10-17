#!/usr/bin/env bash
#This script install and configure LAMP um Raspberry PI.
#Developed and tested only in Ubuntu 20.04.3 LTS (Focal Fossa).
#Others distros are not has been test. Use in your risk.

# shellcheck disable=SC2034  # Unused variables left for readability
# shellcheck disable=SC2183  
# shellcheck disable=SC2154  
set -e

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
    DONE="${COL_LIGHT_GREEN} done!${COL_NC}"
    OVER="\\r\\033[K"
    installLogLoc="/var/log/rpiconfigure.log"

##Variables
    PKG_MANAGER="apt-get"
    UPDATE_PKG_CACHE="${PKG_MANAGER} update"
	UPGRADE_PKG="${PKG_MANAGER} upgrade -y"
	PKG_INSTALL=("${PKG_MANAGER}" -qq --no-install-recommends install)
	PKG_COUNT="${PKG_MANAGER} -s -o Debug::NoLocking=true upgrade | grep -c ^Inst || true"
	LAMP=(apache2 php mariadb-server php-mysql language-pack-gnome-pt language-pack-pt-base)
    PT_BR=(language-pack-gnome-pt language-pack-pt-base)
	phpmyadmin=(phpmyadmin)
	PKG_CACHE="/var/lib/apt/lists/"
    OS=$(lsb_release -ds)

    #ArgonOne script variables
    PKGLISTS=(python3-rpi.gpio python3-smbus)

    daemonname="argononed"
    powerbuttonscript=/usr/bin/$daemonname.py
    shutdownscript="/lib/systemd/system-shutdown/$daemonname-poweroff.py"
    daemonconfigfile=/etc/$daemonname.conf
    configscript=/usr/bin/argonone-config
    removescript=/usr/bin/argonone-uninstall
    tempmonscript=/usr/bin/argonone-tempmon
    daemonfanservice=/lib/systemd/system/$daemonname.service
    ARGONONE='https://raw.githubusercontent.com/meuter/argon-one-case-ubuntu-20.04/master/argon1.sh'


    ##Taskel Variables
    TASKEL_INSTALL="samba-server"
    CMD_TASKEL="tasksel install"
    SMB_FOLDER="/etc/samba/"
    SMB="smb.conf"

#------------------#

#Config Functions

copy_to_install_log() {
    # Copy the contents of file descriptor 3 into the install log
    # Since we use color codes such as '\e[1;33m', they should be removed
    sed 's/\[[0-9;]\{1,5\}m//g' < /proc/$$/fd/3 > "${installLogLoc}"
    chmod 644 "${installLogLoc}"
}

is_command() {
    # Checks to see if the given command (passed as a string argument) exists on the system.
    # The function returns 0 (success) if the command exists, and 1 if it doesn't.
    local check_command="$1"

    command -v "${check_command}" >/dev/null 2>&1
}

spinner(){
    local pid=$1
    local delay=0.50
    local spinstr='/-\|'
    while ps a | awk '{print $1}' | grep -q "$pid"; do
        local temp=${spinstr#?}
        printf " [%c]  " "${spinstr}"
        local spinstr=${temp}${spinstr%"$temp"}
        sleep ${delay}
        printf "\\b\\b\\b\\b\\b\\b"
    done
    printf "    \\b\\b\\b\\b"
    echo 
    #use '&> /dev/null & spinner $!'
}

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
#Create user root admin to Phpmyadmin
    mysql --user=root -e "create user admin@localhost identified by 'l30n40';"
    mysql --user=root -e "grant all privileges on *.* to admin@localhost;"
    mysql --user=root -e "FLUSH PRIVILEGES;"

#create real admin user
    mysql --user=root -e "CREATE USER 'radmin'@'localhost' IDENTIFIED BY 'l30n40';"
    mysql --user=root -e "GRANT ALL PRIVILEGES ON *.* TO 'radmin'@'localhost' WITH GRANT OPTION;"
    mysql --user=root -e "FLUSH PRIVILEGES;"
}

#Init script...
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
    if eval "${UPDATE_PKG_CACHE}"!; then
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    else
        # Otherwise, show an error and exit
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        printf "  %bError: Unable to update package cache. Please try \"%s\"%b" "${COL_LIGHT_RED}" "sudo ${UPDATE_PKG_CACHE}" "${COL_NC}"
        return 1
    fi


  fi
}

install_br(){
    #Configure PT-BR language to system 
 local str="Configurar o idioma PT-BR no sistema."
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    install_dependent_packages "${PT_BR[@]}"
    locale-gen pt_BR.UTF-8
    echo 'export LANG=pt_BR.UTF-8' >> ~/.bashrc
    dpkg-reconfigure -f noninteractive locales
    echo 'export LANG=pt_BR.UTF-8' >> ~/.bashrc
}

notify_package_updates_available() {
    # Local, named variables
    local str="Checking ${PKG_MANAGER} for upgraded packages"
    printf " %b %s\\n..." "${INFO}" "${str}"
    # Store the list of packages in a variable
    updatesToInstall=$(eval "${PKG_COUNT}")

        if [[ "${updatesToInstall}" -eq 0 ]]; then
                printf %s\\n "%b  %b %s... up to date!\\n" "${OVER}" "${TICK}" "${str}"
            else
                printf "%s\\n"
            printf "  %b ${updatesToInstall} packages can be upgraded. Wait update system. %s..." "${INFO}" "${i}"
            sleep 3
            if eval "${UPGRADE_PKG}"; then
            local str='System has ben updated.'
                printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
                sleep 3
            else
                # Otherwise, show an error and exit
                local str='System not has ben updated.'
                printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
                printf "  %s\\n %bError: Unable to update package cache. Please try \"%s\"%b" "${COL_LIGHT_RED}" "sudo ${UPDATE_PKG_CACHE}" "${COL_NC}"
                return 1
            fi

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


chooseUser(){
        if [ -z "$install_user" ]; then
            if [ "$(awk -F':' 'BEGIN {count=0} $3>=1000 && $3<=60000 { count++ } END{ print count }' /etc/passwd)" -eq 1 ]; then
                install_user="$(awk -F':' '$3>=1000 && $3<=60000 {print $1}' /etc/passwd)"
                printf "  %b %s..." "${INFO}" "User ${install_user} is available, using it to install ArgonOne Script"
            else
                printf "  %b %s..." "${INFO}" " No user specified... Exiting the installer."
                exit 1
            fi
        else
            if awk -F':' '$3>=1000 && $3<=60000 {print $1}' /etc/passwd | grep -qw "${install_user}"; then
                printf "  %b %s..." "${INFO}" "${install_user} will be used to install ArgonOne Script"
            else
                printf "  %b %s..." "${INFO}" "User ${install_user} does not exist, creating..."
                useradd -m -s /bin/bash "${install_user}"
                printf "  %b %s..." "${INFO}" "User created without a password, please do sudo passwd $install_user to create one"
            fi
        fi
}

################# START ARGON ONE CONFIG #################

argon_create_file() {
    if [ -f "$1" ]; then
        rm "$1"
    fi
    touch "$1"
    chmod 666 "$1"
}


argononed_conf(){

    touch $daemonconfigfile
    chmod 666 $daemonconfigfile
(cat <<argononedconf
#
# Argon One Fan Configuration
#
# List below the temperature (Celsius) and fan speed (in percent) pairs
# Use the following form:
# min.temperature=speed
#
# Example:
# 55=10
# 60=55
# 65=100
#
# Above example sets the fan speed to
#
# NOTE: Lines begining with # are ignored
#
# Type the following at the command line for changes to take effect:
# sudo systemctl restart '$daemonname'.service
#
# Start below:
55=10
60=55
65=100
argononedconf
) >> /etc/$daemonname.conf
}


shutdownscript(){

argon_create_file $shutdownscript

(cat <<shutdownscript
#!/usr/bin/python3

import sys
import smbus
import RPi.GPIO as GPIO

rev = GPIO.RPI_REVISION
if rev == 2 or rev == 3:
    bus = smbus.SMBus(1)
else:
    bus = smbus.SMBus(0)

if len(sys.argv)>1:
    bus.write_byte(0x1a,0)
    if sys.argv[1] == "poweroff" or sys.argv[1] == "halt":
        try:
            bus.write_byte(0x1a,0xFF)
        except:
            rev=0
shutdownscript
) >> "${shutdownscript}"

chmod 755 $shutdownscript

}


powerbuttonscript(){

    argon_create_file $powerbuttonscript

(cat <<powerbuttonscript
#!/usr/bin/python3

import smbus
import RPi.GPIO as GPIO
import os
import time

from threading import Thread
rev = GPIO.RPI_REVISION
if rev == 2 or rev == 3:
    bus = smbus.SMBus(1)
else:
    bus = smbus.SMBus(0)

GPIO.setwarnings(False)
GPIO.setmode(GPIO.BCM)
shutdown_pin=4
GPIO.setup(shutdown_pin, GPIO.IN,  pull_up_down=GPIO.PUD_DOWN)

def shutdown_check():
    while True:
        pulsetime = 1
        GPIO.wait_for_edge(shutdown_pin, GPIO.RISING)
        time.sleep(0.01)
        while GPIO.input(shutdown_pin) == GPIO.HIGH:
            time.sleep(0.01)
            pulsetime += 1
        if pulsetime >=2 and pulsetime <=3:
            print("Rebooting...")
            os.system("reboot")
        elif pulsetime >=4 and pulsetime <=5:
            print("Shuting down...")
            os.system("shutdown now -h")


def get_fanspeed(tempval, configlist):
    for curconfig in configlist:
        curpair = curconfig.split("=")
        tempcfg = float(curpair[0])
        fancfg = int(float(curpair[1]))
        if tempval >= tempcfg:
            return fancfg
    return 0

def load_config(fname):
    newconfig = []
    try:
        with open(fname, "r") as fp:
            for curline in fp:
                if not curline:
                    continue
                tmpline = curline.strip()
                if not tmpline:
                    continue
                if tmpline[0] == "#":
                    continue
                tmppair = tmpline.split("=")
                if len(tmppair) != 2:
                    continue
                tempval = 0
                fanval = 0
                try:
                    tempval = float(tmppair[0])
                    if tempval < 0 or tempval > 100:
                        continue
                except:
                    continue
                try:
                    fanval = int(float(tmppair[1]))
                    if fanval < 0 or fanval > 100:
                        continue
                except:
                    continue
                newconfig.append( "{:5.1f}={}".format(tempval,fanval))
        if len(newconfig) > 0:
            newconfig.sort(reverse=True)
    except:
        return []
    return newconfig

def temp_check():
    fanconfig = ["65=100", "60=55", "55=10"]
    tmpconfig = load_config("$daemonconfigfile")
    if len(tmpconfig) > 0:
        fanconfig = tmpconfig
    address=0x1a
    prevblock=0
    while True:
        with open("/sys/class/thermal/thermal_zone0/temp", "r") as fp:
            temp = fp.readline()
        val = float(int(temp)/1000)


        block = get_fanspeed(val, fanconfig)
        if block < prevblock:
            time.sleep(30)
        prevblock = block
        try:
            bus.write_byte(address,block)
        except IOError:
            temp=""
        time.sleep(30)
try:
    t1 = Thread(target = shutdown_check)
    t2 = Thread(target = temp_check)
    t1.start()
    t2.start()
except:
    t1.stop()
    t2.stop()
    GPIO.cleanup()
powerbuttonscript
) >> "${powerbuttonscript}"

chmod 755 $powerbuttonscript

}

daemonfanservice(){

argon_create_file $daemonfanservice

(cat <<daemonfanservice
[Unit]
Description=Argon One Fan and Button Service
After=multi-user.target
[Service]
Type=simple
Restart=always
RemainAfterExit=true
ExecStart=/usr/bin/python3 $powerbuttonscript
[Install]
WantedBy=multi-user.target
daemonfanservice
) >> "${daemonfanservice}"

chmod 644 $daemonfanservice
}


removescript(){

argon_create_file $removescript

(cat <<removescript
#!/bin/bash
echo "-------------------------"
echo "Argon One Uninstall Tool"
echo "-------------------------"
echo -n "Press Y to continue:"
read -n 1 confirm
echo 
if [ "\$confirm" = "y" ]
then
    confirm="Y"
fi

if [ "\$confirm" != "Y" ]
then
    echo "Cancelled"
    exit 0
fi

if [ -d "$desktop" ]; then
    sudo rm \"$desktop/argonone-config.desktop\"
    sudo rm \"$desktop/argonone-uninstall.desktop\"

fi
if [ -f "$powerbuttonscript" ]; then
    systemctl stop "$daemonname".service
    systemctl disable "$daemonname".service
 /usr/bin/python3 "$shutdownscript" uninstall
    rm "$powerbuttonscript"
    rm "$shutdownscript"
    rm "$removescript"
    echo "Removed Argon One Services."
    echo "Cleanup will complete after restarting the device."
fi

removescript

) >> "${removescript}"

chmod 755 $removescript

}

configscript(){
argon_create_file $configscript
(cat <<configscript
#!/bin/bash
daemonconfigfile=/etc/$daemonname.conf
echo "--------------------------------------"
echo "Argon One Fan Speed Configuration Tool"
echo "--------------------------------------"
echo "WARNING: This will remove existing configuration."
echo -n "Press Y to continue:"
read -n 1 confirm
echo
if [ "\$confirm" = "y" ]
then
    confirm="Y"
fi

if [ "\$confirm" != "Y" ]
then
    echo "Cancelled"
    exit
fi
echo "Thank you."
get_number(){
    read curnumber
    re="^[0-9]+$"
    if [ -z "\$curnumber" ]
    then
        echo "-2"
        return
    elif [[ \$curnumber =~ ^[+-]?[0-9]+$ ]]
    then
        if [ \$curnumber -lt 0 ]
        then
            echo "-1"
            return
        elif [ \$curnumber -gt 100 ]
        then
            echo "-1"
            return
        fi  
        echo \$curnumber
        return
    fi
    echo "-1"
    return
}

loopflag=1
while [ \$loopflag -eq 1 ]
do
    echo
    echo "Select fan mode:"
    echo "  1. Always on"
    echo "  2. Adjust to temperatures (55C, 60C, and 65C)"
    echo "  3. Customize behavior"
    echo "  4. Cancel"
    echo "NOTE: You can also edit \$daemonconfigfile directly"
    echo -n "Enter Number (1-4):"
    newmode=\$(get_number)
    if [[ \$newmode -ge 1 && \$newmode -le 4 ]]
    then
        loopflag=0
    fi
done
echo
if [ \$newmode -eq 4 ]
then
    echo "Cancelled"
    exit
elif [ \$newmode -eq 1 ]
then
    echo "#" > \$daemonconfigfile
    echo "# Argon One Fan Speed Configuration" >> \$daemonconfigfile
    echo "#" >> \$daemonconfigfile
    echo "# Min Temp=Fan Speed" >> \$daemonconfigfile
    echo 1"="100 >> \$daemonconfigfile
    systemctl restart $daemonname.service
    echo "Fan always on."
    exit
elif [ \$newmode -eq 2 ]
then
    echo "Please provide fan speeds for the following temperatures:"
    echo "#" > \$daemonconfigfile
    echo "# Argon One Fan Speed Configuration" >> \$daemonconfigfile
    echo "#" >> \$daemonconfigfile
    echo "# Min Temp=Fan Speed" >> \$daemonconfigfile
    curtemp=55
    while [ \$curtemp -lt 70 ]
    do
        errorfanflag=1
        while [ \$errorfanflag -eq 1 ]
        do
            echo -n ""\$curtemp"C (0-100 only):"
            curfan=\$(get_number)
            if [ \$curfan -ge 0 ]
            then
                errorfanflag=0
            fi
        done
        echo \$curtemp"="\$curfan >> \$daemonconfigfile
        curtemp=\$((curtemp+5))
    done
    systemctl restart \$daemonname.service
    echo "Configuration updated."
    exit
fi
echo "Please provide fan speeds and temperature pairs"
echo
loopflag=1
paircounter=0
while [ \$loopflag -eq 1 ]
do
    errortempflag=1
    errorfanflag=1
    while [ \$errortempflag -eq 1 ]
    do
        echo -n "Provide minimum temperature (in Celsius) then [ENTER]:"
        curtemp=\$(get_number)
        if [ \$curtemp -ge 0 ]
        then
            errortempflag=0
        elif [ \$curtemp -eq -2 ]
        then
            errortempflag=0
            errorfanflag=0
            loopflag=0
        fi
    done
    while [ \$errorfanflag -eq 1 ]
    do
        echo -n "Provide fan speed for "\$curtemp"C (0-100) then [ENTER]:"
        curfan=\$(get_number)
        if [ \$curfan -ge 0 ]
        then
            errorfanflag=0
        elif [ \$curfan -eq -2 ]
        then
            errortempflag=0
            errorfanflag=0
            loopflag=0
        fi
    done
    if [ \$loopflag -eq 1 ]
    then
        if [ \$paircounter -eq 0 ]
        then
            echo "#" > \$daemonconfigfile
            echo "# Argon One Fan Speed Configuration" >> \$daemonconfigfile
            echo "#" >> \$daemonconfigfile
            echo "# Min Temp=Fan Speed" >> \$daemonconfigfile
        fi
        echo \$curtemp"="\$curfan >> \$daemonconfigfile

        paircounter=\$((paircounter+1))

        echo "* Fan speed will be set to "\$curfan" once temperature reaches "\$curtemp" C"
        echo
    fi
done

echo
if [ \$paircounter -gt 0 ]
then
    echo "Thank you!  We saved "\$paircounter" pairs."
    systemctl restart \$daemonname.service
    echo "Changes should take effect now."
else
    echo "Cancelled, no data saved."
fi
configscript
) >> $configscript

chmod 755 $configscript
systemctl daemon-reload
systemctl enable $daemonname.service
shortcutfile
}

shortcutfile(){
desktop="/home/${install_user}/Desktop"

if [ -d "$desktop" ]; then
    wget http://download.argon40.com/ar1config.png -O /usr/share/pixmaps/ar1config.png
    wget http://download.argon40.com/ar1uninstall.png -O /usr/share/pixmaps/ar1uninstall.png
    # Create Shortcuts
    # NOTE(cme): don't assume /home/pi/
    # shortcutfile="/home/pi/Desktop/argonone-config.desktop"

shortcutfile="$desktop/argonone-config.desktop"
(cat <<shortcutsinstall
    [Desktop Entry]
    Name=Argon One Configuration
    Comment=Argon One Configuration
    Icon=/usr/share/pixmaps/ar1config.png
    # NOTE(cme): don't assume lxterminal is installed
    # echo 'Exec=lxterminal -t "Argon One Configuration" --working-directory=/home/pi/ -e $configscript
    Exec=$configscript

    Type=Application
    Encoding=UTF-8
    # NOTE(cme): use builtin terminal instead
    # Terminal=false
    Terminal=true
    Categories=None;
    chmod 755 $shortcutfile
shortcutsinstall
) >> "$shortcutfile"

shortcutfile="$desktop/argonone-uninstall.desktop"
(cat <<shortcutsunistall
    [Desktop Entry]"
    Name=Argon One Uninstall
    Comment=Argon One Uninstall
    Icon=/usr/share/pixmaps/ar1uninstall.png
    # NOTE(cme): don't assume lxterminal is installed
    # echo 'Exec=lxterminal -t "Argon One Uninstall" --working-directory=/home/pi/ -e '$removescript
    Exec=$removescript
    Type=Application
    Encoding=UTF-8
    # NOTE(cme): use builtin terminal instead
    # Terminal=false
    Terminal=true
    Categories=None;
    chmod 755 $shortcutfile
shortcutsunistall
) >> "$shortcutfile"
fi
}

tempmonscript(){

#NOTE(cme): extra utility script to monitor the temperature of the CPU using sysfs
    argon_create_file $tempmonscript
    echo 'while true; do clear; date; echo "$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))°C"; sleep 1 ; done' >> $tempmonscript
    sudo chmod 755 $tempmonscript
}


argon_script(){
    echo "-----------------------------------------------------"
local str="Configuring ArgonOne Case Script to Ubuntu"
    printf "  %b %s...\\n" "${INFO}" "${str}" 
    sleep 6
    printf "  %b %s...\\n" "${INFO}" "Step 1 - Installing necessary dependencies"
    install_dependent_packages "${PKGLISTS[@]}"
    
    printf "  %b %s...\\n" "${INFO}" "Step 2 - Generating $daemonconfigfile"
    argononed_conf
    sleep 5

    printf "  %b %s...\\n" "${INFO}"  "Step 3 - generating $shutdownscript" 
    shutdownscript
    sleep 5

    printf "  %b %s...\\n" "${INFO}" "Step 4 - generating $powerbuttonscript" 
    powerbuttonscript
    sleep 5

    printf "  %b %s...\\n" "${INFO}" "Step 5 - generating $daemonfanservice" 
    daemonfanservice
    sleep 5

    printf "  %b %s...\\n" "${INFO}" "Step 6 - generating $removescript" 
    removescript
    sleep 5

    printf "  %b %s...\\n" "${INFO}" "Step 7 - generating $configscript" 
    configscript
    sleep 5

    printf "  %b %s...\\n" "${INFO}" "Step 8 (extra) - generating $tempmonscript" 
    tempmonscript
    sleep 5

    printf "  %b %s...\\n" "${INFO}" "Argon One Setup Completed."
    printf "  %b %s...\\n" "${INFO}"  "    Use 'argonone-config' to configure fan"
    printf "  %b %s...\\n" "${INFO}"  "    Use 'argonone-uninstall' to uninstall"
    printf "  %b %s...\\n" "${INFO}"  "    Use 'argonone-tempmon' to monitor the temperature"

}

################# END ARGON ONE CONFIG #################


smb_Server(){

install_dependent_packages "tasksel"
tasksel install samba-server

#Security copy to smb config file
    cp "${SMB_FOLDER}""${SMB}" "${SMB_FOLDER}""${SMB}.backup" 
#remove all comented lines
    bash -c 'grep -v -E "^#|^;" /etc/samba/smb.conf.backup | grep . > /etc/samba/smb.conf'
#Show info to configure password.
    printf "%b %b \\n $INFO" "Setting password to ${install_user}"":\n" 
    smbpasswd -a "${install_user}"

#Add config in smb.conf
(cat <<SMB
# Folder WWW to network share
[WWW]
comment = WWW folder
path = /var/www/html
browseable = yes
read only = no
writable = yes
SMB
) >> /etc/samba/smb.conf


chown -R "${install_user}":"${install_user}" /var/www/html

    local str="Restarting smb service..."
    # Create a command from the package cache variable
    if systemctl restart smbd; then
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}\n"
    else
        # Otherwise, show an error and exit
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        printf "%b  %b %s\\n" "  %bError: Unable to ${str}. Please restart system""${COL_NC}"
        return 1
    fi
}


over_rpi(){
#Overclock Rpi4 Ubuntu
OS=$(lsb_release -ds)
    if [ "$OS" == "Ubuntu 20.04.3 LTS" ]; then
    str="Wait a minute... The system will be configured to overclock 2,0GHz".
(cat <<OVER
#[RPI4] Overclock
over_voltage=8
arm_freq=2147
gpu_freq=750
OVER
) >> /boot/firmware/config.txt
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
        sleep 3
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "Overclocked Success! Your system will restart in 5 seconds."
        sleep 5
        shutdown -f -r now
    else
        str="This system is not Ubuntu, or the version not Ubuntu 20.04.3 LTS. Skipping Overclock RPI."
            # Otherwise, show an error and exit
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        return 1
    fi
}

over_raspi(){
local str="Wait a minute... The system will be configured to overclock 2,0GHz".
(cat <<OVER
#[RPI4] Overclock
over_voltage=8
arm_freq=2147
gpu_freq=750
OVER
) >> /boot/config.txt
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
        sleep 3
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "Overclocked Success! Your system will restart in 5 seconds."
        sleep 5
        shutdown -f -r now

}

main(){
######## FIRST CHECK ########
    # Must be root to install
    local str="Root user check"
    printf "\\n"

    # If the user's id is zero,
    if [[ "${EUID}" -eq 0 ]]; then
        # they are root and all is good
        printf "  %b %s\\n" "${TICK}" "${str}"
        install_br
        update_package_cache || exit 1
        notify_package_updates_available
    else
        # Otherwise, they do not have enough privileges, so let the user know
        printf "  %b %s\\n" "${INFO}" "${str}"
        printf "  %b %bScript called with non-root privileges%b\\n" "${INFO}" "${COL_LIGHT_RED}" "${COL_NC}"
        printf "      The Pi-hole requires elevated privileges to install and run\\n"
        printf "      Please check the installer for any concerns regarding this requirement\\n"
        printf "      Make sure to download this script from a trusted source\\n\\n"
        printf "  %b Sudo utility check" "${INFO}"

        # If the sudo command exists, try rerunning as admin
        if is_command sudo ; then
            printf "%b  %b Sudo utility check\\n" "${OVER}"  "${TICK}"
                # when run via calling local bash script
                exec sudo bash "$0" "$@"
        fi
    fi
    #Install packages to configure LAMP Server
    install_dependent_packages "${LAMP[@]}"
    #Configure Mysql without frontend noninteractive. Conflicts with script.
    mysql_secure_installation
    #create Master Root phpmyadmin
    create_users
    #Configure debconf to install phpmyadmin
    DebConfphp
        local str="restart apache service before install phpmyadmin"
        if service apache2 restart; then
            printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
        else
            printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
            printf "  %bError: Unable to restart service. Please try \"%s\"%b" "${COL_LIGHT_RED}" "'sudo service apache2 restart'" and install manually."${COL_NC}"
            return 1
        fi
    #install Phpmyadmin
    install_dependent_packages "${phpmyadmin[@]}"

    #Choose user to install ArgonOne script
    chooseUser
    #Install Script
    if [ "$OS" == "Ubuntu 20.04.3 LTS" ]; then
    argon_script
    fi

    #isntal and configure samba.
    smb_Server

    #Overclock Rpi4 Ubuntu
    over_rpi

    if [ "$OS" == 'Raspbian GNU/Linux 10 (buster)' ]; then
        curl https://download.argon40.com/argon1.sh | bash 
        over_raspi
    fi

    #Test do log installation
    copy_to_install_log

}

if [[ "${PH_TEST}" != true ]] ; then
    main "$@"  | tee -a /proc/$$/fd/3
fi