#!/usr/bin/env bash

## Script dir
SELF=$(pwd)

## Find the dir.
cd ~/
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
USER="bibbox";

## Define the release file.
URL="https://github.com/bibboxen/bibbox/releases/download/v1.0.0-beta4/"
FILE="v1.0.0-beta4.tar.gz"
VERSION="v1.0.0-beta4"

## Define colors.
BOLD=$(tput bold)
UNDERLINE=$(tput sgr 0 1)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
RESET=$(tput sgr0)

## Check if install has been executed before.
if [ -e $DIR/bibbox ]
then
		echo "${BOLD}Directory ${UNDERLINE}${RED}${DIR}/bibbox${RESET}${BOLD} already exists. Please remove it before running this script${RESET}"
		echo
		echo "rm -fr $DIR/bibbox"
		echo
		exit
fi

## Set the IP (if static).
NETMASK="255.255.255.240"
GATEWAY="172.16.55.1"
CAST="172.16.55.255"
DNS1="10.150.4.201"
DNS2="10.150.4.202"

function set_ip {
 read -p "Enter IP: " IP

  sudo cat << DELIM >> ${DIR}/interfaces
auto lo
iface lo inet loopback
auto $1
iface $1 inet static
  address ${IP}
  netmask ${NETMASK}
  gateway ${GATEWAY}
  broadcast ${CAST}
  dns-nameservers ${DNS1} ${DNS2}
DELIM
  sudo mv interfaces /etc/network/interfaces

  sudo service networking restart
}

while true; do
    read -p "Do you wish to set static IP (y/n)? " yn
    case $yn in
        [Yy]* )
					echo "Select the interface to configure:"
					INTERFACES=$(nmcli -t --fields DEVICE dev)
					INTERFACES+=' Exit'
					select INTERFACE in ${INTERFACES};
					do
						case ${INTERFACE} in
							'Exit')
								break 2
								;;
							*)
								set_ip ${INTERFACE}
								break 2
								;;
						esac
					done
					break
					;;
        [Nn]* )
					break
					;;
        * ) echo "Please answer yes or no.";;
    esac
done

## Ensure system is up-to-date.
sudo apt-get update
sudo apt-get upgrade -y

## Add chrome to the box.
wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
sudo sh -c 'echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list'
sudo apt-get update
sudo apt-get install google-chrome-stable -y

## Get NodeJS.
wget -q -O - https://deb.nodesource.com/setup_6.x | sudo bash
sudo apt-get install nodejs -y

## Install tools.
sudo apt-get install build-essential libudev-dev openssh-server fail2ban -y

## Install usefull packages.
sudo apt-get install git supervisor redis-server -y

## Set udev rule for barcode.
sudo cat << DELIM >> ${DIR}/40-barcode.rules
# Rule for barcode

# 'libusb' device nodes
SUBSYSTEM=="usb", ATTR{idVendor}=="05f9", ATTR{idProduct}=="2206", GROUP="plugdev"

DELIM
sudo mv ${DIR}/40-barcode.rules /etc/udev/rules.d/40-barcode.rules

## Set udev rule for RFID.
sudo cat << DELIM >> ${DIR}/41-rfid.rules
# Rule for Feig Leser
# USB Leser

ACTION!="add", GOTO="feig_rules_end"
SUBSYSTEM!="usb", GOTO="feig_rules_end"

ATTR{product}=="OBID RFID-Reader", ATTR{manufacturer}=="FEIG ELECTRONIC GmbH", MODE:="666", GROUP="users", SYMLINK+="feig_\$ATTR{serial}"
LABEL="feig_rules_end"

DELIM
sudo mv ${DIR}/41-rfid.rules /etc/udev/rules.d/41-rfid.rules

## Add bibbox packages (use symlink to match later update process).
mkdir ${DIR}/${VERSION}/
wget -q ${URL}${FILE}
tar -zxf ${FILE} -C ${DIR}/${VERSION}/
rm -rf ${URL}${FILE}
ln -s ${DIR}/${VERSION}/ bibbox

cp ${SELF}/server.key ${DIR}/bibbox/
cp ${SELF}/server.crt ${DIR}/bibbox/

## Supervisor config
sudo cat << DELIM >> ${DIR}/bibbox.conf
[program:middleware]
command=/usr/bin/node /home/${USER}/bibbox/bootstrap.js
autostart=true
autorestart=true
environment=NODE_ENV=production
stderr_logfile=/var/log/supervisor/bibbox.err.log
stdout_logfile=/var/log/supervisor/bibbox.out.log
user=${USER}
DELIM

sudo mv ${DIR}/bibbox.conf /etc/supervisor/conf.d/bibbox.conf

# Fix supervisor install bug and ensure that it starts.
sudo systemctl enable supervisor
sudo systemctl start supervisor

## Add printer
sudo dpkg -i ${SELF}/epson/*.deb

tgtDir="/usr/share/ppd"
sudo mkdir -p "${tgtDir}/Epson"
sudo cp -p ${SELF}/epson/ppd/tm-* ${tgtDir}/Epson/
sudo chmod -f 644 ${tgtDir}/Epson/*

cat << DELIM >> ${DIR}/printers.conf
<DefaultPrinter EPSON-TM-m30>
  UUID urn:uuid:eb0f7db5-d579-3868-5f9c-21674e09f5bd
  Info EPSON TM-m30
  Location localhost
  MakeModel Epson TM BA Thermal (rastertotmt)
  DeviceURI usb://EPSON/TM-m30
  State Idle
  StateTime 1479136865
  ConfigTime 1479118516
  Type 36868
  Accepting Yes
  Shared no
  JobSheets none none
  QuotaPeriod 0
  PageLimit 0
  KLimit 0
  OpPolicy default
  ErrorPolicy abort-job
</DefaultPrinter>
DELIM
sudo mv ${DIR}/printers.conf /etc/cups/printers.conf

# Restart cups
sudo service cups restart

## Change to kiosk mode
sudo apt-get install openbox -y

# Ensure openbox is default window mananger.
sudo cat << DELIM >> ${DIR}/50-openbox.conf
[SeatDefaults]
autologin-user=bibbox
autologin-user-timeout=0
user-session=openbox
allow-guest=false
greeter-hide-users=true
DELIM

sudo mv ${DIR}/50-openbox.conf /etc/lightdm/lightdm.conf.d/50-openbox.conf

# Ensure chrome is started with openbox.
mkdir -p ${DIR}/.config/openbox
cat << DELIM >> ${DIR}/.config/openbox/autostart
rm -rf ~/.{config,cache}/google-chrome/
google-chrome --make-default-browser
(while true; do
	google-chrome --kiosk --no-first-run --disable-translate --enable-offline-auto-reload 'http://localhost:3010'
done) &
DELIM

# Set default config for openbox.
cp ${SELF}/rc.xml ${DIR}/.config/openbox

## Clean up
sudo apt-get remove --purge firefox libreoffice-core rhythmbox shotwell transmission thunderbird webbrowser-app deja-dup cheese aisleriot gnome-* -y
sudo apt-get --purge remove unity -y
sudo apt-get autoremove -y

# Clean home dir.
rm -rf ${DIR}/{Desktop,Downloads,Documents,Music,Pictures,Public,Templates,Videos,examples.desktop}

## Restart the show
reboot
