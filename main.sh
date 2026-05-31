#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/colors.sh"
. "$SCRIPT_DIR/config.sh"
. "$SCRIPT_DIR/utils.sh"

if [ -z "$WARDEN_DIRECTORY" ]; then
	echo -e "${Red}WARDEN_DIRECTORY environment variable is not set. Set it to your warden data directory and try again.${Color_Off}" >&2
	exit 1
fi

if [ ! -d "$WARDEN_DIRECTORY" ]; then
	echo -e "${Red}WARDEN_DIRECTORY ('$WARDEN_DIRECTORY') is not a valid directory. Set it to an existing warden data directory and try again.${Color_Off}" >&2
	exit 1
fi

bootUp

while [ 1 ]
do
	echo -e -n "${BYellow}"
	read -p "WARDEN > " commandText
	echo -e -n "${Color_Off}"

	if [ "$commandText" == "list" ]; then
		listKeys
		echo
		continue
	fi

	commandArray=($commandText)
	arrayLength=${#commandArray[@]}
	commandType="${commandArray[0]}"

	case "$commandType" in
		"make" | "vim" | "less" | "burn")
			if [ $arrayLength -ne 2 ]; then
				echo -e "${Red}Please provide a ID."
				continue
			fi
			;;
		"rename")
			if [ $arrayLength -ne 3 ]; then
				echo -e "${Red}Syntax: rename A B"
				continue
			fi
			;;
		*)
			if [ $arrayLength -ne 1 ]; then
				echo -e "${Red}Unexpected extra argument."
				continue
			fi
			;;
	esac
	
	case "$commandType" in
		"exit")
			echo Goodbye
			exit 0
			;;
		"help")
			showHelp
			;;
		"find")
			findKeys
			;;
		"tags")
			listTags
			;;
		"make")
			makeKey "${commandArray[1]}"
			;;
		"vim")
			openKey "${commandArray[1]}"
			;;
		"less")
			lessKey "${commandArray[1]}"
			;;
		"burn")
			deleteKey "${commandArray[1]}"
			;;
		"rename")
			renameKey "${commandArray[1]}" "${commandArray[2]}"
			;;
		"encrypt-all")
			encryptAll
			;;
		*)
			echo -e "${Red}Unknown command. Type help"
			;;
	esac

	sleep 0.25
	echo
done

