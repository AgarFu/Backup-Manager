#!/bin/sh
# $Revision: $
# $Date: $

set -e

# Each test script should include testlib.sh
source testlib.sh
# When the test is ready, set this to false for nice outputs.
# if you want to see what happens, use those flags
#verbose="true"
#warnings="true"

# The conffile part of the test, see confs/* for details.
source confs/base.conf
source confs/tarball.conf

export BM_ARCHIVE_ROOT="repository"
export BM_ARCHIVE_METHOD="tarball-incremental"
export BM_TARBALL_DIRECTORIES="$PWD/test"
export BM_TARBALLINC_MASTERDATETYPE="weekly"
export BM_TARBALL_FILETYPE="dar"

# The test actions

rm -rf test
mkdir -p test
mkdir test/dir1
touch test/file1

if [ -e $BM_ARCHIVE_ROOT ]; then
    rm -f $BM_ARCHIVE_ROOT/*
fi    

bm_init_env
bm_init_today
create_archive_root_if_not_exists
make_archives

YESTERDAY=$(date +%Y%m%d --date '1 days ago')

name=$(get_dir_name "$PWD/test" long)
if [ -e "$BM_ARCHIVE_ROOT/$BM_ARCHIVE_PREFIX$name.$TODAY.1.dar" ]; then
    mv "$BM_ARCHIVE_ROOT/$BM_ARCHIVE_PREFIX$name.$TODAY.1.dar" "$BM_ARCHIVE_ROOT/$BM_ARCHIVE_PREFIX$name.$YESTERDAY.1.dar"
    mkdir test/dir2
    touch test/file2
    make_archives

    # Now make sure file2 and dir2 are not saved in last darball
    for file in file1 dir1 
    do
        saved=$(dar -l $BM_ARCHIVE_ROOT/$BM_ARCHIVE_PREFIX$name.$TODAY | grep $file | awk '{print $1}')
        if [ "$saved" == "[saved]" ]; then
            warning "$file is saved in last archive, shouldn't."
            exit 1
        fi
    done
    exit 0
else
    exit 1
fi        
