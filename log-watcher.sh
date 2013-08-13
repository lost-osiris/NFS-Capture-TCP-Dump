#!/bin/bash
pids=$$

FILE="$1"
PIPE="$2"

checkmessages_DEFAULT=("${@: +3}")
length=$(expr `echo ${#checkmessages_DEFAULT[@]}` - 1)
logfound=false

#text formats
bold="\033[1m"
normal="\e[0m"
endColor='\e[0m'
red='\e[0;31m'
yellow='\e[0;33m'

function find_message() {

while read line < $PIPE; do
		
	for ((i=0; i<=$length; i++)); do
		
		test=$(echo $line | grep -F "${checkmessages_DEFAULT[$i]}" -o)

		if [[ "$test" == "${checkmessages_DEFAULT[$i]}" ]]; then
			echo "$line"
			logfound=true
		fi
	done

	if [[ $logfound == true ]]; then
		break
	fi
done

}

if [[ ! -p $PIPE ]]; then
        mkfifo $PIPE
fi

`tail -n 0 -f $FILE >> $PIPE` &
pids="$pids $!"

`find_message &> /tmp/foundmessage.txt`
kill -9 $pids




