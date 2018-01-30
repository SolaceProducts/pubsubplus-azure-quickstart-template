#!/bin/bash

OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our own variables:
current_index=""
ip_prefix=""
number_of_instances=""
password_file="solOSpasswd"
DEBUG="-vvvv"
is_primary="false"

verbose=0

while getopts "c:i:n:p:" opt; do
    case "$opt" in
    c)  current_index=$OPTARG
        ;;
    i)  ip_prefix=$OPTARG
        ;;
    n)  number_of_instances=$OPTARG
        ;;
    p)  password_file=$OPTARG
        ;;
    esac
done

shift $((OPTIND-1))
[ "$1" = "--" ] && shift

verbose=1
echo "`date` current_index=$current_index , ip_prefix=$ip_prefix , number_of_instances=$number_of_instances , \
      password_file=$password_file , Leftovers: $@"
export password=`cat ${password_file}`

#Install the logical volume manager and jq for json parsing
yum -y install lvm2
yum -y install epel-release
yum -y install jq
#Load the VMR
REAL_LINK=
for filename in ./*; do
    echo "File = ${filename}"
    count=`grep -c "https://products.solace.com" ${filename}`
    if [ "1" = ${count} ]; then
      REAL_LINK=`egrep -o "https://[a-zA-Z0-9\.\/\_\?\=]*" ${filename}`
    fi    
done

echo "`date` INFO: check to make sure we have a complete load"
wget -O /tmp/solosEval.info -nv  https://products.solace.com/download/VMR_DOCKER_EVAL_MD5
IFS=' ' read -ra SOLOSEVAL_INFO <<< `cat /tmp/solosEval.info`
MD5_SUM_EVAL=${SOLOSEVAL_INFO[0]}
SolOS_EVAL_LOAD=${SOLOSEVAL_INFO[1]}
echo "`date` INFO: Reference eval md5sum is: ${MD5_SUM_EVAL}"

wget -O /tmp/solosComm.info -nv  https://products.solace.com/download/VMR_DOCKER_COMM_MD5
IFS=' ' read -ra SOLOSCOMM_INFO <<< `cat /tmp/solosComm.info`
MD5_SUM_COMM=${SOLOSCOMM_INFO[0]}
SolOS_COMM_LOAD=${SOLOSCOMM_INFO[1]}
echo "`date` INFO: Reference comm md5sum is: ${MD5_SUM_COMM}"

echo "`date` INFO: try 3 times to download from URL provided and validate it is Evaluation and Community edition VRM"
LOOP_COUNT=0
SolOS_LOAD=solos.tar.gz
isEval=0

while [ $LOOP_COUNT -lt 3 ]; do
  wget -q -O /tmp/${SolOS_LOAD} -nv ${REAL_LINK}

  LOCAL_OS_INFO=`md5sum /tmp/${SolOS_LOAD}`
  IFS=' ' read -ra SOLOS_INFO <<< ${LOCAL_OS_INFO}
  LOCAL_MD5_SUM=${SOLOS_INFO[0]}
  if [ ${LOCAL_MD5_SUM} == ${MD5_SUM_COMM} ]; then
    echo "`date` INFO: Successfully downloaded ${SolOS_COMM_LOAD}"
    break
  fi
  if [ ${LOCAL_MD5_SUM} == ${MD5_SUM_EVAL} ]; then
    echo "`date` INFO: Successfully downloaded ${SolOS_EVAL_LOAD}"
    isEval=1
    break
  fi
  echo "`date` WARNING: CORRUPT SolOS load re-try ${LOOP_COUNT}"
  ((LOOP_COUNT++))
done

if [ ${LOOP_COUNT} == 3 ]; then
  echo "`date` ERROR: Failed to download SolOS exiting" | tee /dev/stderr
  exit 1
fi

echo "`date` INFO: Check if there is a requirement for 3 node cluster and not Evalution edition exit"
if [ ${isEval} == 0 ] && [ ${number_of_instances} == 3 ]; then
  echo "`date` ERROR: Trying to build HA cluster with community edition SolOS, this is not supported" | tee /dev/stderr
  exit 1
fi

echo "`date` INFO: Setting up SolOS Docker image"
#Create new volumes that the VMR container can use to consume and store data.
docker volume create --name=jail
docker volume create --name=var
docker volume create --name=internalSpool
docker volume create --name=adbBackup
docker volume create --name=softAdb

docker load -i /tmp/${SolOS_LOAD} 

export VMR_VERSION=`docker images | grep solace | awk '{print $2}'`
echo "`date` INFO: VMR version: ${VMR_VERSION}"

MEM_SIZE=`cat /proc/meminfo | grep MemTotal | tr -dc '0-9'`

if [ ${MEM_SIZE} -lt 6087960 ]; then
  echo "`date` WARN: Not enough memory: ${MEM_SIZE} Creating 2GB Swap space"
  mkdir /var/lib/solace
  dd if=/dev/zero of=/var/lib/solace/swap count=2048 bs=1MiB
  mkswap -f /var/lib/solace/swap
  chmod 0600 /var/lib/solace/swap
  swapon -f /var/lib/solace/swap
  grep -q 'solace\/swap' /etc/fstab || sudo sh -c 'echo "/var/lib/solace/swap none swap sw 0 0" >> /etc/fstab'
else
   echo "`date` INFO: Memory size is ${MEM_SIZE}"
fi

if [ ${number_of_instances} -gt 1 ]; then
  echo "`date` INFO: Configuring HA tuple"
  case ${current_index} in  
    0 )
      redundancy_config="\
      --env nodetype=message_routing \
      --env routername=primary \
      --env redundancy_matelink_connectvia=${ip_prefix}1 \
      --env redundancy_activestandbyrole=primary \
      --env redundancy_group_passwordfilepath=$(basename ${password_file}) \
      --env redundancy_enable=yes \
      --env redundancy_group_node_primary_nodetype=message_routing \
      --env redundancy_group_node_primary_connectvia=${ip_prefix}0 \
      --env redundancy_group_node_backup_nodetype=message_routing \
      --env redundancy_group_node_backup_connectvia=${ip_prefix}1 \
      --env redundancy_group_node_monitor_nodetype=monitoring \
      --env redundancy_group_node_monitor_connectvia=${ip_prefix}2 \
      --env configsync_enable=yes"
      is_primary="true"
        ;; 
    1 ) 
      redundancy_config="\
      --env nodetype=message_routing \
      --env routername=backup \
      --env redundancy_matelink_connectvia=${ip_prefix}0 \
      --env redundancy_activestandbyrole=backup \
      --env redundancy_group_passwordfilepath=$(basename ${password_file}) \
      --env redundancy_enable=yes \
      --env redundancy_group_node_primary_nodetype=message_routing \
      --env redundancy_group_node_primary_connectvia=${ip_prefix}0 \
      --env redundancy_group_node_backup_nodetype=message_routing \
      --env redundancy_group_node_backup_connectvia=${ip_prefix}1 \
      --env redundancy_group_node_monitor_nodetype=monitoring \
      --env redundancy_group_node_monitor_connectvia=${ip_prefix}2 \
      --env configsync_enable=yes"
        ;; 
    2 ) 
      redundancy_config="\
      --env nodetype=monitoring \
      --env routername=monitor \
      --env redundancy_group_passwordfilepath=$(basename ${password_file}) \
      --env redundancy_enable=yes \
      --env redundancy_group_node_primary_nodetype=message_routing \
      --env redundancy_group_node_primary_connectvia=${ip_prefix}0 \
      --env redundancy_group_node_backup_nodetype=message_routing \
      --env redundancy_group_node_backup_connectvia=${ip_prefix}1 \
      --env redundancy_group_node_monitor_nodetype=monitoring \
      --env redundancy_group_node_monitor_connectvia=${ip_prefix}2"
        ;; 
  esac
else
  echo "`date` INFO: Configuring singleton"
  redundancy_config=""
fi

#Define a create script
tee /root/docker-create <<-EOF 
#!/bin/bash 
docker create \
 --privileged=true \
 --uts=host \
 --shm-size 2g \
 --ulimit memlock=-1 \
 --ulimit nofile=2448:38048 \
 --ulimit core=-1 \
 --net=host \
 --log-driver syslog \
 --log-opt syslog-format=rfc3164 \
 --log-opt syslog-address=udp://127.0.0.1:25224 \
 -v jail:/usr/sw/jail \
 -v var:/usr/sw/var \
 -v $(dirname ${password_file}):/run/secrets \
 -v internalSpool:/usr/sw/internalSpool \
 -v adbBackup:/usr/sw/adb \
 -v softAdb:/usr/sw/internalSpool/softAdb \
 --env username_admin_globalaccesslevel=admin \
 --env username_admin_passwordfilepath=$(basename ${password_file}) \
 --env logging_debug_output=all \
 --env logging_command_output=all \
 --env logging_system_output=all \
 --env logging_event_output=all \
 --env logging_kernel_output=all \
 --env logging_debug_format=graylog \
 --env logging_command_format=graylog \
 --env logging_system_format=graylog \
 --env logging_event_format=graylog \
 --env logging_kernel_format=graylog \
 ${redundancy_config} \
 --name=solace solace-app:${VMR_VERSION} 
EOF

#Make the file executable
chmod +x /root/docker-create

echo "`date` INFO: Creating the Solace VMR container"
/root/docker-create

#Construct systemd for VMR
tee /etc/systemd/system/solace-docker-vmr.service <<-EOF
[Unit] 
  Description=solace-docker-vmr 
  Requires=docker.service 
  After=docker.service 
[Service] 
  Restart=always 
  ExecStart=/usr/bin/docker start -a solace 
  ExecStop=/usr/bin/docker stop solace 
[Install] 
  WantedBy=default.target 
EOF

echo "`date` INFO: Start the Solace VMR container"
systemctl daemon-reload 
systemctl enable solace-docker-vmr 
systemctl start solace-docker-vmr

# Poll the VMR SEMP port until it is Up
loop_guard=30
pause=10
count=0
echo "`date` INFO: Wait for the VMR SEMP service to be enabled"
while [ ${count} -lt ${loop_guard} ]; do
  online_results=`./semp_query.sh -n admin -p ${password} -u http://localhost:8080/SEMP \
    -q "<rpc semp-version='soltr/8_7VMR'><show><service/></show></rpc>" \
    -v "/rpc-reply/rpc/show/service/services/service[name='SEMP']/enabled[text()]"`

  is_vmr_up=`echo ${online_results} | jq '.valueSearchResult' -`
  echo "`date` INFO: SEMP service 'enabled' status is: ${is_vmr_up}"

  run_time=$((${count} * ${pause}))
  if [ "${is_vmr_up}" = "\"true\"" ]; then
      echo "`date` INFO: VMR SEMP service is up, after ${run_time} seconds"
      break
  fi
  ((count++))
  echo "`date` INFO: Waited ${run_time} seconds, VMR SEMP service not yet up"
  sleep ${pause}
done

# Remove all VMR Secrets from the host; at this point, the VMR should have come up
# and it won't be needing those files anymore
rm ${password_file}

# Poll the redundancy status on the Primary VMR
loop_guard=30
pause=10
count=0
mate_active_check=""
if [ "${is_primary}" = "true" ]; then
  echo "`date` INFO: Wait for Primary to be 'Local Active' or 'Mate Active'"
  while [ ${count} -lt ${loop_guard} ]; do 
    online_results=`./semp_query.sh -n admin -p ${password} -u http://localhost:8080/SEMP \
         -q "<rpc semp-version='soltr/8_7VMR'><show><redundancy><detail/></redundancy></show></rpc>" \
         -v "/rpc-reply/rpc/show/redundancy/virtual-routers/primary/status/activity[text()]"`

    local_activity=`echo ${online_results} | jq '.valueSearchResult' -`
    echo "`date` INFO: Local activity state is: ${local_activity}"

    run_time=$((${count} * ${pause}))
    case "${local_activity}" in
      "\"Local Active\"")
        echo "`date` INFO: Redundancy is up locally, Primary Active, after ${run_time} seconds"
        mate_active_check="Standby"
        break
        ;;
      "\"Mate Active\"")
        echo "`date` INFO: Redundancy is up locally, Backup Active, after ${run_time} seconds"
        mate_active_check="Active"
        break
        ;;
    esac
    ((count++))
    echo "`date` INFO: Waited ${run_time} seconds, Redundancy not yet up"
    sleep ${pause}
  done

  if [ ${count} -eq ${loop_guard} ]; then
    echo "`date` ERROR: Solace redundancy group never came up" | tee /dev/stderr
    exit 1 
  fi

  loop_guard=30
  pause=10
  count=0
  echo "`date` INFO: Wait for Backup to be 'Active' or 'Standby'"
  while [ ${count} -lt ${loop_guard} ]; do 
    online_results=`./semp_query.sh -n admin -p ${password} -u http://localhost:8080/SEMP \
         -q "<rpc semp-version='soltr/8_7VMR'><show><redundancy><detail/></redundancy></show></rpc>" \
         -v "/rpc-reply/rpc/show/redundancy/virtual-routers/primary/status/detail/priority-reported-by-mate/summary[text()]"`

    mate_activity=`echo ${online_results} | jq '.valueSearchResult' -`
    echo "`date` INFO: Mate activity state is: ${mate_activity}"

    run_time=$((${count} * ${pause}))
    case "${mate_activity}" in
      "\"Active\"")
        echo "`date` INFO: Redundancy is up end-to-end, Backup Active, after ${run_time} seconds"
        mate_active_check="Standby"
        break
        ;;
      "\"Standby\"")
        echo "`date` INFO: Redundancy is up end-to-end, Primary Active, after ${run_time} seconds"
        mate_active_check="Active"
        break
        ;;
    esac
    ((count++))
    echo "`date` INFO: Waited ${run_time} seconds, Redundancy not yet up"
    sleep ${pause}
  done

  if [ ${count} -eq ${loop_guard} ]; then
    echo "`date` ERROR: Solace redundancy group never came up" | tee /dev/stderr
    exit 1 
  fi

 ./semp_query.sh -n admin -p ${password} -u http://localhost:8080/SEMP \
         -q "<rpc semp-version='soltr/8_7VMR'><admin><config-sync><assert-master><router/></assert-master></config-sync></admin></rpc>"
 ./semp_query.sh -n admin -p ${password} -u http://localhost:8080/SEMP \
         -q "<rpc semp-version='soltr/8_7VMR'><admin><config-sync><assert-master><vpn-name>default</vpn-name></assert-master></config-sync></admin></rpc>"
fi
echo "`date` INFO: Solace VMR bringup complete"