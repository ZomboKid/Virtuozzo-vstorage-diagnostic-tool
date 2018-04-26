#!/bin/bash

FILE="./error.log"

#----------------------------------------------------------------------------------------
get_mds_service_status () {
IFS=$'\n'
local rr=0
local warn_str=("WARNING! Script may be incorrect result. Check local mds-service status:")
local srvc_status=($(systemctl | grep vstorage-mds | awk '{print $1,$3}'))
for i in "${!srvc_status[@]}"; do
 local status=($(echo ${srvc_status[i]} | awk '{print $2}'))
 if [[ $status == "active" || $status == "running" ]]; then rr=$rr
   else
       #fill warn array by warn status from systemctl
       warn_str[i+1]=${srvc_status[i]}
       rr=$rr+1
 fi
done
if [[ $rr > 0 ]]; then
  #print warnings in separate string in red color
  echo -e "\033[0;31m${warn_str[*]}\033[0m"
fi
unset IFS
}
#----------------------------------------------------------------------------------------
get_cluster_name() {
   IFS=$'\n'
   local name
   local raw_arr
   raw_arr=($(eval "ls -al /etc/vstorage/clusters/"))
   name=($(echo ${raw_arr[3]} | awk -F " " '{print $9}'))
   #return cluster name with 1st arg of this function
   eval "$1=$name"
   IFS=$' '
}
#----------------------------------------------------------------------------------------
write_to_log() {
   IFS=$'\n'
   local curr_date

   declare -a stat_arr=("${!1}")
   declare -a event_arr=("${!2}")
   local cluster=$3

   #date and time with milliseconds - %3N
   curr_date=$(eval "date +\"%Y-%m-%d %H:%M:%S:%3N\"")
   echo "---------------------------------------------------------------------------------------------------------" >> $FILE
   echo $curr_date >> $FILE
   #grep between "of " and " (" from string with 'CS nodes: '
   chunks_count=($(vstorage -q -c $cl_name stat | grep 'CS nodes: ' | grep -o -P '(?<=of ).*?(?= \()'))
   #grep between "of " and ", " from string with 'MDS nodes: '
   meta_count=($(vstorage -q -c $cl_name stat | grep 'MDS nodes: ' | grep -o -P '(?<=of ).*?(?=, )'))
   #grep strictly NOT "avail" status (unavail, error etc.)
   echo "${stat_arr[*]}" | grep "MDSID" -A$meta_count | grep -wv "avail" >> $FILE
   #grep strictly NOT "avctive" status (unavail, error etc.)
   echo "${stat_arr[*]}" | grep "CSID" -A$chunks_count | grep -wv "active" >> $FILE  
   #get id of problem meta and chunk servers   
   mds_id=($(echo "${stat_arr[*]}" | grep "MDSID" -A$meta_count | grep -wv "avail" | awk '{print $1}')) 
   chunk_id=($(echo "${stat_arr[*]}" | grep "CSID" -A$chunks_count | grep -wv "active" | awk '{print $1}'))
   #delete "MDSID" and "CSID" elements from its arrays
   unset 'mds_id[0]' 
   unset 'chunk_id[0]'
   #get MDS events from log  
   for i in "${!mds_id[@]}"; do
   echo ">>>LOG EVENTS ABOUT MDS: ${mds_id[i]} ..............................................................................." >> $FILE
     echo "${event_arr[*]}" | grep -i mds\#${mds_id[i]} | tail -10 >> $FILE
   done
   #get CS events from log
   for i in "${!chunk_id[@]}"; do
   echo ">>>LOG EVENTS ABOUT CS: ${chunk_id[i]} ..............................................................................." >> $FILE
      echo "${event_arr[*]}" | grep -i cs\#${chunk_id[i]} | tail -10 >> $FILE
   done
   IFS=$' '
}
#----------------------------------------------------------------------------------------

get_mds_service_status

get_cluster_name cl_name

IFS=$'\n'

event_array=($(eval "vstorage -q -c $cl_name get-event"))
stat_array=($(eval "vstorage -q -c $cl_name stat"))

cl_status=($(echo ${stat_array[0]} | awk -F ": " '{print $2}'))

if [[ $cl_status == "healthy" ]]; then 
   printf "cluster $cl_name is OK\n"
elif [[ $cl_status == "degraded" ]]; then
     printf "cluster $cl_name is WARN\n"
     write_to_log stat_array[@] event_array[@] $cl_name
elif [[ $cl_status == "unknown" || $cl_status == "failure" ]]; then
     printf "cluster $cl_name is ERROR\n"
     write_to_log stat_array[@] event_array[@] $cl_name
fi

IFS=$' '
