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

is_command() {
    # Checks to see if the given command (passed as a string argument) exists on the system.
    # The function returns 0 (success) if the command exists, and 1 if it doesn't.
    local check_command="$1"

    command -v "${check_command}" >/dev/null 2>&1
}

################# START ARGON ONE CONFIG #################

argon_create_file() {
    if [ -f "$1" ]; then
        rm "$1"
    fi
    touch "$1"
    chmod 666 "$1"
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
                printf "%b  %b Checking for %s\\n (will be installed)\\n" "${OVER}" "${INFO}" "${i}"
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
                printf "  %b %s..." "${INFO}" "No user specified, but only ${install_user} is available, using it"
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

#!/bin/bash

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
    tmpconfig = load_config("'$daemonconfigfile'")
    if len(tmpconfig) > 0:
        fanconfig = tmpconfig
    address=0x1a
    prevblock=0
    while True:


# NOTE(cme): AFAIK vcgencmd is not available on ubuntu, so use sysfs instead
#     temp = os.popen("vcgencmd measure_temp").readline()
#     temp = temp.replace("temp=","")
#     val = float(temp.replace("'"'"'C",""))

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

#!/usr/bin/env bash
echo "-------------------------"
echo "Argon One Uninstall Tool"
echo "-------------------------"
echo -n "Press Y to continue:"
read -n 1 confirm
echo
if [ "$confirm" = "y" ]
then
    confirm="Y"
fi

if [ "$confirm" != "Y" ]
then
    echo "Cancelled"
    exit
fi

echo "if [ -d "$desktop" ]; then
echo "  sudo rm \"$desktop/argonone-config.desktop\"
echo "  sudo rm \"$desktop/argonone-uninstall.desktop\"

fi
if [ -f '$powerbuttonscript' ]; then
    systemctl stop '$daemonname'.service
    systemctl disable '$daemonname'.service
    /usr/bin/python3 '$shutdownscript' uninstall
    rm '$powerbuttonscript >> $removescript
    rm '$shutdownscript >> $removescript
    rm '$removescript >> $removescript
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
#!/bin/bash'
daemonconfigfile="/etc/$daemonname.conf"
echo "--------------------------------------"
echo "Argon One Fan Speed Configuration Tool"
echo "--------------------------------------"
echo "WARNING: This will remove existing configuration."
echo -n "Press Y to continue:"
read -n 1 confirm

if [ "$confirm" = "y" ]
then
    confirm="Y"
fi

if [ "$confirm" != "Y" ]
then
    echo "Cancelled"
    exit
fi
echo "Thank you."

get_number(){
    read curnumber
    re="^[0-9]+$"
    if [ -z "$curnumber" ]
    then
        echo "-2"
        return
    elif [[ $curnumber =~ ^[+-]?[0-9]+$ ]]
    then
        if [ $curnumber -lt 0 ]
        then
            echo "-1"
            return
        elif [ $curnumber -gt 100 ]
        then
            echo "-1"
            return
        fi  
        echo $curnumber
        return
    fi
    echo "-1"
    return
}


loopflag=1
while [ $loopflag -eq 1 ]
do
    
    echo "Select fan mode:"
    echo "  1. Always on"
    echo "  2. Adjust to temperatures (55C, 60C, and 65C)"
    echo "  3. Customize behavior"
    echo "  4. Cancel"
    echo "NOTE: You can also edit $daemonconfigfile directly"
    echo -n "Enter Number (1-4):"
    newmode=$( get_number )
    if [[ $newmode -ge 1 && $newmode -le 4 ]]
    then
        loopflag=0
    fi
done


if [ $newmode -eq 4 ]
then
    echo "Cancelled"
    exit
elif [ $newmode -eq 1 ]
then
    echo "#" > $daemonconfigfile
    echo "# Argon One Fan Speed Configuration" >> $daemonconfigfile
    echo "#" >> $daemonconfigfile
    echo "# Min Temp=Fan Speed" >> $daemonconfigfile
    echo 1"="100 >> $daemonconfigfile
    sudo systemctl restart '$daemonname'.service
    echo "Fan always on."
    exit
elif [ $newmode -eq 2 ]
then
    echo "Please provide fan speeds for the following temperatures:"
    echo "#" > $daemonconfigfile
    echo "# Argon One Fan Speed Configuration" >> $daemonconfigfile
    echo "#" >> $daemonconfigfile
    echo "# Min Temp=Fan Speed" >> $daemonconfigfile
    curtemp=55
    while [ $curtemp -lt 70 ]
    do
        errorfanflag=1
        while [ $errorfanflag -eq 1 ]
        do
            echo -n ""$curtemp"C (0-100 only):"
            curfan=$( get_number )
            if [ $curfan -ge 0 ]
            then
                errorfanflag=0
            fi
        done
        echo $curtemp"="$curfan >> $daemonconfigfile
        curtemp=$((curtemp+5))
    done

    systemctl restart $daemonname.service
    echo "Configuration updated."
    exit
fi

echo "Please provide fan speeds and temperature pairs"

loopflag=1
paircounter=0
while [ $loopflag -eq 1 ]
do
    errortempflag=1
    errorfanflag=1
    while [ $errortempflag -eq 1 ]
    do
        echo -n "Provide minimum temperature (in Celsius) then [ENTER]:"
        curtemp=$( get_number )
        if [ $curtemp -ge 0 ]
        then
            errortempflag=0
        elif [ $curtemp -eq -2 ]
        then
            errortempflag=0
            errorfanflag=0
            loopflag=0
        fi
    done
    while [ $errorfanflag -eq 1 ]
    do
        echo -n "Provide fan speed for "$curtemp"C (0-100) then [ENTER]:"
        curfan=$( get_number )
        if [ $curfan -ge 0 ]
        then
            errorfanflag=0
        elif [ $curfan -eq -2 ]
        then
            errortempflag=0
            errorfanflag=0
            loopflag=0
        fi
    done
    if [ $loopflag -eq 1 ]
    then
        if [ $paircounter -eq 0 ]
        then
            echo "#" > $daemonconfigfile
            echo "# Argon One Fan Speed Configuration" >> $daemonconfigfile
            echo "#" >> $daemonconfigfile
            echo "# Min Temp=Fan Speed" >> $daemonconfigfile
        fi
        echo $curtemp"="$curfan >> $daemonconfigfile
        
        paircounter=$((paircounter+1))
        
        echo "* Fan speed will be set to "$curfan" once temperature reaches "$curtemp" C"
        echo
    fi
done

echo
if [ $paircounter -gt 0 ]
then
    echo "Thank you!  We saved "$paircounter" pairs."
    systemctl restart $daemonname.service
    echo "Changes should take effect now."
else
    echo "Cancelled, no data saved."
fi

chmod 755 $configscript

configscript
)

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

	chooseUser
    echo "-----------------------------------------------------"
local str="Configuring ArgonOne Case Script to Ubuntu"
    printf "  %b %s...\\n" "${INFO}" "${str}" 
    sleep 6
    printf "  %b %s...\\n" "${INFO}" "Step 1 - Installing necessary dependencies"
    install_dependent_packages ${PKGLISTS[@]}
    
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

if [[ "${PH_TEST}" != true ]] ; then
    argon_script "$@"
fi

################# END ARGON ONE CONFIG #################