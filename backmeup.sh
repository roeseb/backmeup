#!/bin/bash

CONFIG_FILE="backmeup.cfg"

function main() {
	echo "starting"
	parseOptions "$@"
	echo "initialized"
	readConfig

	echo "initialized"

	TEMP_FOLDER=$(mktemp -d -p /tmp backmeup.XXXXXXXX)
	EXCLUDE_TEMP_FILE=$TEMP_FOLDER"/exclude.txt"

	echo $BACKUP_EXCLUDE | sed 's/ /\n/g' >$EXCLUDE_TEMP_FILE

	if [ "$VERBOSE" = "true" ]; then
		echo "Done"
	fi

	case "true" in
	$FULL_BACKUP)
		fullBackup
		;;
	$SYNC_MODE)
		echo "Sync mode"
		;;
	$DELTA_MODE)
		echo "delta"
		deltaMode
		;;
	*)
		echo "No run mode selected"
		RETURN_CODE=1
		;;
	esac

	rm $EXCLUDE_TEMP_FILE
	rmdir $TEMP_FOLDER

	exit $RETURN_CODE
}

function deltaMode() {
	local LAST_RUN_FILE="$VAR_DIR/lastrun"

	[ -f $LAST_RUN_FILE ] || echo "There is no lastrun file in directory $VAR_DIR. Can't do a delta backup." && exit 1

	echo "Exec!!!!"
}

function fullBackup() {
	BACKUP_FILE_FULL_PATH=$(echo $BACKUP_DIR | sed 's/\/ *$//g')
	BACKUP_FILE_FULL_PATH+="/$BACKUP_FILE"

	FIFO_FILE=$TEMP_FOLDER"/ssh.pipe"

	TAR_OPTIONS="cz"

	if [ "$VERBOSE" = 'true' ]; then
		TAR_OPTIONS+="v"
	fi

	TAR_OPTIONS+="f"

	mkifo $FIFO_FILE

	TAR_COMMAND="tar --exclude-from $EXCLUDE_TEMP_FILE -$TAR_OPTIONS - $SOURCE_PATHES > $FIFO_FILE"
	SSH_COMMAND="cat $FIFO_FILE | ssh -i $CERTIFICATE $BACKUP_USER@$BACKUP_HOST \"cat > $BACKUP_FILE_FULL_PATH\""

	if [ "$VERBOSE" = "true" ]; then
		echo ""
		echo "Starting backup"
		echo $COMMAND
	fi

	if [ "$TEST" = "true" ]; then
		echo "Test mode"
		exit 0
	fi

	eval "$SSH_COMMAND &"
	eval "$TAR_COMMAND"

	RETURN_CODE=$?

	if [ "$RETURN_CODE" = "0" ]; then
		echo "Backup was successfull!"
	else
		echo "Backup failed!"
	fi

	rm $FIFO_FILE
}

function parseOptions() {
	while getopts "htfsdc:v" opt; do
		case $opt in
		h)
			usage
			exit 0
			;;
		t)
			TEST="true"
			;;
		f)
			FULL_BACKUP="true"
			;;
		s)
			SYNC_MODE="true"
			;;
		d)
			DELTA_MODE="true"
			;;
		c)
			CONFIG_FILE=$OPTARG
			;;
		v)
			VERBOSE="true"
			;;
		esac
	done
}

function usage() {
	echo "backmeup.sh v0.1"
	echo "Usage backmeup.sh [OPTIONS] [-c <Config File>] [-v]"
	echo "Options:"
	echo "  -h Display this help"
	echo "  -t Test mode"
	echo "  -f Full backup to backup server"
	echo "  -s Sync mode"
	echo "  -d Delta backup of changed files"

}

function readConfig() {
	getExclusions
	getDestinationData
	getPathes
	echo "env now"
	getEnvironment

	BACKUP_FILE=$BACKUP_NAME
	BACKUP_FILE+="_$(date +'%Y%m%d_%H%M').tar.gz"

	if [ "$VERBOSE" = "true" ]; then
		echo "Backup Name: $BACKUP_NAME"
		echo "Backup Host: $BACKUP_HOST"
		echo "Backup User: $BACKUP_USER"
		echo "Backup Path: $BACKUP_DIR"
		echo "Certificate: $CERTIFICATE"
		echo ""
		echo "Backup File: $BACKUP_FILE"
		echo ""
		echo "Source Pathes: $SOURCE_PATHES"
		echo "Exclusions   : $BACKUP_EXCLUDE"
	fi

}

function getEnvironment() {
	extractParamValues VAR_DIR
	VAR_DIR=$PARAM_VALUE
	if [ "$VAR_DIR" = "" ]; then
		VAR_DIR="/var/lib/backmeup"
	fi
echo "check $VAR_DIR"
	[ -d $VAR_DIR ] || echo "Directory $VAR_DIR doesn't exist" && exit 1
	echo "ok"
}

function getPathes() {
	extractParamValues PATH
	SOURCE_PATHES=$PARAM_VALUE
	checkMandatoryParamList "$SOURCE_PATHES" "source path"
}

function getDestinationData() {
	extractParamValues BACKUP_NAME
	BACKUP_NAME=$PARAM_VALUE
	checkUniqeMandatoryParam "$BACKUP_NAME" "backup name"

	extractParamValues BACKUP_HOST
	BACKUP_HOST=$PARAM_VALUE
	checkUniqeMandatoryParam "$BACKUP_HOST" "backup host"

	extractParamValues BACKUP_USER
	BACKUP_USER=$PARAM_VALUE
	checkUniqeMandatoryParam "$BACKUP_USER" "backup user"

	extractParamValues CERTIFICATE
	CERTIFICATE=$PARAM_VALUE
	checkUniqeMandatoryParam "$CERTIFICATE" "certificate file"

	extractParamValues PASS_PHRASE
	PASS_PHRASE=$PARAM_VALUE
	checkUniqeParam "$PASS_PHRASE" "pass phrase"

	extractParamValues BACKUP_DIR
	BACKUP_DIR=$PARAM_VALUE
	checkUniqeMandatoryParam "$BACKUP_DIR" "backup dir"
}

function extractParamValues {
	PARAM_VALUE=$(grep "^$1 *=" $CONFIG_FILE | sed "{ 
		s/^$1 *=//g
		s/ //g
		}")
}

function checkUniqeMandatoryParam() {
	if [ "$1" = "" ]; then
		echo "No $2 defined in $CONFIG_FILE!"
		exit 1
	fi

	local COUNT=$(echo $1 | wc -w)
	if [ $COUNT -gt "1" ]; then
		echo "Multiple $2s ($COUNT) defined in $CONFIG_FILE! Currently only one backup host is supported."
		exit 1
	fi
}

function checkUniqeParam() {
	local COUNT=$(echo $1 | wc -w)
	if [ $COUNT -gt "1" ]; then
		echo "Multiple $2s ($COUNT) defined in $CONFIG_FILE! Currently only one backup host is supported."
		exit 1
	fi
}

function checkMandatoryParamList() {
	if [ "$1" = "" ]; then
		echo "No $2 defined in $CONFIG_FILE!"
		exit 1
	fi
}

function getExclusions() {

	local BACKUP_EXCLUDE_CONFIG=$(grep '^EXCLUDE=' $CONFIG_FILE | sed s/^EXCLUDE=//g)

	local NETWORK_MOUNTS=$(mount | grep fuse.sshfs | sed '{ 
		s/^.* on //g;
		s/ type .*$//g;
	}')

	BACKUP_EXCLUDE=$(echo $BACKUP_EXCLUDE_CONFIG $NETWORK_MOUNTS)
}

main "$@"
