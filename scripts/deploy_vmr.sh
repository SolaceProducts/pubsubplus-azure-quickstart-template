#!/bin/bash

OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our own variables:
current_index=""
ip_prefix=""
number_of_instances=""
password="admin"
DEBUG="-vvvv"

verbose=0

while getopts "c:i:vn:" opt; do
    case "$opt" in
    c)  current_index=$OPTARG
        ;;
    i)  ip_prefix=$OPTARG
        ;;
    n)  number_of_instances=$OPTARG
        ;;
    n)  password=$OPTARG
        ;;        
    esac
done

shift $((OPTIND-1))
[ "$1" = "--" ] && shift

verbose=1
echo "`date` current_index=$current_index ,ip_prefix=$ip_prefix ,number_of_instances=$number_of_instances, \
       ,Leftovers: $@"


#Install the logical volume manager
yum -y install lvm2


#Create new volumes that the VMR container can use to consume and store data.
docker volume create --name=jail
docker volume create --name=var
docker volume create --name=internalSpool
docker volume create --name=adbBackup
docker volume create --name=softAdb

LOOP_COUNT=0

while [ $LOOP_COUNT -lt 3 ]; do
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
  wget -O /tmp/solos.info -nv  https://products.solace.com/download/VMR_DOCKER_COMM_MD5
  IFS=' ' read -ra SOLOS_INFO <<< `cat /tmp/solos.info`
  MD5_SUM=${SOLOS_INFO[0]}
  SolOS_LOAD=${SOLOS_INFO[1]}
  echo "`date` INFO: Reference md5sum is: ${MD5_SUM}"

  wget -q -O /tmp/${SolOS_LOAD} -nv ${REAL_LINK}

  LOCAL_OS_INFO=`md5sum /tmp/${SolOS_LOAD}`
  IFS=' ' read -ra SOLOS_INFO <<< ${LOCAL_OS_INFO}
  LOCAL_MD5_SUM=${SOLOS_INFO[0]}
  if [ ${LOCAL_MD5_SUM} != ${MD5_SUM} ]; then
    ((LOOP_COUNT++))
    echo "`date` WARNING: CORRUPT SolOS load re-try ${LOOP_COUNT}"
  else
    echo "Successfully downloaded ${SolOS_LOAD}"
    break
  fi
done

if [ ${LOOP_COUNT} == 3 ]; then
  echo "`date` ERROR: Failed to download ${SolOS_LOAD} exiting"
  exit 1
fi

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

if [ ${number_of_instances} > 1 ]; then
  echo "`date` INFO: Configuring HA tuple"
  case ${$current_index} in  
    0 )
      redundancy_config="\
      --env nodetype=message_routing \
      --env routername=primary \
      --env redundancy_matelink_connectvia=${ip_prefix}1 \
      --env redundancy_activestandbyrole=primary \
      --env redundancy_group_password=${admin_password} \
      --env redundancy_enable=yes \
      --env redundancy_group_node_primary_nodetype=message_routing \
      --env redundancy_group_node_primary_connectvia=${ip_prefix}0 \
      --env redundancy_group_node_backup_nodetype=message_routing \
      --env redundancy_group_node_backup_connectvia=${ip_prefix}1 \
      --env redundancy_group_node_monitor_nodetype=monitoring \
      --env redundancy_group_node_monitor_connectvia=${ip_prefix}2 \
      --env configsync_enable=yes"
        ;; 
    1 ) 
      redundancy_config="\
      --env nodetype=message_routing \
      --env routername=backup \
      --env redundancy_matelink_connectvia=${ip_prefix}0 \
      --env redundancy_activestandbyrole=backup \
      --env redundancy_group_password=${admin_password} \
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
      --env nodetype=monitor \
      --env routername=monitor \
      --env redundancy_group_password=${admin_password} \
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
 --shm-size 2g \
 --net=host \
 -v jail:/usr/sw/jail \
 -v var:/usr/sw/var \
 -v internalSpool:/usr/sw/internalSpool \
 -v adbBackup:/usr/sw/adb \
 -v softAdb:/usr/sw/internalSpool/softAdb \
 --env 'username_admin_globalaccesslevel=admin' \
 --env 'username_admin_password=${password}' \
 ${redundancy_config} \
 --name=solace solace-app:${VMR_VERSION} 
EOF

#Make the file executable
chmod +x /root/docker-create

#Launch the VMR
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

#Start the solace service and enable it at system start up.
systemctl daemon-reload 
systemctl enable solace-docker-vmr 
systemctl start solace-docker-vmr