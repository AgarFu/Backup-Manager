#
# The backup-manager's actions.sh library.
#
# Every major feature of backup-manager is here.
#


# This will get all the md5 sums of the day,
# mount the BM_BURNING_DEVICE on /tmp/device and check 
# that the files are correct with md5 tests.
check_cdrom_md5_sums()
{
	has_error=0

	# first be sure that the mount point 
	# is not already used.
	if [ -d $mount_point ]; then
		error "The mount point \$mount_point is already there, remove it if needed"
	fi
	
	# mount the device in /tmp/
	info -n "Mounting \$BM_BURNING_DEVICE: "
	mkdir $mount_point || error "unable to create the mount point \$mount_point"
	mount $BM_BURNING_DEVICE $mount_point >& /dev/null || error "unable to mount \$BM_BURNING_DEVICE on \$mount_point"
	info "ok"
	export HAS_MOUNTED=1
	
	# now we can check the md5 sums.
	for file in $mount_point/*
	do
		base_file=$(basename $file)
		date_of_file=$(get_date_from_file $file)
		prefix_of_file=$(get_prefix_from_file $file)
		info -n "Checking MD5 sum for \$base_file: "
		
		# Which file should contain the MD5 hashes for that file ?
		md5_file="$BM_ARCHIVES_REPOSITORY/${prefix_of_file}-${date_of_file}.md5"

		# if it does not exists, we create it (yes that will take much time).
		if [ ! -f $md5_file ]; then
			save_md5_sum $file $md5_file || continue
		fi
		
		# try to read the previously saved md5 hash in the file
		md5hash_trust=$(get_md5sum_from_file ${base_file} $md5_file)

		# If the MD5 hash was not found, generate it and save it now.
		if [ -z "$md5hash_trust" ]; then
			save_md5_sum $file $md5_file || continue
			md5hash_trust=$(get_md5sum_from_file ${base_file} $md5_file)
		fi
		
		md5hash_cdrom=$(get_md5sum $file) || md5hash_cdrom="undefined"
		case "$md5hash_cdrom" in
			"$md5hash_trust")
				info "ok"
			;;
			"undefined")
				info "failed (read error)"
				has_error=1
			;;
			*)
				info "failed (MD5 hash mismatch)"
				has_error=1
			;;
		esac
	done

	if [ $has_error = 1 ]; then
		error "Error during MD5 controls. Run \$0 --md5check --verbose for details"
	fi

	# remove the mount point
	umount $BM_BURNING_DEVICE
	rmdir $mount_point
}

# this will try to burn the generated archives to the media
# choosed in the configuration.
# Obviously, we will use mkisofs for generating the iso and 
# cdrecord for burning CD, growisofs for the DVD.
# Note that we pipe the iso image directly to cdrecord
# in this way, we prevent the use of preicous disk place.
burn_files()
{
	if 	[ -z "$BM_BURNING" ] ||
		[ "$BM_BURNING" = "no" ]; then
		info "The automatic burning system is disabled in the conf file."
	else
		if [ -z "$BM_BURNING_MEDIA" ]; then
			info "Please set the BM_BURNING_MEDIA conf key in \$conffile, I assume you want 'cdrom'"
			export BM_BURNING_MEDIA="cdrom"
		fi

		if [ -z "$BM_BURNING_DEVICE" ]; then
			info "Please set the BM_BURNING_DEVICE conf key in \$conffile, I assume you want '/dev/cdrom'"
			export BM_BURNING_DEVICE="/dev/cdrom"
		fi

		if [ -z "$BM_BURNING_METHOD" ]; then
			info "Please set the BM_BURNING_METHOD conf key in \$conffile, I assume you want 'CDRW'"
			export BM_BURNING_METHOD="CDRW"
		fi

		if [ -z "$BM_BURNING_MAXSIZE" ]; then
			info "Please set the BM_BURNING_MAXSIZE conf key in \$conffile, I assume you want '650'"
			export BM_BURNING_MAXSIZE="650"
		fi

		# determine what to burn according to the size...
		what_to_burn=""
		size=$(size_of_path "$BM_ARCHIVES_REPOSITORY")
		if [ $size -gt $BM_BURNING_MAXSIZE ]; then
			size=$(size_of_path "${BM_ARCHIVES_REPOSITORY}/*${TODAY}*")
			if [ $size -gt $BM_BURNING_MAXSIZE ]; then
				error "Cannot burn archives of the \$TODAY, too big : \${size}M, must fit in \$BM_BURNING_MAXSIZE"
			else
				what_to_burn="${BM_ARCHIVES_REPOSITORY}/*${TODAY}*"
			fi
		else
			what_to_burn="$BM_ARCHIVES_REPOSITORY"
		fi

		title="Backups_${TODAY}"
		
		# burning the iso with the user choosen method
		case "$BM_BURNING_METHOD" in
			"CDRW")
                                info -n "Blanking the CDRW in \$BM_BURNING_DEVICE: "
                                ${cdrecord} -tao dev=${BM_BURNING_DEVICE} blank=all > ${logfile} 2>&1 ||
                                        error "failed"
				info "ok"
				
                                info -n "Burning data to \$BM_BURNING_DEVICE: "
                                ${mkisofs} -V "${title}" -q -R -J ${what_to_burn} | \
                                ${cdrecord} -tao dev=${BM_BURNING_DEVICE} - > ${logfile} 2>&1 ||
                                        error "failed"
				info "ok"
			;;
			"CDR")
			        info -n "Burning data to \$BM_BURNING_DEVICE: "
                                ${mkisofs} -V "${title}" -q -R -J ${what_to_burn} | \
                                ${cdrecord} -tao dev=${BM_BURNING_DEVICE} - > ${logfile} 2>&1 ||
                                        error "failed"
				info "ok"
			;;
		esac
	
		# checking the burnt files 
		check_cdrom_md5_sums
		
		# cleaning 
		rm -f $logfile
	fi

}


make_archives()
{

	# First, we read some conf keys.
	
	# Create the directories blacklist
	blacklist=""
	for pattern in $BM_DIRECTORIES_BLACKLIST
	do
		blacklist="$blacklist --exclude=$pattern"
	done
	
	# Set the -h flag according to the $BM_DUMP_SYMLINKS conf key
	h=""
	if [ ! -z $BM_DUMP_SYMLINKS ]; then
		if [ "$BM_DUMP_SYMLINKS" = "yes" ] ||
		   [ "$BM_DUMP_SYMLINKS" = "true" ]; then
			h="-h "
		fi
	fi

	for DIR in $BM_DIRECTORIES
	do
		dir_name=$(get_dir_name $DIR $BM_NAME_FORMAT)
		file_to_create="$BM_ARCHIVES_REPOSITORY/$BM_ARCHIVES_PREFIX$dir_name.$TODAY.$BM_FILETYPE"
		
		
		if [ ! -f $file_to_create ] ||
		   [ $force = true ]; then
		   	
			info -n "Creating \$file_to_create: "
			case $BM_FILETYPE in
				tar.gz) # generate a tar.gz file if needed 
					$tar $blacklist $h -c -z -f "$file_to_create" "$DIR" > /dev/null 2>&1 || info -n '~'
				;;
				tar.bz2|tar.bz) # generate a tar.bz2 file if needed
					$tar $blacklist $h -c -j -f "$file_to_create" "$DIR" > /dev/null 2>&1 || info '~'
				;;
				tar) # generate a tar file if needed
					$tar $blacklist $h -c -f "$file_to_create" "$DIR" > /dev/null 2>&1 || info '~'
				;;
				zip) # generate a zip file if needed
					$zip -r "$file_to_create" "$DIR" > /dev/null 2>&1 || info '~'
				;;
				*) # unknown option
					info "failed"
					error "The filetype \$BM_FILETYPE is not spported."
					_exit
				;;
			esac
			size=$(size_of_path $file_to_create)
			info -n "ok (\${size}M, "
	 		
			base=$(basename $file_to_create)
			md5hash=$(get_md5sum $file_to_create)
			info "${md5hash})"
			echo "$md5hash $base" >> $BM_ARCHIVES_REPOSITORY/${BM_ARCHIVES_PREFIX}-${TODAY}.md5
		else
			warning "File \$file_to_create already exists, skipping."
		fi
	done
}

# This will parse all the files contained in BM_ARCHIVES_REPOSITORY
# and will clean them up. Using clean_directory() and clean_file().
clean_repositories()
{
	info "Cleaning \$BM_ARCHIVES_REPOSITORY: "
	clean_directory $BM_ARCHIVES_REPOSITORY
}


# This is the call to backup-manager-upload 
# with the appropriate options.
# This will upload the files with scp or ftp.
upload_files ()
{
	if [ -n "$BM_UPLOAD_HOSTS" ] 
	then
		if [ "$verbose" == "true" ]; then
			v="-v"
		else
			v=""
		fi
		
		servers=`echo $BM_UPLOAD_HOSTS| sed 's/ /,/g'`
		if [ "$BM_UPLOAD_MODE" == "ftp" ]; then
			$bmu $v -m="$BM_UPLOAD_MODE" \
				-h="$servers" \
				-u="$BM_UPLOAD_USER" \
				-p="$BM_UPLOAD_PASSWD" \
				-d="$BM_UPLOAD_DIR" \
				-r="$BM_ARCHIVES_REPOSITORY" today || error "unable to call backup-manager-upload"
		else
			if [ ! -z "$BM_UPLOAD_KEY" ]; then
				key_opt="-k=\"$BM_UPLOAD_KEY\""
			else
				key_opt=""
			fi
			su $BM_UPLOAD_USER -s /bin/sh -c \
			"$bmu $v -m="$BM_UPLOAD_MODE" \
				-h="$servers" \
				-u="$BM_UPLOAD_USER" $key_opt \
				-d="$BM_UPLOAD_DIR" \
				-r="$BM_ARCHIVES_REPOSITORY" today" || error "unable to call backup-manager-upload"
		fi
	else
		info "The upload system is disabled in the conf file."
	fi
}

# This will run the pre-command given.
# If this command prints on STDOUT "false", 
# backup-manager will stop here.
exec_pre_command()
{
	if [ ! -z "$BM_PRE_BACKUP_COMMAND" ]; then
		info -n "Running pre-command: \$BM_PRE_BACKUP_COMMAND: "
		RET=`$BM_PRE_BACKUP_COMMAND` || RET="false" 
		case "$RET" in
			"false")
				info "failed"
				warning "pre-command returned false. Stopping the process."
				_exit 0
			;;

			*)
				info "ok"
			;;
		esac
	fi

}

exec_post_command()
{
	if [ -n $BM_POST_BACKUP_COMMAND ]; then
		info -n "Running post-command: \$BM_POST_BACKUP_COMMAND: "
		RET=`$BM_POST_BACKUP_COMMAND` || RET="false"
		case "$RET" in
			"false")
				info "failed"
				warning "post-command returned false."
			;;

			*)
				info "ok"
			;;
		esac
	fi
}
