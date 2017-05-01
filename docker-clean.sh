#!/bin/bash
# Maintained by Sean Kilgarriff and Killian Brackey at ZZROT Design
#
# The MIT License (MIT)
# Copyright © 2016 ZZROT LLC <docker@zzrot.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the “Software”), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# TODO Function to check for which images containers are using
# TODO fully implement the created containers function so that created containers aren't removed by Default
# TODO maybe add a ratio of the number of containers/images that are being removed (could be confusing, but could clarify as well)


#ENVIRONMENT VARIABLES

# @info:	Docker-clean current version
declare VERSION="1.4.1"

# @info:	Required Docker version for Volume and Network functionality
declare REQUIRED_VERSION="1.9.0"

# @info:	Boolean for storing Docker version info
declare HAS_VERSION=false

# @info:	Boolean for verbose mode
declare VERBOSE=false

# @info:	Boolean for dry run to see before removing
declare DRY_RUN=false

# @info:    Boolean to flag if Containers should be stopped.
declare STOP_CONTAINERS=false

# @info:	Boolean to flag if containers should be deleted.
declare CLEAN_CONTAINERS=false

# @info:	Boolean to flag if images should be deleted.
declare CLEAN_IMAGES=false

# @info:	Boolean to flag if volumes should be deleted.
declare CLEAN_VOLUMES=false

# @info:	Boolean to flag if networks should be deleted.
declare CLEAN_NETWORKS=false

# @info:	Boolean to flag if machine/daemon should be reset.
declare RESTART=false

# @info:    Boolean to flag if tagged images are to be deleted.
declare DELETE_TAGGED=false

# @info:    Boolean to flag if Containers with status Created will be deleted or not.
declare DELETE_CREATED=true

#FUNCTIONS

# @info:    Parses and validates the CLI arguments
# @args:	Global Arguments $@
# TODO: handle use case where just -n or just -l flag is given
function parseCli(){
	if [[ "$#" -eq 0 ]]; then
		CLEAN_CONTAINERS=true
		CLEAN_IMAGES=true
		CLEAN_VOLUMES=true
		CLEAN_NETWORKS=true
		dockerClean
	fi
	if [[ "$#" -eq 1 ]]; then
		#If there is only one flag, and it is dry run or log, set defaults
		key="$1"
		case $key in
			-n | --dry-run) CLEAN_CONTAINERS=true; CLEAN_IMAGES=true; CLEAN_VOLUMES=true; CLEAN_NETWORKS=true ;;
			-l | --log) CLEAN_CONTAINERS=true; CLEAN_IMAGES=true; CLEAN_VOLUMES=true; CLEAN_NETWORKS=true ;;
		esac
	fi
	while [[ "$#" -gt 0 ]]; do
		key="$1"
		case $key in
			stop ) STOP_CONTAINERS=true; CLEAN_CONTAINERS=true; CLEAN_IMAGES=true; CLEAN_VOLUMES=true; CLEAN_NETWORKS=true ;;
			images ) DELETE_TAGGED=true; CLEAN_CONTAINERS=true; CLEAN_IMAGES=true; CLEAN_VOLUMES=true; CLEAN_NETWORKS=true ;;
			all ) STOP_CONTAINERS=true; DELETE_TAGGED=true; CLEAN_CONTAINERS=true; CLEAN_IMAGES=true; CLEAN_VOLUMES=true; CLEAN_NETWORKS=true ;;
			-s | --stop) STOP_CONTAINERS=true ;;
			-n | --dry-run) DRY_RUN=true ;;
			-l | --log) VERBOSE=true ;;
			-c | --containers) CLEAN_CONTAINERS=true ;;
			-i | --images) CLEAN_IMAGES=true ;;
			-m | --volumes) CLEAN_VOLUMES=true ;;
			-net | --networks) CLEAN_NETWORKS=true ;;
			-r | --restart) RESTART=true ;;
			-d | --created) DELETE_CREATED=false ;;
			-t | --tagged) DELETE_TAGGED=true ;;
			-a | --all) STOP_CONTAINERS=true; DELETE_TAGGED=true; CLEAN_CONTAINERS=true; CLEAN_IMAGES=true; CLEAN_VOLUMES=true; CLEAN_NETWORKS=true; RESTART=true ;;
			-v | --version) version; exit 0 ;;
			-h | --help | *) usage; exit 0 ;;
		esac
		shift
	done
	dockerClean
}

# @info:	Prints out Docker-clean current version
function version {
	echo $VERSION
}

# @info:	Prints out usage
function usage {
	echo
	echo "Options:"
  	echo "-h or --help        Opens this help menu"
  	echo "-v or --version     Prints the current docker-clean version"
  	echo
  	echo "-a or --all         Stops and removes all Containers, Images, and Restarts docker"
  	echo "-c or --containers  Stops and removes Stopped and Running Containers"
  	echo "-i or --images      Stops and removes all Containers and Images"
  	echo "-net or --networks  Removes all empty Networks"
		echo "-s or --stop        Stops all running Containers"
		echo
		echo "--dry-run           Adding this additional flag at the end will list items to be"
		echo "                    removed without running the remove or stop commands"
		echo
		echo "-l or --log         Adding this as an additional flag will list all"
		echo "                    image, volume, and container deleting output"
}

# @info:	Prints out 3-point version (000.000.000) without decimals for comparison
# @args:	Docker Version of the client
function printVersion {
	echo "$@" | awk -F. '{ printf("%03d%03d%03d\n", $1,$2,$3); }';
}

# @info:	Checks Docker Version and then configures the HAS_VERSION var.
function checkVersion  {
	local Docker_Version
	Docker_Version="$(docker --version | sed 's/[^0-9.]*\([0-9.]*\).*/\1/')"
	if [ "$(printVersion "$Docker_Version")" -gt "$(printVersion "$REQUIRED_VERSION")" ]; then
		HAS_VERSION=true
    else
        echo "Your Version of Docker is below 1.9.0 which is required for full functionality."
        echo "Please upgrade your Docker daemon. Until then, the Volume and Network processing will not work."
    fi
}

# @info:	Checks to see if Docker is installed and connected
function checkDocker {
    #Run Docker ps to make sure that docker is installed
    #As well as that the Daemon is connected.
    docker ps &>/dev/null
    DOCKER_CHECK=$?

    #If Docker Check returns 1 (Error), send a message and exit.
	if [ ! "$DOCKER_CHECK" ]; then
        echo "Docker is either not installed, or the Docker Daemon is not currently connected."
        echo "Please check your installation and try again."
        exit 1;
    fi
}

# @info: Stops all running docker containers.
function stop {
	IFS=$'\n' read -rd '' -a runningContainers <<<"$(docker ps -q)"
	if $DRY_RUN; then
		echo "Dry run on stoppage of running containers:"
		if [[ ! $runningContainers ]]; then
			echo "No running containers. Running without -n or --dry-run flag won't stop any containers."
            echo #Spacing
		else
			echo "Running without -n or --dry-run flag will stop the listed containers:"
            echo #Spacing
			for i in "${runningContainers[@]}"; do
				local name
				local path
				local args
				name="$(docker inspect -f '{{json .Name}}' $i)"
				path="$(docker inspect -f '{{json .Path}}' $i)"
				args="$(docker inspect -f '{{json .Args}}' $i)"
				echo "Container ID: $i IMAGE: $path/$args NAME: $name"
			done
            echo #Spacing
		fi # End Dry Run
	else
		if [ ! "$runningContainers" ]; then
			echo "No running containers!"
		else
			local count=0
			echo "Stopping running containers..."
			for i in "${runningContainers[@]}"; do
				local output
				local status
				local name
				local path
				local args
				name="$(docker inspect -f '{{json .Name}}' $i)"
				path="$(docker inspect -f '{{json .Path}}' $i)"
				args="$(docker inspect -f '{{json .Args}}' $i)"
				docker stop "$i" &>/dev/null
				status=$?
				if [[ $status -eq 0 ]] ; then
					count=$((count+1))
					output="STOPPED: ID: $i IMAGE: $path/$args NAME: $name"
					echo $output | log
				else
					output="COULD NOT STOP: ID: $i IMAGE: $path/$args NAME: $name"
					echo $output | log
				fi
			done
			echo "Containers stopped: $count"
		fi
	fi
}

# @info:	Removes all stopped docker containers.
function cleanContainers {
	if $DRY_RUN; then
		if $STOP_CONTAINERS && $DELETE_CREATED; then
			IFS=$'\n' read -rd '' -a containers <<<"$(docker ps -aq)"
		elif $STOP_CONTAINERS && ! $DELETE_CREATED; then
			IFS=$'\n' read -rd '' -a containers <<<"$(docker ps -q -f STATUS=exited -f STATUS=running)"
		elif ! $STOP_CONTAINERS && $DELETE_CREATED; then
			IFS=$'\n' read -rd '' -a containers <<<"$(docker ps -q -f STATUS=exited -f STATUS=created)"
		fi
		echo "Dry run on removal of stopped containers:"
		if [[ ! $containers ]]; then
			echo "No removable containers. Running without -n or --dry-run flag won't remove any containers."
			echo #Spacing
		fi
		if [[ $containers ]]; then
			echo "Running without -n or --dry-run flag will remove the listed containers:"
            echo #Spacing
			for i in "${containers[@]}"; do
				local name
				local path
				local args
				name="$(docker inspect -f '{{json .Name}}' $i)"
				path="$(docker inspect -f '{{json .Path}}' $i)"
				args="$(docker inspect -f '{{json .Args}}' $i)"
				echo "Container ID: $i IMAGE: $path/$args NAME: $name"
			done
			echo #Spacing
		fi # end dry run
	else
		if $DELETE_CREATED; then
			IFS=$'\n' read -rd '' -a containers <<<"$(docker ps -q -f STATUS=exited -f STATUS=created)"
		else
			IFS=$'\n' read -rd '' -a containers <<<"$(docker ps -q -f STATUS=exited)"
		fi
	    if [ ! "$containers" ]; then
	        echo "No containers To clean!"
	    else
			local count=0
			echo "Cleaning containers..."
			for i in "${containers[@]}"; do
				local output
				local status
				local name
				local path
				local args
				name="$(docker inspect -f '{{json .Name}}' $i)"
				path="$(docker inspect -f '{{json .Path}}' $i)"
				args="$(docker inspect -f '{{json .Args}}' $i)"
				docker rm "$i" &>/dev/null
				status=$?
				if [[ $status -eq 0 ]] ; then
					count=$((count+1))
					output="DELETED: ID: $i IMAGE: $path/$args NAME: $name"
					echo $output | log
				else
					output="COULD NOT DELETE: ID: $i IMAGE: $path/$args NAME: $name"
					echo $output | log
				fi
			done
			echo "Stopped containers cleaned: $count"
	    fi
	fi
}

# @info:	Removes all untagged/tagged docker images.
function cleanImages {
	if $DELETE_TAGGED; then
		IFS=$'\n' read -rd '' -a images <<<"$(docker images -a -q)"
	else
		IFS=$'\n' read -rd '' -a images <<<"$(docker images -aq --filter "dangling=true")"
	fi
	if $DRY_RUN; then
		echo "Dry run on removal of images:"
		if [[ ! $images ]]; then
			echo "No images. Running without -n or --dry-run flag won't remove any images."
			echo #Spacing
		else
			echo "Running without -n or --dry-run flag will remove the listed images:"
			echo #Spacing
			local totalSize=0
			for i in "${images[@]}"; do
				local repotag
				local size
				repotag="$(docker inspect -f '{{json .RepoTags}}' $i)"
				size="$(docker inspect -f '{{json .Size}}' $i)"
				echo "REPOSITORY/TAG: $repotag IMAGE ID: $i"
				totalSize=$((totalSize+size))
			done
			echoSize $totalSize
			echo #Spacing
		fi # End dry run
	else
		if [ ! "$images" ]; then
	        echo "No images to delete!"
	    else
			local count=0
			local totalSize=0
			echo "Cleaning images..."
			while [[ $images ]] ; do
				for i in "${images[@]}"; do
					local output
					local status
					local repotag
					local size
					repotag="$(docker inspect -f '{{json .RepoTags}}' $i)"
					size="$(docker inspect -f '{{json .Size}}' $i)"
					docker rmi -f $i &>/dev/null
					status=$?
					if [[ $status -eq 0 ]] ; then
						count=$((count+1))
						totalSize=$((totalSize+size))
						output="DELETED: REPOSITORY/TAG: $repotag IMAGE ID: $i"
						echo $output | log
						unset images[$i]
					fi
				done
			done
			echo "Images cleaned: $count"
			echoSize $totalSize
	    fi
	fi
}

# @info:	Removes all dangling Docker Volumes.
function cleanVolumes {
	IFS=$'\n' read -rd '' -a danglingVolumes <<<"$(docker volume ls -qf dangling=true)"
	if $DRY_RUN; then
		if $STOP_CONTAINERS && $DELETE_CREATED; then
			IFS=$'\n' read -rd '' -a containers <<<"$(docker ps -aq)"
		elif $STOP_CONTAINERS && ! $DELETE_CREATED; then
			IFS=$'\n' read -rd '' -a containers <<<"$(docker ps -q -f STATUS=exited -f STATUS=running)"
		elif ! $STOP_CONTAINERS && $DELETE_CREATED; then
			IFS=$'\n' read -rd '' -a containers <<<"$(docker ps -q -f STATUS=exited -f STATUS=created)"
		fi
		echo "Dry run on removal of dangling volumes:"
		if [[ ! $danglingVolumes ]]; then
			echo "No danlging volumes. Running without -n or --dry-run flag won't remove any dangling volumes."
			echo
		else
			echo "Running without -n or --dry-run flag will stop the listed dangling volumes:"
			for i in "${danglingVolumes[@]}"; do
				local driver
				driver="$(docker volume inspect -f '{{json .Driver}}' $i)"
				echo "DRIVER: $driver NAME: $i"
			done
			echo #For spacing
		fi # End dry run
	else
	    if [ ! "$danglingVolumes" ]; then
	        echo "No dangling volumes!"
	    else
			echo "Cleaning volumes..."
			local count=0
			for i in "${danglingVolumes[@]}"; do
				local status
				local output
				local driver
				driver="$(docker volume inspect -f '{{json .Driver}}' $i)"
				docker volume rm $i &>/dev/null
				status=$?
				if [[ $status -eq 0 ]] ; then
					count=$((count+1))
					output="DELETED DRIVER: $driver NAME: $i"
					echo $output | log
				else
					output="COULD NOT DELETE DRIVER: $driver NAME: $i"
				fi
				echo "Volumes cleaned: $count"
			done
	    fi
	fi
}

function cleanNetworks {
	IFS=$'\n' read -rd '' -a networks <<<"$(docker network ls -q)"
	declare -a emptyNetworks
	for i in "${networks[@]}"; do
		containers="$(docker network inspect -f '{{json .Containers}}' $i)"
		name="$(docker network inspect -f '{{json .Name}}' $i)"
		if [[ -n "$containers" ]] && [[ "$name" != '"bridge"' ]] && [[ "$name" != '"host"' ]] && [[ "$name" != '"none"' ]]; then
			emptyNetworks+=($i)
		fi
	done
	if [[ $DRY_RUN == true ]]; then
		echo "Dry run on removal of networks:"
		if [[ ! $emptyNetworks ]]; then
			echo "No empty networks. Running without -n or --dry-run flag won't remove any networks."
		else
			echo "Running without -n or --dry-run flag will remove the listed networks:"
			for i in "${emptyNetworks[@]}"; do
				local name="$(docker inspect -f '{{json .Name}}' $i)"
				local driver="$(docker inspect -f '{{json .Driver}}' $i)"
				echo "Network ID: $i NAME: $name DRIVER: $driver"
			done
		fi # End Dry Run
	else
		if [ ! "$emptyNetworks" ]; then
			echo "No empty networks!"
			echo
		else
			local count=0
			echo "Removing empty networks..."
			for i in "${emptyNetworks[@]}"; do
				if docker network rm $i 2>&1 | log ; then
					count=$((count+1))
				fi
			done
			echo "Networks removed: $count"
			echo
		fi
	fi
}

# @info:	Restarts and reRuns docker-machine env active machine
function restartMachine {
	operating_system=$(testOS)
	#if [[ $DRY_RUN == false ]]; then
		if [[ $operating_system =~ "mac" || $operating_system =~ 'windows' ]]; then
			active="$(docker-machine active)"
			if [[ $DRY_RUN == false ]]; then
				docker-machine restart $active
			else
				echo "Dry run on Daemon restart:"
				echo "Command that would be used: docker-machine restart $active"
			fi
			eval $(docker-machine env $active)
			echo "Running docker-machine env $active..."
			echo "New IP Address for" $active ":" $(docker-machine ip)
		elif [[ $operating_system =~ "linux" ]]; then
			if [[ $DRY_RUN == false ]]; then
				echo "Restarting Docker..."
				echo "Restarting this service requires sudo privileges"
			else
				echo "Dry run on Daemon restart, requires sudo to check platform:"
			fi
			init_system=$(linuxInitSystem)
			# Upstart covers SysV and OpenRC as well.
			if [[ $init_system =~ 'upstart'  ]]; then
				if [[ $DRY_RUN == false ]]; then
					sudo service docker restart
				else
					echo "Restart command that would be run: sudo service docker restart"
				fi
			elif [[ $init_system =~ 'systemd' ]]; then
				if [[ $DRY_RUN == false ]]; then
					sudo systemctl restart docker.service
				else
					echo "Restart command that would be run: sudo systemctl restart docker.service"
				fi
			elif [[ $init_system =~ 'rc' ]]; then
				if [[ $DRY_RUN == false ]]; then
					sudo launchctl restart docker
				else
					echo "Restart command that would be run: sudo launchctl restart docker"
				fi
			fi
		else
			echo It appears your OS is not compatible with our docker engine restart
			echo Windows compatibility work in progress
			echo It you feel you are seeing this as an error please visit
			echo "https://github.com/ZZROTDesign/docker-clean and open an issue."
			exit 2
		fi
	#else
		#echo "Docker daemon would now restart if docker-clean is run without -n or -dry-run."
		#if [[ $operating_system =~ "linux" ]]; then
	#		init_system=$(linuxInitSystem)
	#		echo "Command that would be used to restart:"
	#		if [[ $init_system =~ 'upstart'  ]]; then
	#			echo "Command that would be used to restart:sudo service docker restart"
#fi
		#fi
	#fi
}

# @info:	Runs the checks before the main code can be run.
function Check {
	checkDocker
	checkVersion
}

# @info:	Accepts input to output if verbose mode is flagged.
function log {
	read IN
	if $VERBOSE; then
		echo $IN
	fi
}

## ** Script for testing os **
# Modified for our usage from:
# Credit https://stackoverflow.com/questions/3466166/how-to-check-if-running-in-cygwin-mac-or-linux/17072017#17072017?newreg=b1cdf253d60546f0acfb73e0351ea8be
# Echo mac for Mac OS X, echo linux for GNU/Linux, echo windows for Window
function testOS {
  if [ "$(uname)" == "Darwin" ]; then
      # Do something under Mac OS X platform
      echo mac
  elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
      # Do something under GNU/Linux platform
      echo linux
			#!/bin/bash

  elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
      # Do something under Windows NT platform
      echo windows
  fi
}
#END FUNCTIONS

# Function for testing linux initSystem
function linuxInitSystem {
	# To include hidden files
	shopt -s nullglob dotglob

	# Get sudo privileges
	if [ $EUID != 0 ]; then
    sudo "$0" "$@" &>/dev/null
    #exit $?
fi
# Directories to check
# Upstart covers SysV and OpenRC as well.
	upstart=(/etc/init.d/docker)
	systemd=(/etc/systemd/docker)
	rc=(/etc/rc.d/docker)
	initSystem=""
	#files=(/some/dir/*)
	if [ ${#upstart[@]} -gt 0 ]; then
		initSystem=upstart
	elif [ ${#systemd[@]} -gt 0 ]; then
		initSystem=systemd
	elif [ ${#rc[@]} -gt 0 ]; then
		initSystem=rc
	fi
	echo $initSystem
}

# @info:	Echos the size of images removed in various measurements
# @args:	The number of bytes moved
function echoSize {
	local mega
	local giga
	mega=$(($1/1000000))
	giga=$(($1/1000000000))
	echo "You've cleared approximately MB: $mega or GB: $giga of space!"
}

# @info:	Default run option, cleans stopped containers and images
function dockerClean {

	if $STOP_CONTAINERS; then
		stop
	fi
	if $CLEAN_CONTAINERS; then
		cleanContainers
	fi
	if $CLEAN_IMAGES; then
		cleanImages
	fi
	if $CLEAN_VOLUMES && $HAS_VERSION; then
		cleanVolumes
	fi
	if $CLEAN_NETWORKS && $HAS_VERSION; then
		cleanNetworks
	fi
	if $RESTART;  then
		restartMachine
	fi
}

# @info:	Main function
Check
parseCli "$@"
exit 0
