#!/bin/bash

#Install the logical volume manager
yum -y install lvm2

#Install the Docker yum repository. 
tee /etc/yum.repos.d/docker.repo <<-EOF 
[dockerrepo]
 name=Docker Repository 
 baseurl=https://yum.dockerproject.org/repo/main/centos/7/
 enabled=1 
 gpgcheck=1 
 gpgkey=https://yum.dockerproject.org/gpg 
EOF

#Create new volumes that the VMR container can use to consume and store data.
docker volume create --name=jail
docker volume create --name=var
docker volume create --name=internalSpool
docker volume create --name=adbBackup
docker volume create --name=softAdb

#Load the VMR
docker load -i ./soltr*.tar.gz

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
 --name=solace solace-app:100.0vmr_docker.0.60-enterprise 
EOF

#Make the file executable
chmod +x docker-create

#Launch the VMR
./docker-create

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