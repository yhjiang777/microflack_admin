#!/bin/bash -e

# This script performs a complete install on a single host. Intended for
# development, staging and testing.

GITROOT=https://github.com/yhjiang777
pushd ~/

# environment variables
export HOST_IP_ADDRESS=$(ip route get 1 | awk '{for(i=1; i<NF; i++) if($i == "src") { print $((i+1)); break }}')
export SECRET_KEY=$(pwgen -1 -c -n -s 32)
export JWT_SECRET_KEY=$(pwgen -1 -c -n -s 32)
export PATH=$PATH:$PWD/microflack_admin/bin
echo export HOST_IP_ADDRESS=$HOST_IP_ADDRESS >> ~/.profile
echo export SECRET_KEY=$SECRET_KEY >> ~/.profile
echo export JWT_SECRET_KEY=$JWT_SECRET_KEY >> ~/.profile
echo export PATH=\$PATH:$PWD/microflack_admin/bin >> ~/.profile

# logging
docker run --name logspout -d --restart always -p 1095:80 -v /var/run/docker.sock:/var/run/docker.sock gliderlabs/logspout:latest

# deploy etcd
docker run --name etcd -d --restart always -p 2379:2379 -p 2380:2380 miguelgrinberg/easy-etcd:latest
export ETCD=http://$HOST_IP_ADDRESS:2379
echo export ETCD=$ETCD >> ~/.profile

# install etcdtool
docker pull mkoppanen/etcdtool

# deploy mysql
mkdir -p ~/mysql-data-dir
MYSQL_ROOT_PASSWORD=$(pwgen -1 -c -n -s 16)
docker run --name mysql -d --restart always -p 3306:3306 -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD -v ~/mysql-data-dir:/var/lib/mysql mysql:5.7
export DATABASE_SERVER=$HOST_IP_ADDRESS:3306
echo export DATABASE_SERVER=$DATABASE_SERVER >> ~/.profile
echo MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD >> ~/.mysql_root_password

# deploy redis
docker run --name redis -d --restart always -p 6379:6379 redis:3.2-alpine
export REDIS=$HOST_IP_ADDRESS:6379
echo export REDIS=$REDIS >> ~/.profile

# deploy load balancer
if [[ "$LOAD_BALANCER" == "traefik" ]]; then
    # use the traefik load balancer
    echo export LOAD_BALANCER=traefik >> ~/.profile
    docker run --name lb -d --restart always -p 80:80 -p 8080:8080 traefik:1.3 --etcd --etcd.endpoint="$HOST_IP_ADDRESS:2379" --web --web.address=":8080"
else
    # use the haproxy load balancer (recommended)
    echo export LOAD_BALANCER=haproxy >> ~/.profile
    docker run --name lb -d --restart always -p 80:80 -e ETCD_PEERS=$ETCD -e HAPROXY_STATS=1 miguelgrinberg/easy-lb-haproxy:latest
fi

# download the code and build containers
git clone $GITROOT/microflack_admin
cd microflack_admin
source mfvars
install/make-db-passwords.sh
echo "source $PWD/mfvars" >> ~/.profile
mfclone ..
mfbuild all

# run services
for SERVICE in $SERVICES; do
    mfrun $SERVICE
done

popd
echo MicroFlack is now deployed!
echo - Run "source ~/.profile" or log back in to update your environment.
echo - You may need some variables from ~/.profile if you intend to run services in another host.
