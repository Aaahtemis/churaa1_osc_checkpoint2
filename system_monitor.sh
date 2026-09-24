#!/bin/bash
# ======================
# Script  : system_monitor.sh
# Purpose : Allows the user to manage processes priority and kill them.
# Author  : Artemis Churcher
# Date	  : 2026-09-24
# ======================

line(){
	echo
	echo "---------------------------"
	echo
}

end(){
	echo
	echo $2
	echo "Exiting.."
	echo
	sleep 1
	exit $1
}
log(){
	logDirectory="/var/logs"
	if ! [ -d "$logDirectory" ]; then
		mkdir -p "$logDirectory"
	fi
	logLocation="${logDirectory}/system_monitor.log"
	if ! [ -f "$logLocation" ]; then
		touch "$logLocation"
	fi
	echo "$(date '+[%Y-%m-%d %H:%M:%S]') $1 : $2" >> "$logLocation"
	
}
# Build cpu processes list and set limit
minCPU=0.0 # for debugging is set to 0.0
cpuList=$(
	ps -eo pid=,pcpu=,pmem=,args=  --sort=-pcpu | 
	head -n 5
)

# Sum of top 5 processes
cpuTotal=$(awk '{ sum += $2 } END { printf "%.1f", sum }' <<< "$cpuList")
if [[ "$cpuTotal" < "$minCPU" ]]; then
	end 0 "Processes are functioning within cpu limits."
else
	echo "Highest cpu-cost processes: "
	# Write list to screen
	while read -r pid cpu mem command; do
		printf "PID: %s | CPU: %.1f%% | MEM: %.1f%% | CMD: %s\n" \
			"$pid" "$cpu" "$mem" "$command"
	done <<< "$cpuList"
	echo "Total Usage: $cpuTotal"
	echo

	# Request if delete all
	read -rp "Would you like to terminate these processes? y/N :" ans
	if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
		while IFS= read -r line; do
			pid=$(echo "$line" | awk '{print $1}')
			kill -TERM "$pid"
			echo "Sent SIGTERM to $pid. Waiting 3 seconds..."
			sleep 3
			# check if stopped peacefully otherwise force remove
			if kill -0 "$pid"  2>/dev/null; then
				kill -KILL "$pid"
				echo "Failed to stop process $pid peacefully -- sent SIGKILL"
			else 
				echo "Process $pid stopped gracefully"
			fi
		done <<< "$cpuList"
	fi
fi

line

# Build ram processes list and set limit
minRAM=0.0 # for debugging is set to 0.0
ramList=$(
	ps -eo pid=,pmem=,args=  --sort=-pmem
)

# Sum of all process ram usage
ramTotal=$(awk '{ sum += $2 } END { printf "%.1f", sum }' <<< "$ramList")
if [[ "$ramTotal" < "$minRAM" ]]; then
	end 0 "Processes are functioning within ram limits."
else
	echo "Highest ram-cost processes: "
	# Write list to screen
	while read -r pid mem command; do
		printf "PID: %s | CMD: %s | MEM: %.1f%%\n" \
			"$pid" "$command" "$mem"
	done <<< "$ramList" | head -n 5
	echo "Total Usage: $ramTotal"
	log "WARNING" "Memory usage at $ramTotal"
fi

line

inLoop=1
while [[ "$inLoop" -gt 0 ]]; do
	read -rp "Enter a PID to act on (or press Enter to exit): " pid

	# check for exit
	if [[ -z "$pid" ]]; then
		end 0 "No PID entered."
	fi

	if ! kill -0 "$pid" 2>/dev/null; then
		echo "Process - $pid is not currently running."
	else
		read -rp "Choose an action -- [t]erminate, [n]renice: " action
		case "$action" in
			t | terminate)
				echo "Terminating process - $pid"
				kill -TERM "$pid"
				echo "Sent SIGTERM to $pid. Waiting 3 seconds..."
				sleep 3
				# check if stopped peacefully otherwise force remove
				if kill -0 "$pid"  2>/dev/null; then
					kill -KILL "$pid"
					echo "Failed to stop process $pid peacefully -- sent SIGKILL"
				else 
					echo "Process $pid stopped gracefully"
				fi
				line
				;;
			n | renice)
				echo "Change the priority of process - $pid"
				((inLoop++))
				while [[ "$inLoop" -gt 1 ]]; do
					line
					read -rp "Enter a new nice value (0..19 or press Enter to exit): " nice_value
					# check for blank value
					if [[ -z "$nice_value" ]];then
						((inLoop--))
					fi

					# check if nice
					if ! [[ "$nice_value" =~ ^[0-9]+$ ]] ||
						(( nice_value < 0 || nice_value > 19)); then
						echo "Error: nice value mist be in 0...19"
						line
					elif renice -n "$nice_value" -p "$pid" >/dev/null; then
						echo "Process $pid set to nice value $nice_value."
						((inLoop--))
						line
					fi
				done
				;;
			*)
				echo "Unknown action"
				;;
		esac
	fi
done

