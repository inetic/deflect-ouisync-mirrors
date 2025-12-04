#!/bin/bash

set -e

primary_container_name=test.ouisync_mirror.primary
mirror_container_name=test.ouisync_mirror.mirror

function remove_containers (
    docker container rm -f $primary_container_name $mirror_container_name 2>/dev/null 1>&2 || true
)

# --- set up ---

# Ensure there are no containers left from previous runs
remove_containers

test_dir=$(mktemp -d /tmp/ouisync-mirror-tests/$(date '+%Y-%m-%d_%Hh%Mm%Ss').XXXX)

store_dir=$test_dir/store
primary_dir=$test_dir/primary
mirror_dir=$test_dir/mirror

mkdir -p $store_dir $primary_dir $mirror_dir

./ouisync-mirror.sh -c $primary_container_name -p $store_dir $primary_dir

./ouisync-mirror.sh -c $mirror_container_name -m \
    $(./ouisync-mirror.sh -c $primary_container_name --get-token read) \
    $mirror_dir

# --- tests ---

function check_same (
    local dir1=$primary_dir
    local dir2=$mirror_dir
    local same
    for i in $(seq 1 50); do
        difference=$(diff -r $dir1 $dir2 || true)
        if [ -z "$difference" ]; then
            same=y
            break
        fi
        sleep 0.2
    done
    if [ $same != y ]; then
        echo "ERROR: Dirs not in sync"
        echo "$difference"
        return 1
    fi
)

echo "######## Running tests ##########"

control_text="Hello from Ouisync Mirrors"
echo $control_text > $primary_dir/file1
check_same

control_text="foo bar"
echo $control_text > $primary_dir/file2
check_same

rm $primary_dir/file1
check_same

rm $primary_dir/file2
check_same

control_text="inside dir"
mkdir -p $primary_dir/dir
echo $control_text > $primary_dir/dir/file3
check_same

rm $primary_dir/dir/file3
check_same

rm -r $primary_dir/dir
check_same

echo "ALL GOOD"

# --- clean up ---

remove_containers
rm -rf $test_dir
