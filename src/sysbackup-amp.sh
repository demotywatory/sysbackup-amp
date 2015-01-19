#!/bin/sh

# Set the field separator to a literal tab and newline.
IFS="
"

# Set default program options.
opt_opt_error=0
opt_debug=''
opt_quiet=''
opt_verbose=''
opt_dry_run=''
opt_syslog=''
opt_prefix='sysbackup'
opt_label=''
opt_sep='_'
opt_keep=''
opt_backup_folder=''
opt_exclude=''
opt_auto=''
opt_mutithreaded=''

ret_stdout=''
ret_stderr=''

rsync_exclude=''

CREATION_COUNT='0'
WARNING_COUNT='0'
DESTRUCTION_COUNT='0'

get_options () # [argv]
{
GETOPT=$(getopt \
  --longoptions=debug,help,quiet,dry-run,syslog,verbose,label:,keep:,exclude:,folder:,auto,multi,multithreaded \
  --options=dhqnsvl:k:x:f:am \
  -- "$@" ) \
  || opt_opt_error=1

if [ $opt_opt_error != 0 ] ; then
    print_usage
    exit 128;
    fi

eval set -- "$GETOPT"

while [ "$#" -gt '0' ]
do
	case "$1" in
		(-d|--debug)
			opt_debug='1'
			opt_quiet=''
			opt_verbose='1'
			shift 1
			;;
		(-h|--help)
			print_usage
			exit 0
			;;
		(-q|--quiet)
			opt_debug=''
			opt_quiet='1'
			opt_verbose=''
			shift 1
			;;
		(-n|--dry-run)
			opt_dry_run='1'
			shift 1
			;;
		(-s|--syslog)
			opt_syslog='1'
			shift 1
			;;
		(-v|--verbose)
			opt_quiet=''
			opt_verbose='1'
			shift 1
			;;
		(-l|--label)
			opt_label="$2"
			shift 2
			;;
		(-f|--folder)
			opt_backup_folder="$2"
			shift 2
			;;
		(-k|--keep)
			if ! test "$2" -gt '0' 2>/dev/null
			then
				print_log error "The $1 parameter must be a positive integer."
				exit 129
			fi
			opt_keep="$2"
			shift 2
			;;
		(-x|--exclude)
            if [ -z "$opt_exclude" ]
            then
                opt_exclude="$2"
            else
                opt_exclude="$opt_exclude
$2"
            fi
			shift 2
			;;
		(-a|--auto)
			opt_auto='1'
			shift 1
			;;
		(-m|--multi|--multithreaded)
			opt_mutithreaded="1"
			shift 1
			;;
		(--)
			shift 1
			break
			;;
	esac
done
}

print_usage ()
{
	echo "Usage: $0 [options]
  -d, --debug        Print debugging messages.
  -h, --help         Print this usage message.
  -q, --quiet        Suppress warnings and notices at the console.
  -n, --dry-run      Print actions without actually doing anything.
  -s, --syslog       Write messages into the system log.
  -v, --verbose      Print info messages.
  -l, --label=LAB    LAB is usually 'hourly', 'daily', or 'monthly'.
  -k, --keep=NUM     Keep NUM recent backups and destroy older backups.
  -x, --exclude=EX   Exclude folder from syncing. For multiple folders use multiple times.
  -a, --auto         Automatically set 'label' and 'keep'
  -m, --multi        Use pigz - Parallel Implementation of GZip.
"
}

print_log () # level, message, ...
{
	LEVEL=$1
	shift 1
	case $LEVEL in
		(eme*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.emerge "$*"
			echo Emergency: "$*" 1>&2
			;;
		(ale*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.alert "$*"
			echo Alert: "$*" 1>&2
			;;
		(cri*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.crit "$*"
			echo Critical: "$*" 1>&2
			;;
		(err*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.err "$*"
			echo Error: "$*" 1>&2
			;;
		(war*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.warning "$*"
			test -z "$opt_quiet" && echo Warning: "$*" 1>&2
			;;
		(not*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.notice "$*"
			test -z "$opt_quiet" && echo "$*"
			;;
		(inf*)
			# test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.info "$*"
			test -n "$opt_verbose" && echo "$*"
			;;
		(deb*)
			# test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.debug "$*"
			test -n "$opt_debug" && echo Debug: "$*"
			;;
		(*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" "$*"
			echo "$*" 1>&2
			;;
	esac
}

do_run () # [argv]
{
    if [ -n "$opt_dry_run" ]; then
        print_log info "Dry run: ${*}"
#        RC="$?"
    else
        if [ -n "opt_debug" ]; then
            print_log debug "Executing command: $*"
        fi

#        ret_stdout=''
        ret_stderr=''

#        TMP=$(mktemp)
#	TMPOUT=$(mktemp)
	TMPERR=$(mktemp)
#        ret_stdout=$( eval $* 2> "$TMP")
        eval $* 2> "$TMPERR"
#        eval $* 2> "$TMPERR" | tee "$TMPOUT"
#        ret_stderr=$(cat "$TMP")
#        ret_stdout=$(cat "$TMPOUT")
        ret_stderr=$(cat "$TMPERR")
#        rm "$TMP"
        rm "$TMPERR"
#        RC=ret_stdout

#        print_log debug "Command stdout: $ret_stdout"
#        print_log debug "Command stderr: $ret_stderr"

        if [ -n "$ret_stderr" ]; then
            print_log warning "$* returned stderr: $ret_stderr"
        fi
    fi
}

do_rsync ()
{
print_log info "Start rsyncing"
if [ -n "$opt_verbose" ]
then
#    do_run "rsync -avx --progress --delete --one-file-system ${rsync_exclude} / ${FOLDER_RSYNC}"
    do_run "rsync -av --progress --delete ${rsync_exclude} / ${FOLDER_RSYNC}"
elif [ -n "$opt_quiet" ]
then
#    do_run "rsync -aqx --progress --delete --one-file-system ${rsync_exclude} / ${FOLDER_RSYNC}"
    do_run "rsync -aq --progress --delete ${rsync_exclude} / ${FOLDER_RSYNC}"
else
#    do_run "rsync -ax --progress --delete --one-file-system ${rsync_exclude} / ${FOLDER_RSYNC} | sed '0,/^$/d'"
    do_run "rsync -a --progress --delete ${rsync_exclude} / ${FOLDER_RSYNC} | sed '0,/^$/d'"
fi
if [ "$?" -ne 0 ]
then
    exit $?
fi
}

do_tar ()
{
print_log info "Start taring"
print_log debug "Start taring"
if [ -n "$opt_verbose" ]; then
    if [ -n "$opt_mutithreaded" ]; then
        do_run "tar -cpv -I pigz --totals -f $TARFILE -C ${FOLDER_RSYNC} . 2>&1"
    else
        do_run "tar -cpvz --totals -f $TARFILE -C ${FOLDER_RSYNC} . 2>&1"
    fi

else
    if [ -n "$opt_mutithreaded" ]; then
        do_run "tar -cp -I pigz -f $TARFILE -C ${FOLDER_RSYNC} . 2>&1"
    else
        do_run "tar -cpz -f $TARFILE -C ${FOLDER_RSYNC} . 2>&1"
    fi

fi

if [ "$?" -ne 0 ]; then
    exit $?
fi
CREATION_COUNT=$(( $CREATION_COUNT + 1 ))
}

do_delete ()
{
if [ -n "$opt_label" ]
then
    BCKPLIST=$(env LC_ALL=C ls -1tl $opt_backup_folder | grep ^- | awk '{print $9}' | grep ${opt_prefix}${opt_sep}${opt_label}${opt_sep}) || { print_log warning "Cannot list backups or there is no backups to list."; return 1; }
else
    BCKPLIST=$(env LC_ALL=C ls -1tl $opt_backup_folder | grep ^- | awk '{print $9}' | grep ${opt_prefix}${opt_sep}) || { print_log warning "Cannot list backups or there is no backups to list."; return 1; }
fi
print_log debug "Backups list:\n$BCKPLIST"

KEEP=$opt_keep

for OLDBCKP in $BCKPLIST
do
    print_log debug "Backup deleting loop. File: $OLDBCKP, keep counter: $KEEP"
    if [ "$KEEP" -le '0' ]
    then
        DELFILE="${opt_backup_folder}/${OLDBCKP}"
        print_log debug "Keep counter < 1, delete backup file $DELFILE"
        if [ -n "$opt_verbose" ]
        then
            do_run "rm -v $DELFILE"
        else
            do_run "rm $DELFILE"
        fi

        #if [ "$?" -ne 0 ]
        if [ -n "$ret_stderr" ]
        then
            WARNING_COUNT=$(( $WARNING_COUNT + 1 ))
        else
            DESTRUCTION_COUNT=$(( $DESTRUCTION_COUNT + 1 ))
        fi
    fi
    KEEP=$(( $KEEP - 1 ))
done
}

# main ()
# {

# Get options.
get_options $@

print_log debug "Start program. (Input options have been processed.)"

# Test requied programs
print_log debut "Checking if all requied programs (rsync, tar, gzip or pizg) are available."
command -v rsync >/dev/null 2>&1 || { print_log error "This program requires rsync but it's not installed. Aborting."; exit 1; }
command -v tar >/dev/null 2>&1 || { print_log error "This program requires tar but it's not installed. Aborting."; exit 1; }
if [ -n "$opt_mutithreaded" ]; then
    command -v pigz >/dev/null 2>&1 || { print_log error "This program requires pigz (Parallel Implementation of GZip) but it's not installed. Aborting."; exit 1; }
else
    command -v gzip >/dev/null 2>&1 || { print_log error "This program requires gzip but it's not installed. Aborting."; exit 1; }
fi

# In auto mode automatically set 'label' and 'keep'
if [ -n "$opt_auto" ]; then
    print_log debug "Auto mode - set 'label' and 'keep' from day-of-month and day-of-week."
    DOM=$(date +%d)
    DOW=$(date +%w)

    if [ "$DOM" -eq 3 ]
    then
            opt_label='monthly'
            opt_keep=''
    elif [ "$DOW" -eq 6 ]
    then
            opt_label='weekly'
            opt_keep='4'
    else
            opt_label='daily'
            opt_keep='7'
    fi
    print_log debug "Auto mode set label=${opt_label} and keep=${opt_keep}"
fi


# ISO style date; fifteen characters: YYYY-MM-DD-HHMM
# On Solaris %H%M expands to 12h34.
DATE=$(date --utc +%F-%H%M)
print_log debug "Use date (UTC) : $DATE"

# Check backup folder
if [ -z "$opt_backup_folder" ]; then
    print_log info "Backup folder not specified, using PWD"
    opt_backup_folder="$PWD"
fi
print_log debug "Using backup folder: $opt_backup_folder"

# Prepare folder for rsyncing
print_log debug "Prepare folder for newest rsync"
FOLDER_RSYNC="${opt_backup_folder}/${opt_prefix}"
print_log debug "Backup folder: $FOLDER_RSYNC"
do_run "mkdir -p $FOLDER_RSYNC"
if [ "$?" -ne 0 ]
then
    exit $?
fi

# Create exclude
#if [ -z "$opt_exclude" ]
#then
#    print_log debug "No folders to exclude from rsync. Excluding backup folder"
#    opt_exclude=$opt_backup_folder
#fi
rsync_exclude="--exclude ${opt_backup_folder} --exclude /proc --exclude /dev --exclude /sys --exclude /run"
for ii in $opt_exclude
do
    rsync_exclude="$rsync_exclude --exclude ${ii}"
done
print_log debug "rsync_exclude: $rsync_exclude"

# Proceed rsync
do_rsync

# Prepare tarball file name
print_log debug "Prepare tarball file name"
if [ -n "$opt_label" ]; then
    TARFILE="${opt_backup_folder}/${opt_prefix}${opt_sep}${opt_label}${opt_sep}${DATE}.tgz"
else
    TARFILE="${opt_backup_folder}/${opt_prefix}${opt_sep}${DATE}.tgz"
fi
print_log debug "Tar file: $TARFILE"

# Proceed tar
do_tar

# Find and delete too old tars
if [ -n "$opt_keep" ] && [ "$opt_keep" -gt 0 ]; then
    print_log debug "Deleting old backups."
    do_delete
fi

if [ -n "$opt_label" ]; then
    BACKUPNAME="${opt_prefix}${opt_sep}${opt_label}${opt_sep}${DATE}.tgz"
else
    BACKUPNAME="${opt_prefix}${opt_sep}${DATE}.tgz"
fi

# Write last filename into file
print_log debug "Write last filename into file"

LASTFILE="${opt_backup_folder}/${opt_prefix}.latest"
print_log debug "Last file name: ${LASTFILE}"

do_run "echo ${TARFILE} > ${LASTFILE}"

# Summary
print_log notice "$BACKUPNAME: $CREATION_COUNT created, $DESTRUCTION_COUNT destroyed, $WARNING_COUNT warnings."

print_log info "End program."

exit 0
# }
