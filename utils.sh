#!/bin/bash


pass=""

makeKey() {
	key=$1
	file=$WARDEN_DIRECTORY/$key.md
	
	if [[ ! $key =~ ^[a-zA-Z0-9_]+$ ]]; then
		echo -e "${Red}Invalid ID"
		return
	fi

	if [ -f $file ]; then
		echo -e "${Red}File already exists"
		return
	fi

	read -p "Title? " title
	newLines=()
	newLines+=("$title")
	newLines+=("#etc")
	newLines+=("$DECRYPTED_ROW")
	newLines+=("Write your secrets here")
	printf "%s\n" "${newLines[@]}" > $file

	openKey "$key"
}

listKeys() {
	# Reads each file (linear), tab-prefixes each display row with its timestamp, and
	# lets `sort -n` do the ordering. This replaces the old O(n^2) bash insertion sort
	# (which forked an `expr` per arithmetic op and made `list` painfully slow); it is
	# fast, portable, and needs no compiler.
	keys=$(ls "$WARDEN_DIRECTORY")
	for key in $keys; do
		if [ "$key" == "master.md" ]; then
			continue
		fi
		file="$WARDEN_DIRECTORY/$key"
		title=$(head -n 1 "$file")
		hashtags=$(head -n 2 "$file" | tail -n 1)
		if [ "$hashtags" == "$ENCRYPTED_ROW" ]; then
			hashtags=""
		fi
		timestamp=$(tail -n 1 "$file")
		# <timestamp>\t<display row>. The display row contains no tabs, so cut can
		# strip the sort key afterwards.
		printf '%s\t%b- %s %b%s %b%s%b\n' \
			"$timestamp" "$Cyan" "$key" "$Color_Off" "$title" "$Purple" "$hashtags" "$Color_Off"
	done | sort -n -s -k1,1 | cut -f2-
}

findKeys() {
	read -p "Search: " searchTerm

	keys=$(ls $WARDEN_DIRECTORY)
	for key in $keys; do
		if [ "$key" == "master.md" ]; then
			continue
		fi
		file="$WARDEN_DIRECTORY/$key"
		title=$(head -n 1 $file)
		hashtags=$(head -n 2 $file | tail -n 1)
		if [ "$hashtags" == "$ENCRYPTED_ROW" ]; then
			hashtags=""
		fi
		
		if [[ $title != *"$searchTerm"* ]] && [[ $key != *"$searchTerm"* ]] && [[ $hashtags != *"$searchTerm"* ]]; then
			continue
		fi

		echo -e "${Cyan}- $key ${Color_Off}$title ${Purple}$hashtags${Color_Off}"
	done
}

listTags() {
	keys=$(ls $WARDEN_DIRECTORY)
	uniqueHashtags=()

	for key in $keys; do
		if [ "$key" == "master.md" ]; then
			continue
		fi
		file="$WARDEN_DIRECTORY/$key"
		hashtags=$(head -n 2 $file | tail -n 1)
		if [ "$hashtags" == "$ENCRYPTED_ROW" ]; then
			continue
		fi
		for hashtag in $hashtags; do
			if [[ ! " ${uniqueHashtags[*]} " =~ " ${hashtag} " ]]; then
				uniqueHashtags+=("$hashtag")
			fi
		done
	done

	for hashtag in "${uniqueHashtags[@]}"; do
		echo -e "- ${Purple}$hashtag${Color_Off}"
	done
}

encryptKey() {
	key=$1
	file=$WARDEN_DIRECTORY/$key.md

	if [ ! -f $file ]; then
		echo -e "${Red}File not found"
		exit 1
	fi

	checksum=$(shasum $file -a 256 | cut -d " " -f 1)

	didPassDecryptedRow=$FALSE
	newLines=()
	originalText=""
	while IFS= read -r line; do
	   	if [ "$line" == "$ENCRYPTED_ROW" ]; then
	   		# Already encrypted
	   		return
	   	fi
	    if [ "$line" == "$DECRYPTED_ROW" ]; then
	    	didPassDecryptedRow=$TRUE
	    	newLines+=("$ENCRYPTED_ROW")
	    	continue
	    fi
	    if [ $didPassDecryptedRow == $FALSE ]; then
	    	newLines+=("$line")
	    else
	    	originalText+="$line$NEW_LINE_CHAR"
	    fi
	done < $file

	if [ $didPassDecryptedRow == $FALSE ]; then
		echo -e "${Red}Format error: Did not find $DECRYPTED_ROW"
		exit 1
	fi

	indexInOriginalText=0
	blockBytes=0
	blockText=""
	lineNum=0 # used for showing progress only.

	for (( indexInOriginalText=0; indexInOriginalText<${#originalText}; indexInOriginalText++ )); do
		charValue="${originalText:$indexInOriginalText:1}"
		charBytes=$(echo -n "$charValue" | wc -c)
	    blockBytes=$(expr $blockBytes + $charBytes)
		blockText="$blockText$charValue"
		if [ $blockBytes -ge 12 ]; then # 16 (bytes per block) - 4 (max bytes per char) = 12
			blockBytes=0
			encryptedText=$(echo "$blockText" | openssl enc -aes-256-cbc -md sha512 -base64 -pbkdf2 -k "$pass" -iter 20000 -salt)
			newLines+=("$encryptedText")
			blockText=""
			lineNum=$(($lineNum + 1))
			echo "Encrypting line $lineNum ..."
		fi
	done

	if [ $blockBytes -gt 0 ]; then
		encryptedText=$(echo "$blockText" | openssl enc -aes-256-cbc -md sha512 -base64 -pbkdf2 -k "$pass" -iter 20000 -salt)
		newLines+=("$encryptedText")
	fi

	printf "%s\n" "${newLines[@]}" > $file
	echo -n $METADATA_ROW >> $file
	echo -n $'\n' >> $file
	echo -n $checksum >> $file
	echo -n $'\n' >> $file
	echo -n $(date +%s) >> $file
}

decryptKey() {
	key=$1
	outputMode=$2 # 1 = decrypt only, 2 = write to file, 3 = echo to stdout
	file=$WARDEN_DIRECTORY/$key.md

	if [ ! -f $file ]; then
		echo -e "${Red}File not found.${Color_Off}"
		exit 1
	fi
	if [ ! $outputMode -gt 0 ]; then
		echo -e "${Red}Invalid output mode.${Color_Off}"
		exit 1
	fi

	modifiedTimeMs=$(tail -n 1 $file)
	checksumBefore=$(tail -n 2 $file | head -n 1)
	didPassEncryptedRow=$FALSE
	newLines=()
	originalText=""
	while IFS= read -r line; do
	   	if [ "$line" == "$DECRYPTED_ROW" ]; then
	   		# Already decrypted
	   		return
	   	fi
	    if [ "$line" == "$ENCRYPTED_ROW" ]; then
	    	didPassEncryptedRow=$TRUE
	    	newLines+=("$DECRYPTED_ROW")
	    	continue
	    fi
		if [ "$line" == "$METADATA_ROW" ]; then
			break
		fi
	    if [ $didPassEncryptedRow == $FALSE ]; then
	    	newLines+=("$line")
	    else
	    	decryptedBlock=$(echo "$line" | openssl enc -aes-256-cbc -md sha512 -base64 -pbkdf2 -k "$pass" -iter 20000 -salt -d 2> /dev/null)
			if [ $? -eq 1 ]; then
				echo -e "${Red}Decryption failed. Wrong master password${Color_Off}"
				exit 1
			fi
			originalText="$originalText$decryptedBlock"
	    fi
	done < $file

	if [ $didPassEncryptedRow == $FALSE ]; then
		echo -e "${Red}Format error: Did not find $ENCRYPTED_ROW"
		exit 1
	fi

	originalTextLine=""
	for (( i=0; i<${#originalText}; i++ )); do
		charValue="${originalText:$i:1}"
		if [ "$charValue" == $NEW_LINE_CHAR ]; then
			newLines+=("$originalTextLine")
			originalTextLine=""
		else
			originalTextLine="$originalTextLine$charValue"
		fi
	done
	newLines+=("$originalTextLine")

	if [ $outputMode -eq 1 ]; then
		return
	fi

	numLines=${#newLines[@]}
	lineCount=0
	if [ $outputMode -eq 2 ]; then
		> $file;
	fi
	for newLine in "${newLines[@]}"; do
		if [ $outputMode -eq 2 ]; then
			printf "%s" "$newLine" >> $file
		else
			printf "%s" "$newLine"
		fi
		lineCount=$(expr $lineCount + 1)
		if [ $lineCount -lt $numLines ]; then
			if [ $outputMode -eq 2 ]; then
				printf "\n" >> $file
			else
				printf "\n"
			fi
		fi
	done

	if [ $outputMode -eq 3 ]; then
		return
	fi
	checksumAfter=$(shasum $file -a 256 | cut -d " " -f 1)
	if [ "$checksumBefore" == "$checksumAfter" ]; then
		echo -e "${Green}Checksum matches!${Color_Off}"
	else
		echo -e "${Red}Checksum does not match!${Color_Off}"

		read -p "Force open? [y] " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]
		then
			echo "Opening ..."
		else
			echo "Exiting ..."
			exit 1
		fi
	fi
}

deleteKey() {
	key=$1
	file=$WARDEN_DIRECTORY/$key.md

	if [ ! -f $file ]; then
		echo -e "${Red}File not found${Color_Off}"
		return
	fi

	read -p "Are you sure? [y] " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]
	then
		rm $file
		echo "Deleted $file"
	else
		echo "Canceled deletion"
	fi
}

lessKey() {
	key=$1
	file=$WARDEN_DIRECTORY/$key.md

	if [ ! -f $file ]; then
		echo -e "${Red}File not found${Color_Off}"
		return
	fi

	less -f <(decryptKey "$key" 3)
}

openKey() {
	key=$1
	file=$WARDEN_DIRECTORY/$key.md

	if [ ! -f $file ]; then
		echo -e "${Red}File not found${Color_Off}"
		return
	fi

	decryptKey "$key" 2
	vim "$file"
	encryptKey "$key"
}

renameKey() {
	key=$1
	newKey=$2
	file=$WARDEN_DIRECTORY/$key.md
	newFile=$WARDEN_DIRECTORY/$newKey.md

	if [ ! -f $file ]; then
		echo -e "${Red}File not found${Color_Off}"
		return
	fi

	if [ -f $newFile ]; then
		echo -e "${Red}File already exists${Color_Off}"
		return
	fi

	if [[ ! $newKey =~ ^[a-zA-Z0-9_]+$ ]]; then
		echo -e "${Red}Invalid ID for new file name${Color_Off}"
		return
	fi

	mv $file $newFile

	echo "Renamed $key.md -> $newKey.md"
}

encryptAll() {
	echo "Encrypting all keys ..."
	files=$(ls $WARDEN_DIRECTORY)
	for file in $files; do
		key=$(echo $file | cut -d. -f1)
		echo "Encrypting $key"
		encryptKey "$key"
	done
	echo "Encrypted all keys."
}

bootUp() {
	echo
	echo -e "${Purple}__          __           _            ${Color_Off}"
	echo -e "${Purple}\ \        / /          | |           ${Color_Off}"
	echo -e "${Purple} \ \  /\  / /_ _ _ __ __| | ___ _ __  ${Color_Off}"
	echo -e "${Purple}  \ \/  \/ / _\` | '__/ _\` |/ _ \ '_ \ ${Color_Off}"
	echo -e "${Purple}   \  /\  / (_| | | | (_| |  __/ | | |${Color_Off}"
	echo -e "${Purple}    \/  \/ \__,_|_|  \__,_|\___|_| |_|${Color_Off}"
	echo

	if [ ! -d "$WARDEN_DIRECTORY" ]; then
		echo -e "${Red}Could not find $WARDEN_DIRECTORY . ${Color_Off}"
		exit 1
	fi
                                       
	masterFile=$WARDEN_DIRECTORY/master.md

	if [ ! -f $masterFile ]; then
		echo -e "${BGreen}Welcome! This is your first time using this system.${Color_Off}"
		echo "You need to choose your master password."
		echo "Choose wisely because you can not change it later"
		echo

		echo -n "Choose your master password: "
		read -s passChoose1
		echo

		passLength=${#passChoose1}

		if [ $passLength -lt 10 ]; then
			echo -e "${Red}Password is too short. Min 10"
			exit 1
		fi
		
		if [ $passLength -gt 50 ]; then
			echo -e "${Red}Password is too long. Max 50"
			exit 1
		fi

		echo -n "Type it again to confirm: "
		read -s passChoose2
		echo

		if [ "$passChoose1" != "$passChoose2" ]; then
			echo -e "${Red}Passwords do not match."
			exit 1
		fi
		pass="$passChoose1"
		masterLines=("Master file" "$DECRYPTED_ROW" "Hello!")
		printf "%s\n" "${masterLines[@]}" > $masterFile
		encryptKey master
	else
		echo -e "${BGreen}Welcome back!${Color_Off}"
		echo

		echo -n "Master password: "
		read -s pass
		echo

		decryptKey master 1
	fi
	echo
}

showHelp() {
	echo -e "${Green}Available commands:${Color_Off}"
	echo "- exit            # exit"
	echo "- list            # list all files"
	echo "- find            # search files"
	echo "- tags            # list all hashtags"
	echo "- make FILENAME   # make a file"
	echo "- vim  FILENAME   # open & edit a file"
	echo "- less FILENAME   # open a file in read-only mode (faster & safer)"
	echo "- burn FILENAME   # delete a file"
	echo
	echo -e "${Green}Advanced commands:${Color_Off}"
	echo "- encrypt-all		# encrypt all files"
	echo "- rename A B 		# rename a file"
}

