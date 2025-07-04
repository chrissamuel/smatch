#!/bin/bash

set -e

if echo $1 | grep -q '^-p' ; then
    PROJ=$(echo $1 | cut -d = -f 2)
    shift
fi

info_file=$1

if [[ "$info_file" = "" ]] ; then
    echo "Usage:  $0 -p=<project> <file with smatch messages>"
    exit 1
fi

if [ ! -e "$info_file" ] ; then
    echo "no such file: $info_file"
    exit 1
fi

bin_dir=$(dirname $0)
db_file=smatch_db.sqlite.new

rm -f $db_file

for i in ${bin_dir}/*.schema ; do
    cat $i | sqlite3 $db_file
done

${bin_dir}/init_constraints.pl "$PROJ" $info_file $db_file
${bin_dir}/init_constraints_required.pl "$PROJ" $info_file $db_file
${bin_dir}/fill_db_sql.pl "$PROJ" $info_file $db_file
if [ -e ${info_file}.sql ] ; then
    ${bin_dir}/fill_db_sql.pl "$PROJ" ${info_file}.sql $db_file
fi
${bin_dir}/fill_db_caller_info.pl "$PROJ" $info_file $db_file
if [ -e ${info_file}.caller_info ] ; then
    ${bin_dir}/fill_db_caller_info.pl "$PROJ" ${info_file}.caller_info $db_file
fi
${bin_dir}/build_early_index.sh $db_file

${bin_dir}/fill_db_type_value.pl "$PROJ" $info_file $db_file
${bin_dir}/fill_db_type_size.pl "$PROJ" $info_file $db_file
${bin_dir}/copy_required_constraints.pl "$PROJ" $info_file $db_file
${bin_dir}/build_late_index.sh $db_file

${bin_dir}/fixup_all.sh $db_file
if [ "$PROJ" != "" ] ; then
    # Run the fixup script only if it exists and is executable
    test -x ${bin_dir}/fixup_${PROJ}.sh && ${bin_dir}/fixup_${PROJ}.sh $db_file
fi

${bin_dir}/copy_function_pointers.pl $db_file
${bin_dir}/remove_mixed_up_pointer_params.pl $db_file
${bin_dir}/delete_too_common_fn_ptr.sh $db_file
${bin_dir}/mark_function_ptrs_searchable.pl $db_file

# delete duplicate entrees and speed things up
echo "delete from function_ptr where rowid not in (select min(rowid) from function_ptr group by file, function, ptr, searchable);" | sqlite3 $db_file

${bin_dir}/apply_return_fixes.sh -p=${PROJ} $db_file
if [ "$PROJ" != "" ] ; then
    ${bin_dir}/insert_manual_states.pl ${PROJ} $db_file
fi

# test the new DB
if ! echo "select * from return_states where type = 0 limit 1;" | \
    sqlite3 $db_file > /dev/null ; then
    echo "$0 failed."
    exit 1
fi

mv $db_file smatch_db.sqlite
