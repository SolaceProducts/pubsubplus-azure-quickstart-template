#!/bin/bash

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

  #check to make sure we have a complete load
  wget -O /tmp/solos.info -nv  https://products.solace.com/download/VMR_DOCKER_COMM_MD5
  IFS=' ' read -ra SOLOS_INFO <<< `cat /tmp/solos.info`
  MD5_SUM=${SOLOS_INFO[0]}
  SolOS_LOAD=${SOLOS_INFO[1]}

  wget -O /tmp/${SolOS_LOAD} -nv ${REAL_LINK}

  LOCAL_MD5_SUM=`md5sum /tmp/${SolOS_LOAD}`

  if [ ${LOCAL_MD5_SUM} -ne `cat wget -O /tmp/solos.info` ]; then
    ((LOOP_COUNT++))
    echo "`date` WARNING: CORRUPT SolOS load re-try ${LOOP_COUNT}"
  else
    echo "Successfully downloaded ${SolOS_LOAD}"
    break
  fi
done

if [ ${LOOP_COUNT} -eq 3 ]; then
  echo "`date` ERROR: Failed to download ${SolOS_LOAD} exiting"
  exit 1
fi

docker load -i /tmp/${SolOS_LOAD} 

#Need to de
export VMR_VERSION=`docker images | grep solace | awk '{print $2}'`

MEM_SIZE=`cat /proc/meminfo | grep MemTotal | tr -dc '0-9'`

if [ ${MEM_SIZE} -lt 6087960 ]; then
  mkdir /var/lib/solace
  dd if=/dev/zero of=/var/lib/solace/swap count=2048 bs=1MiB
  mkswap -f /var/lib/solace/swap
  chmod 0600 /var/lib/solace/swap
  swapon -f /var/lib/solace/swap
  grep -q 'solace\/swap' /etc/fstab || sudo sh -c 'echo "/var/lib/solace/swap none swap sw 0 0" >> /etc/fstab'
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
 --env 'username_admin_password=admin' \
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