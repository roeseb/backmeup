#!/bin/bash


CONFIG_FILE="backmeup.cfg"

function main() {
	parseOptions "$@"
	readConfig

	local TEMP_FOLDER=`mktemp -d -p /tmp backmeup.XXXXXXXX`
	local EXCLUDE_TEMP_FILE=$TEMP_FOLDER"/exclude.txt"
	local FIFO_FILE=$TEMP_FOLDER"/ssh.pipe"

	echo $BACKUP_EXCLUDE | sed 's/ /\n/g' > $EXCLUDE_TEMP_FILE
    mkfifo $FIFO_FILE


	BACKUP_FILE_FULL_PATH=`echo $BACKUP_DIR | sed 's/\/ *$//g'`
	BACKUP_FILE_FULL_PATH+="/$BACKUP_FILE"

	TAR_OPTIONS="cz"

	if [ "$VERBOSE" = 'true' ]
	then
		TAR_OPTIONS+="v"
	fi


	TAR_OPTIONS+="f"


	TAR_COMMAND="tar --exclude-from $EXCLUDE_TEMP_FILE -$TAR_OPTIONS - $SOURCE_PATHES > $FIFO_FILE"
	SSH_COMMAND="cat $FIFO_FILE | ssh -i $CERTIFICATE $BACKUP_USER@$BACKUP_HOST \"cat > $BACKUP_FILE_FULL_PATH\""

	if [ "$VERBOSE" = "true" ]
	then
		echo ""
		echo "Starting backup"
		echo $COMMAND
	fi

	if [ "$SIMULATE" = "true" ]
	then
		echo "Simulation mode"
		exit 0
	fi

    eval "$SSH_COMMAND &"
	eval "$TAR_COMMAND"

	RETURN_CODE=$?

    if [ "$RETURN_CODE" = "0" ]
    then
        echo "Backup was successfull!"
    else
        echo "Backup failed!"
    fi

	if [ "$VERBOSE" = "true" ]
	then
		echo "Cleaning up"
	fi

	sleep 1

	rm $EXCLUDE_TEMP_FILE
	rm $FIFO_FILE
	rmdir $TEMP_FOLDER

	if [ "$VERBOSE" = "true" ]
	then
		echo "Done"
	fi

	exit $RETURN_CODE
}


#ddBACKUP=tar czvf / --exclude /dev /proc /tmp/ 


function parseOptions() {
	while getopts "hc:vs" opt 
	do
		case $opt in
			h) 
				usage 
				exit 0
			        ;;
			c) 
				CONFIG_FILE=$OPTARG 
				;;
			v)
				VERBOSE="true"
				;;
			s)
				SIMULATE="true"
				;;
		esac
	done
}

function usage() {
   echo "backmeup.sh v0.1"
   echo "Usage backmeup.sh [-h]"

}

function readConfig() {
	getExclusions
	getDestinationData
	getPathes

	BACKUP_FILE=$BACKUP_NAME
	BACKUP_FILE+="_`date +'%Y%m%d_%H%M'`.tar.gz"

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
	PARAM_VALUE=`grep "^$1 *=" $CONFIG_FILE | sed "{ 
		s/^$1 *=//g
		s/ //g
		}"`
}

function checkUniqeMandatoryParam() {
	if [ "$1" = "" ]
	then
			echo "No $2 defined in $CONFIG_FILE!"
			exit 1
	fi


	local COUNT=`echo $1 | wc -w`
    if [ $COUNT -gt "1" ]
	then
			echo "Multiple $2s ($COUNT) defined in $CONFIG_FILE! Currently only one backup host is supported."
			exit 1
	fi
}

function checkUniqeParam() {
	local COUNT=`echo $1 | wc -w`
    if [ $COUNT -gt "1" ]
	then
			echo "Multiple $2s ($COUNT) defined in $CONFIG_FILE! Currently only one backup host is supported."
			exit 1
	fi
}

function checkMandatoryParamList() {
	if [ "$1" = "" ]
	then
			echo "No $2 defined in $CONFIG_FILE!"
			exit 1
	fi
}

function getExclusions() {

	local BACKUP_EXCLUDE_CONFIG=`grep '^EXCLUDE='	 $CONFIG_FILE | sed s/^EXCLUDE=//g`

	local NETWORK_MOUNTS=`mount | grep fuse.sshfs | sed '{ 
		s/^.* on //g;
		s/ type .*$//g;
	}' `

	BACKUP_EXCLUDE=`echo $BACKUP_EXCLUDE_CONFIG $NETWORK_MOUNTS`
}

main "$@"