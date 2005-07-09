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

	if [ -z $BM_BURNING_DEVICE ]; then
		error "MD5 checkup is only performed on CD media. Please set the BM_BURNING_DEVICE in $conffile."
	fi

	# first create the mount point
	mount_point="$(mktemp -d /tmp/bm-mnt.XXXXXX)"
	if [ ! -d $mount_point ]; then
		error "The mount point \$mount_point is not there"
	fi
	
	# mount the device in /tmp/
	info -n "Mounting \$BM_BURNING_DEVICE: "
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
		error "Errors encountered during MD5 controls."
	fi

	# remove the mount point
	umount $BM_BURNING_DEVICE || error "unable to unmount the mount point \$mount_point"
	rmdir $mount_point || error "unable to remove the mount point \$mount_point"
}

# this will try to burn the generated archives to the media
# choosed in the configuration.
# Obviously, we will use mkisofs for generating the iso and 
# cdrecord for burning CD, growisofs for the DVD.
# Note that we pipe the iso image directly to cdrecord
# in this way, we prevent the use of preicous disk place.
burn_files()
{
	if [ "$BM_BURNING" != "yes" ]; then
		info "The burning system is disabled in the conf file."
		return 0
	fi
	
	# determine what to burn according to the size...
	what_to_burn=""
	size=$(size_of_path "$BM_ARCHIVES_REPOSITORY")
	if [ $size -gt $BM_BURNING_MAXSIZE ]; then
		size=$(size_of_path "${BM_ARCHIVES_REPOSITORY}/*${TODAY}*")
		if [ $size -gt $BM_BURNING_MAXSIZE ]; then
			error "Cannot burn archives of the \$TODAY, too big: \${size}M, must fit in \$BM_BURNING_MAXSIZE"
		else
			# let's take all the regular files from today
			for file in ${BM_ARCHIVES_REPOSITORY}/*${TODAY}*
			do
				# we only take the regular files, not the symlinks
				if [ ! -L $file ]; then
					what_to_burn="$what_to_burn $file"
				fi
			done		
		fi
	else
		# let's take all the regular files from today
		for file in ${BM_ARCHIVES_REPOSITORY}
		do
			# we only take the regular files, not the symlinks
			if [ ! -L $file ]; then
				what_to_burn="$what_to_burn $file"
			fi
		done		
	fi

	title="Backups_${TODAY}"
	
	# Let's un mount the device first
	umount $BM_BURNING_DEVICE || warning "Unable to unmount the device \$BM_BURNING_DEVICE"
	
	# get a log file in a secure path
	logfile="$(mktemp /tmp/bm-cdrecord.log.XXXXXX)"
	info "Redirecting cdrecord logs into \$logfile"
	
	# set the cdrecord command 
	devforced=""
	if [ -n "$BM_BURNING_DEVFORCED" ]; then
		info "Forcing dev=${BM_BURNING_DEVFORCED} for cdrecord commands"
		devforced="dev=${BM_BURNING_DEVFORCED}"
	fi
	
	# burning the iso with the user choosen method
	case "$BM_BURNING_METHOD" in
		"CDRW")
			info -n "Blanking the CDRW in \$BM_BURNING_DEVICE: "
			${cdrecord} -tao $devforced blank=fast > ${logfile} 2>&1 ||
				error "failed, check \$logfile"
			info "ok"
			
			info -n "Burning data to \$BM_BURNING_DEVICE: "
			${mkisofs} -V "${title}" -q -R -J ${what_to_burn} | \
			${cdrecord} -tao $devforced - > ${logfile} 2>&1 ||
				error "failed, check \$logfile"
			info "ok"
		;;
		"CDR")
			info -n "Burning data to \$BM_BURNING_DEVICE: "
			${mkisofs} -V "${title}" -q -R -J ${what_to_burn} | \
			${cdrecord} -tao $devforced - > ${logfile} 2>&1 ||
				error "failed, check \$logfile"
			info "ok"
		;;
	esac
	
	# Cleaning the logile, everything was fine at this point.
	rm -f $logfile

	# checking the files in the CDR if wanted
	if [ $BM_BURNING_CHKMD5 = yes ] 
	then
		check_cdrom_md5_sums
	fi
}


make_archives()
{
	# FIXME currently, only one backup method is supported : default.
	if [ -z "$BM_BACKUP_METHOD" ]; then
		BM_BACKUP_METHOD="default"
	fi

	# do we have to use a pipe method? 
	if [ $(expr match "$BM_BACKUP_METHOD" "|") -gt 0 ]; then
		info "Using the \"pipe\" backup method"
		backup_method_pipe

	# The known methods
	else
		case $BM_BACKUP_METHOD in
		
		mysql)
			info "Using the \"mysql\" backup method"
			backup_method_mysql
		;;
		rsync)
			info "Using the \"rsync\" backup method"
			backup_method_rsync
		;;

		# default behaviour is to make a tarball with BM_FILETYPE 
		*)
			info "Using the \"tarball\" backup method"
			backup_method_tarball
		;;

		esac
	fi
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
		
		if [ -z "$BM_FTP_PURGE" ] || 
		   [ "$BM_FTP_PURGE" = "no" ]; then
		   	ftp_purge=""
		else
			ftp_purge="--ftp-purge"
		fi
		
		servers=`echo $BM_UPLOAD_HOSTS| sed 's/ /,/g'`
		if [ "$BM_UPLOAD_MODE" == "ftp" ]; then
			$bmu $v $ftp_purge \
				-m="$BM_UPLOAD_MODE" \
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
	if [ ! -z "$BM_POST_BACKUP_COMMAND" ]; then
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
