#!/bin/bash

trap ctrl_c INT

pids=$$ #holds all pids for all background processes
logpids=""
tcpdump_pids=""
index=$(expr 0)

#tcpdump defaults
filesize="1024MB"

#varibles used to check logs for messages
checkmessages_DEFAULT=("not responding, timed out" "not responding, still trying")
defaultlog="/var/log/messages"
logfoundmessage=""
PIPE="/tmp/log-test.txt"
logfound=false
TESTLOG=false
DEFAULTLOG=true
DEFAULTMESSAGE=true

#varibles will be used for file naming and temp files
output=""
debugoutput=""
tcpdumpout=""
filename="nfs-test.tar"
casenum=""

#Mode varibles
DEBUG=false
MANUAL=true #running in manual mode by defualt
AUTO=false
CASE=false
CASESET=false
MULTISERVERS=false
MANUAL_IP=false
MANUAL_INTERFACE=false
TCPDUMPRAN=false
ARCHIVE=false
TRACE=false #used for developing
LISTALL=false

#text formats
bold="\033[1m"
normal="\e[0m"
endColor='\e[0m'
red='\e[0;31m'
yellow='\e[0;33m'

#Holds the amount if servers mounted. Manual mode changes value to one after user selects server.
servercount=$(expr `echo "$serverip" | wc -w`)

#will hold tcpdump information to display in debug mode
debug=""

#Holds interface for TCPdump to test.	
interface=""

#Finds all mount points using NFS
findmounts=$(grep "nfs" /proc/mounts | grep -E '[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}' | awk '{print $2}')

#Test IP's are mounted using NFS
#Will handle for ALL NFS versions
serverip=$(grep "nfs" /proc/mounts | grep -E '[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\ ' /proc/mounts -o)

#Holds arguments user passes
#serverslist=(${serverip// /})
ARG=( "$@" )

function validate_arg() {

if [ "$ARG" != "" ]; then
	for x in "${ARG[@]}"; do 

       		case $x in

        	"-d" | "--debug")
			DEBUG=true
			echo -e "${bold}Debuging on${normal}"
       		;;

		"-a" | "--auto")
			AUTO=true
			MANUAL=false
		;;

		"-c" | "--case-number")
			CASE=true
		;;

		"-i" | "--interface")
			if [[ $AUTO == false ]]; then
				MANUAL_INTERFACE=true
				interface=""
			else
				echo -e "\n${red}*** Can't run Auto and Manual mode at same time ***${endColor}\nFor help use --help or -h\n"
				kill -9 $pids
			fi
		;;
	
		"-s" | "--serverip")
			if [[ $AUTO == false ]]; then
				MANUAL_IP=true
				serverip=""
			else
				echo -e "\n${red}*** Can't run Auto and Manual mode at same time ***${endColor}\nFor help use --help or -h\n"
				kill -9 $pids
			fi
		;;

		"-h" | "--help")
			print_usage
			kill -9 $pids
		;;

		"-z" | "--zip")
			ARCHIVE=true
		;;

		#will only list servers and mount points
		"-l" | "--list")
			server_detials
		;;

		"-C" | "--check-log")
			TESTLOG=true

			if [[ ! -p $PIPE ]]; then
				mkfifo $PIPE
				trace "Kernel Mustard 'picks up' his Pipe!"
			else
				trace "Kernel Mustard 'has' his Pipe!"
			fi
		;;

		"-t" | "--trace")
			TRACE=true
			trace "Trace Mode is ON"
			
		;;

		"-D" | "--default-log")
			DEFAULTLOG=false
			defaultlog=""
		;;

		"-T" | "--test-message")
			DEFAULTMESSAGE=false
		;;

		"-L" | "--list-all")
			LISTALL=true
			server_detials
		;;

		*) #everything after arguments is pasted is handled below

			if [[ $CASE == true ]] && [[ $CASESET == false ]]; then
				
				x=$(echo $x | tr -d ' ') #won't error out if user puts space by mistake
				
				if [[ $x != *[!0-9]* ]] && [[ $(expr length "$x") -eq 8 ]]; then #test if case number is a valid number and at least 7 digits long
					casenum="case#$x"
					filename="nfs-test-$casenum.tar"  
					CASESET=true             			
				else 
					echo -e "${red}*** ${bold}$x${normal} ${red}is not a valid case number or is not 8 digits long ***${endColor}\nFor help use -h or --help\n"
					kill -9 $pids
				fi
				
				continue
             		fi

			if ([[ $MANUAL_IP == true ]] && [[ $MANUAL_INTERFACE == false ]]) || ([[ $MANUAL_IP == true ]] && [[ $MANUAL_INTERFACE == true ]] && [[ "$serverip" == "" ]]); then

				x=$(echo $x | tr -d ' ') #won't error out if user puts space by mistake
				test=$(echo "$x" | grep -E '[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}' -o)

				if [ "$x" == "$test" ]; then
					serverip=$x				
				else 
					
					echo -e "${red}*** ${bold}$x${normal} ${red}is not a valid IP address for server ip ***${endColor} \nFor help use -h or --help\n"
					kill -9 $pids
				fi
						
			fi


			if ([[ $MANUAL_INTERFACE == true ]] && [[ $MANUAL_IP == false ]]) || ([[ $MANUAL_INTERFACE == true ]] && [[ $MANUAL_IP == true ]] && [[ "$interface" == "" ]]); then
				MULTISERVERS=false
				
				test=$(netstat -ie | grep -F "$x" | awk '{print $1}' | head -n1) #tests if provided interface exists
				intf_found=false
	
				for intf in $test; do 				
					if [ "$x" == "$intf" ]; then
						intf_found=true
					fi
				done

				if [[ $intf_found != true ]]; then 
					echo -e "${red}*** ${bold}$x${normal} ${red}is not a valid interface ***${endColor}  \nFor help use -h or --help\n"
					kill -9 $pids
				else
					echo -e "Interface ${bold}$x${normal} found"
				fi	
				
				interface=$x

			fi

			if [[ $TESTLOG == true ]] && [[ $DEFAULTMESSAGE == true ]] && [[ $DEFAULTLOG == true ]]; then
				if [[ -f "log-watcher.sh" ]]; then

					trace "Determaining if config file exists"

					if [ -f $x ]; then
						echo -e "\nFile ${bold}$x${normal} found!\n"
							
						checkmessages_DEFAULT=()
						count=$(expr 0)
						
						#Sets default messages from config file
						while read messages; do
						
							checkmessages_DEFAULT[$count]="$messages"
							count=$(expr $count + 1)

						done < $x

						trace "Using config file: $x"
					else
						trace "No config file found \nDefault Test Log = $defaultTESTLOG"
					fi

				else
					echo -e "${red}*** Must have log-watcher.sh to run this option ***${endColor}  \nFor help use -h or --help\n"
					kill -9 $pids
				fi
			fi
			
			if ([[ $DEFAULTLOG == false ]] && [[ $DEFAULTMESSAGE == true ]]) || ([[ $DEFAULTLOG == false ]] && [[ $DEFAULTMESSAGE == false ]]); then
				
				loglist=(${x// /})
			
				for i in "${loglist[@]}"; do 
					if [[ -f "$i" ]]; then
						defaultlog="$defaultlog $i"
						trace "Default log file: ${loglist[@]}"
					else
						echo -e "${red}*** ${bold}$i${normal} ${red}Is not a valid log file ***${endColor}  \nFor help use -h or --help\n"
						kill -9 $pids
					fi
				done
			fi

			if [[ $DEFAULTMESSAGE == false ]]; then
				checkmessages_DEFAULT=()
				checkmessages_DEFAULT="$x"
				trace "default message: `echo "${checkmessages_DEFAULT[@]}"`"
			fi

			continue
        	esac	
	done
fi

if [[ "$serverip" == "" ]] && [[ $MANUAL_INTERFACE == false ]] && [[ $MANUAL_IP == false ]]; then
	echo -e "${red}${bold}*** No NFS Servers Mounted. ***${normal}${endColor}\nFor help use -h or --help"
	kill -9 $pids
fi

if [[ $casenum == "" ]] && [[ $CASE == true ]]; then
	echo -e "${red}*** ${bold}$x${normal} ${red}is not a valid case number ***${endColor}\nFor help use -h or --help"
	kill -9 $pids
fi

if [[ $MANUAL_INTERFACE == true ]] && [[ $MANUAL_IP == false ]]; then
	serverip="null"
fi

if ([[ $AUTO == true ]]) && ([[ $MANUAL_INTERFACE == true ]] | [[ $MANUAL_IP == true ]]); then

	echo -e "\n${red}*** Can't run Auto and Manual mode at same time ***${endColor}\nFor help use --help or -h\n"
	kill -9 $pids

fi

teststring=$(ls)

#Handles if script has been run before in current directory to ensure files don't get overwriten
if [[ "$teststring" == *"tcpdump-"* ]] || [[ "$teststring" == *"nfs-test"* ]]; then	
	for ((i=0; i < 3; i++)); do

		echo -en "${red}*** Warning ***${endColor}: Output files exist using default naming convention \nWould you like to continue? (yes) or (no): "

		read selection
	
		if [ "$selection" == "" ]; then

			if [[ $i -eq 2 ]]; then
				echo -e "\n${red}*** Notice ***${endColor}: No input provided will assume ${bold}yes${normal} and continue"
			fi

			continue
		fi

		if [[ "$selection" == "yes"  ]] || [[ "$selection" == "y"  ]]; then
			break
		fi
		
		if [[ "$selection" == "no"  ]] || [[ "$selection" == "n"  ]]; then
			kill -9 $pids
		fi
		
		if [[ $i -eq 2 ]]; then
			kill -9 $pids
		fi
	done
fi

multi_servers

if [ $MANUAL == true ]; then
	if [ $MULTISERVERS == true ]; then
		echo ""
		echo -e "${bold}Starting Manual Mode${normal}"
	else
		echo -e "${bold}Starting Manual Mode\nOnly one server mounted${normal}"
		servercount=$(expr 1)
	fi
else
	echo -e "${bold}Starting Auto Mode${normal}"
fi

}

#Mulitiple server defined by more then 16 characters 000.000.000.000 standard IP address format.
function multi_servers() {

multiservers=$(expr length "$serverip")

if [ $multiservers -gt 16 ]; then
	MULTISERVERS=true
else		
	MULTISERVERS=false	
fi

}

function run_manual() {

if [ $MULTISERVERS == true ]; then

run_display_prompt #displays servers and allows user to pick. Sets varable SERVERIP and INTERFACE
get_output $serverip $interface $casenum

echo -e "\n*****  At any point to exit hit ${bold}${red}'CRL + c'${endColor}${normal}   *****"
run_tcpdump
loading_screen

else

	if [ $MANUAL_INTERFACE != true ]; then
		serverip=$(echo $serverip | tr -d ' ')
		interface=$(ip route get $serverip | head -n1 | awk '{print $3}' | tr -d ' ')
	fi

	get_output $serverip $interface $casenum
	echo -e "\n*****  At any point to exit hit ${bold}${red}'CRL + c'${endColor}${normal}   *****"
	run_tcpdump
	loading_screen

fi

}

#Allows user to pick test server.
#Formats prompt as well.
function run_display_prompt() {

moreinfo=$1

trace "Displaying prompt for user to select server"

#Puts servers into an Array to allow user to select which server to run test on
serverslist=(${serverip// /})
mountlist=(${findmounts// /})
selectedstring=""
count=$(expr 0)
	
#Prints out server options for user to select
for i in "${serverslist[@]}"
do
	if [[ $moreinfo == true ]]; then
		echo -e "  $count) ${bold}${serverslist[$count]}${normal}"
	else
		echo -e "  $count) ${bold}${serverslist[$count]}${normal} on ${mountlist[$count]}"
	fi

	selectedstring="$selectedstring $count," 
	count=$(expr $count + 1)				
done

selectedindex=$((`echo ${#selectedstring}` - 1))
selectedstring=`echo ${selectedstring:0:$selectedindex}`

#Validating user input to be between max and min of array
for ((i=0; i < 3; i++)); do

	if [[ $moreinfo == true ]]; then
		echo -en "Which server would you like to know more information about [$selectedstring]: "
	else
		echo -en "Which server would you like to test [$selectedstring]: "
	fi

	read selectserver
	
	if [ "$selectserver" == "" ]; then
		selectserver=$(expr 0)
		echo "Picking 0"
	fi

	if [[ `expr $selectserver` != *[!0-9]* ]] && [[ `expr $selectserver` -le `expr $count - 1` ]]; then 
		break
	else
		echo -e "\n${red}Must enter a valid number between and including ${bold}0 & `expr $count - 1`${normal}${endColor}\n"
	fi

	if [[ $i -eq 2 ]]; then
		kill -9 $pids
	fi

done
	
serverip=`echo ${serverslist[$selectserver]} | awk '{split($0,a,":"); print a[1];}'`
interface=$(ip route get $serverip | head -n1 | awk '{print $3}')
servercount=$(expr 1)

get_output $serverip $interface $casenum

}

#tests all servers found and only runs on servers that are unique
function run_auto() {

serverip=$(echo "$serverip" | sort | uniq)
servercount=$(expr `echo "$serverip" | wc -w`)
serverslist=(${serverip// /})

for ((index=0; index<$servercount; index++)); do

	serverip=$(echo "${serverslist[$index]}")

	#Given an IP address. Will find interface.	
	interface=$(ip route get $serverip | head -n1 | awk '{print $3}')

	get_output $serverip $interface $casenum $index
	run_tcpdump
done

#resetting server ip addresses
serverip=$(grep "nfs" /proc/mounts | grep -E '[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\ ' /proc/mounts -o | sort | uniq)

trace "TCPdump is running along with script on the following pids: $pids"

echo -e "\n*****  At any point to exit hit ${bold}${red}'CRL + c'${endColor}${normal}   *****\n"

loading_screen

}

#Pass in $serverip, $interface, $casenum in this order
#All varibles are global
function get_output() {

server=$1
intf=$2
case_number=$3
tcpdumpout="/tmp/tcpdump-output$index.txt"

if [[ $MANUAL_INTERFACE == true ]] && [[ $MANUAL_IP == true ]]; then

	if [ $CASE == true ]; then 
		file_naming $case_number $intf $server	
	else
		file_naming $intf $server
	fi

else

	if [[ $MANUAL_INTERFACE == true ]] && [[ $MANUAL_IP == false ]]; then
		
	
		if [ $CASE == true ]; then 
			file_naming $case_number $intf
		else
			file_naming $intf
		fi

	else
		if [ $MANUAL_IP == true ]; then

			if [ $CASE == true ]; then 
				file_naming $case_number $intf $server
			else
				file_naming $intf $server
			fi
		fi
	fi

fi				

if [[ $AUTO == true ]] || ([[ $MANUAL == true ]] && [[ $MANUAL_IP == false ]] && [[ $MANUAL_INTERFACE == false ]]); then

	if [ $CASE == true ]; then 
		file_naming $case_number $intf $server
	else
		file_naming $intf $server
	fi
fi

}

#handles all file naming to ensure .pcap file will correspond with debug file
function file_naming() {

names=$@
string=""

for i in $names; do
	string="$string-$i"
done

output="/tmp/tcpdump-test$string.pcap"
debugoutput="/tmp/tcpdump-debug-log$string.txt"

}

function run_tcpdump() {
TCPDUMPRAN=true

if [ $AUTO != true ]; then
	echo -e "\nTesting host: ${bold}$serverip${normal} \nInterface: ${bold}$interface${normal} \nOutput Location: ${bold}$output${normal} \nFile Size: ${bold}$filesize${normal}\n"
fi

if [[ $MANUAL_INTERFACE == true ]] && [[ $MANUAL_IP == false ]]; then

	
	`tcpdump -s0 -i $interface -W 1 -C $filesize -w $output &> $(echo "$tcpdumpout")` & #Writes output to file
	pids="$pids $!"

	trace "TCPdump is running along with script on the following pids: $pids"
else
	`tcpdump -s0 -i $interface host $serverip -W 1 -C $filesize -w $output &> $(echo "$tcpdumpout")` & #Writes output to file
	pids="$pids $!"
 
	trace "TCPdump is running along with script on the following pids: $pids"
fi

}

#Gets tcpdump packet information and all varibles user on time tcpdump was run.
function run_debug() {

if [ $DEBUG == true ]; then
debug="NFS mount points \n$findmounts\n
Server Tested: $serverip
Interface: $interface
Output=$output
Found Message: $logfoundmessage
TCP dump command:\ntcpdump -s0 -i $interface host $serverip -W 1 -C $filesize -w $output \nTCP dump Output:"

	message=$(cat $tcpdumpout)
	debug="$debug \n$message"

	if [ $CASE == true ]; then 
		echo -e "$debug" &> $debugoutput
	else
		echo -e "$debug" &> $debugoutput
	fi
fi

}

#Listens for ctrl+c press and kills all background process and checks for debug mode
function ctrl_c() {

index=$(expr 0) #reset index
serverslist=(${serverip// /})

currentdir=$(pwd)

if [[ $logfound == true ]]; then
	echo -e "\n${red}\nKilled tcpdump, Message found in:${bold} $defaultlog \n${normal}Message found: ${bold}$logfoundmessage${normal}${endColor}"	
fi

trace "Orginizing output files to match .pcap and debug files \nServer Count = $servercount"

for ((index=0; index<$servercount; index++)); do	

	if [[ $AUTO == true ]]; then
		serverip=$(echo "${serverslist[$index]}")
		interface=$(ip route get $serverip | head -n1 | awk '{print $3}')

		get_output $serverip $interface $casenum $index
		run_debug
	else
		get_output $serverip $interface $casenum $index 
		run_debug
	fi

done

#Checks if TCP dump ever ran. Check ensurres files exist.
if [ $TCPDUMPRAN == true ]; then	
	echo -e "\n${bold}\nGetting files${normal}"
	get_files
	rm -f $PIPE
fi

echo ""

kill -9 $pids


}

#Archives files if user specifies or 
#copyies temp files to current directory then
#removes temp files
function get_files() {

trace "Getting files after script has ended"

currentdir=$(pwd)
find_files="tcpdump"
tcpdumpout="tcpdump-output"

cd /tmp/ #Ensures archive only gets files rather then entire directory
if [ $ARCHIVE == true ]; then

	echo -e "${bold}Files Archived are:${normal}"

	rm -f $tcpdumpout*
	#archives file and puts in /tmp/ along with output files and copies over to current directory. Does this to avoid perrmissions problems
	tar -zvcf $filename $find_files*
	cp -f $filename $currentdir/
	rm -f $filename* $find_files*

	echo -e "${bold}*** Done! ***${normal} \n \nFiles stored in $currentdir"

else

	rm -f $tcpdumpout*
	cp -f $find_files* $currentdir/ 
	rm -f $filename* $find_files* 
	echo -e "${bold}*** Done! ***${normal} \n \nFiles stored in $currentdir"
fi

cd $currentdir

return
}

#Adds dots to the end of statement. Indacating to user that TCP dump is running.
function loading_screen() {

trace "Loading screen running"

if [[ $TESTLOG == true ]] || [[ $DEFAULTMESSAGE == false ]]; then
	echo -e "Testing for messages in ${bold}$defaultlog${normal}"
	echo -ne "${bold}TCP Dump is Running${normal}"

	if [[ $DEFAULTMESSAGE == false ]]; then

		trace "Not using default message"
		`/bin/bash log-watcher.sh "$defaultlog" "$PIPE" "${checkmessages_DEFAULT[@]}"` &
		pids="$pids $!"

	else

		trace "Using default message"
		`/bin/bash log-watcher.sh "$defaultlog" "$PIPE" "${checkmessages_DEFAULT[@]}"` &
		pids="$pids $!"

	fi

	while true; do
		echo -ne "${red}${bold}.${endColor}${normal}"
		sleep 3

		test_string=$(cat /tmp/foundmessage.txt)

		if [[ "$test_string" != "" ]]; then
			logfound=true
			logfoundmessage="$test_string"
			ctrl_c
		fi

	done
else

	echo -ne "${bold}TCP Dump is Running${normal}"

	while true; do
		echo -ne "${red}${bold}.${endColor}${normal}"
		sleep 3
	done

fi
		
}

#used to print debug messages for developing script
function trace() {
debugmessage="$1"
color="$2"

if [[ $TRACE == true ]]; then

	if [[ "$color" == "" ]]; then
		echo -e "\n${yellow}${bold}$debugmessage${normal}${endColor}\n"
	else
		echo -e "\n${color}${bold}$debugmessage${normal}${endColor}\n"
	fi
fi

}

function server_detials() {
serverip=$(echo -e "$serverip" | sort | uniq)
serverslist=(${serverip// /})
count=$(expr 0)

if [[ $MULTISERVERS == false ]]; then 
	$LISTALL == true
fi

if [[ $LISTALL == true ]]; then
	
	
	length=$(expr `echo "${#serverslist[@]}"`)
	for i in "${serverslist[@]}"; do
		serverip=$i
		get_detials
	done

else
	run_display_prompt true
	get_detials
fi
			
kill -9 $pids

}

function get_detials() {

string=$(grep "$serverip" /proc/mounts | tr "," " " | tr "\\n" " ")
information=(${string// / })
length=$(expr `echo -e "${#information[@]}"`)

echo -e "\n${red}*** Displaying all Information on ${bold}$serverip${normal} ${red}***${endColor}"
for ((i=0; i<$length; i++)); do

	test=$(echo "${information[$i]}" | grep "$serverip" | awk '{split($0,a,":"); print a[1];}')

	if [[ "$serverip" == "$test" ]]; then
		version=$(echo ${information[$i+5]} | awk '{split($0,a,"vers="); print a[2];}')
		echo -e "${bold}\nMount Point${normal}: ${information[$i+1]} ${bold}\nNFS Version${normal}: $version ${bold}\nPermissions${normal}: ${information[$i+3]}${bold}\nMount Type${normal}: ${information[$i+9]}"
	fi
done

exportsfile=$(showmount --exports $serverip | tail -n +2)
clientsmounted=$(showmount -a $serverip | tail -n +2)

echo -e "
${bold}Exports${normal}: \n$exportsfile 
${bold}\nClients Mounted${normal}: \n$clientsmounted\n"

}

function print_usage() {

usage="Usage: [-a | --auto] [-s | --server server IP address] [-z | --zip] 
[-i | --interface interface] [-c | --case-number case number] [-d | --debug]
[-C | --check-log [configuration file]] [ --test-message message to test]
[-D | --default-log test log location] [-l | --list] 

${bold}Synopsis${normal}

   Script finds NFS servers to run TCP dump on. By default the script runs in 
   Manual mode allowing the user to select which server the user would like
   to run on. All output of script will be archived and stored in users current
   directory.

${bold}Options${normal}   *** ${red}Note all arguments must have a '-' before them${endColor} ***
   ${bold}-a, --auto	       ${normal}Will run TCP dump on all servers mounted by NFS

   ${bold}-i, --interface     [interface]${normal}   Must specify an interface for TCP dump
			            to run on. Script will find server mounted
				    by specified interface

   ${bold}-d, --debug	       ${normal}Writes all variables to current directory for debuging

   ${bold}-s, --serverip      [server IP address]${normal}   Must specify NFS server IP address 
					      Script finds interface for 
					      TCP dump with supplied IP address

   ${bold}-c, --case-number   [valid case number]${normal}   Must supply valid case number
					     Takes case number and apply
					     it to output file of TCP dump.

   ${bold}-h, --help	      ${normal}Prints this page

   ${bold}-z, --zip	      ${normal}Archives files writen to current directory

   ${bold}-l, --list	      ${normal}Allows user to select which NFS server information is displayed

   ${bold}-L, --list-all      ${normal}Displays all NFS server information

   ${bold}-C, --check-log     [Configuration file]  ${normal}Turns on log watching for a message
					            also will oads a file that contains messages 
					            to test agains default log files

   ${bold}-D, --default-log   [test log location]   ${normal}Changes the default test log location

   ${bold}-T, --test-message  [message]   ${normal}Sets a message to test against logs.

See Examples.txt for addional help"


echo -e "$usage" | less -R

}

function main() {

validate_arg $ARG

if [ $MANUAL == true ]; then
	run_manual
fi

if [ $AUTO == true ]; then
	run_auto
fi

}

main
 

