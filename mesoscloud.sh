#!/bin/sh

# mesoscloud
#
# https://github.com/mesoscloud/mesoscloud-do

config() {
    # from environment
    eval v=\$$1
    if [ -n "$v" ]; then
	echo "$v"
	return
    fi
    a=`echo $1 | cut -d_ -f1 | tr '[:upper:]' '[:lower:]'`
    b=`echo $1 | cut -d_ -f2- | tr '[:upper:]' '[:lower:]'`
    # from mesoscloud.cfg, or default
    python -c "import ConfigParser; config = ConfigParser.SafeConfigParser(); config.read('mesoscloud.cfg'); print config.get('$a', '$b')" 2> /dev/null || echo "$2"
}

# generate a random password
password() {
    python -c "import os, re; print(re.sub(r'[^a-zA-Z0-9]', '', os.urandom($1 * 1024))[:$1])"
}

# cluster
MESOSCLOUD_NAME=`config MESOSCLOUD_NAME dev`
MESOSCLOUD_NODES=`config MESOSCLOUD_NODES "${MESOSCLOUD_NAME}-1 ${MESOSCLOUD_NAME}-2 ${MESOSCLOUD_NAME}-3"`
MESOSCLOUD_MASTERS=`config MESOSCLOUD_MASTERS "${MESOSCLOUD_NAME}-1 ${MESOSCLOUD_NAME}-2 ${MESOSCLOUD_NAME}-3"`
MESOSCLOUD_SLAVES=`config MESOSCLOUD_SLAVES "${MESOSCLOUD_NAME}-1 ${MESOSCLOUD_NAME}-2 ${MESOSCLOUD_NAME}-3"`

# do
DIGITALOCEAN_ACCESS_TOKEN=`config DIGITALOCEAN_ACCESS_TOKEN ""`
DIGITALOCEAN_REGION=`config DIGITALOCEAN_REGION nyc3`
DIGITALOCEAN_SIZE=`config DIGITALOCEAN_SIZE 4gb`

# images
IMAGE_EVENTS=`config IMAGE_EVENTS mesoscloud/events:0.2.2`
IMAGE_ZOOKEEPER=`config IMAGE_ZOOKEEPER mesoscloud/zookeeper:3.4.6-ubuntu-14.04`
IMAGE_MESOS_MASTER=`config IMAGE_MESOS_MASTER mesoscloud/mesos-master:0.23.0-ubuntu-14.04`
IMAGE_MESOS_SLAVE=`config IMAGE_MESOS_SLAVE mesoscloud/mesos-slave:0.23.0-ubuntu-14.04`
IMAGE_MARATHON=`config IMAGE_MARATHON mesoscloud/marathon:0.10.1-ubuntu-14.04`
IMAGE_CHRONOS=`config IMAGE_CHRONOS mesoscloud/chronos:2.4.0-ubuntu-14.04`
IMAGE_HAPROXY_MARATHON=`config IMAGE_HAPROXY_MARATHON mesoscloud/haproxy-marathon:0.1.1`
IMAGE_HAPROXY=`config IMAGE_HAPROXY mesoscloud/haproxy:1.5.14-ubuntu-14.04`
IMAGE_ELASTICSEARCH=`config IMAGE_ELASTICSEARCH mesoscloud/elasticsearch:1.7.1-ubuntu-14.04`
IMAGE_LOGSTASH=`config IMAGE_LOGSTASH mesoscloud/logstash:1.5.4-ubuntu-14.04`

# cpu
CPU_EVENTS=`config CPU_EVENTS 1.0`
CPU_ZOOKEEPER=`config CPU_ZOOKEEPER 1.0`
CPU_MESOS_MASTER=`config CPU_MESOS_MASTER 1.0`
CPU_MESOS_SLAVE=`config CPU_MESOS_SLAVE 1.0`
CPU_MARATHON=`config CPU_MARATHON 1.0`
CPU_CHRONOS=`config CPU_CHRONOS 1.0`
CPU_HAPROXY_MARATHON=`config CPU_HAPROXY_MARATHON 1.0`
CPU_HAPROXY=`config CPU_HAPROXY 1.0`
CPU_ELASTICSEARCH=`config CPU_ELASTICSEARCH 1.0`
CPU_LOGSTASH=`config CPU_LOGSTASH 1.0`

# mesos
MESOS_SECRET=`config MESOS_SECRET "$(password 32)"`

# write mesoscloud.cfg.current
config_write() {
    touch mesoscloud.cfg.current
    chmod 600 mesoscloud.cfg.current
    cat > mesoscloud.cfg.current <<EOF
[mesoscloud]
name: $MESOSCLOUD_NAME
nodes: $MESOSCLOUD_NODES
masters: $MESOSCLOUD_MASTERS
slaves: $MESOSCLOUD_SLAVES

[digitalocean]
access_token: $DIGITALOCEAN_ACCESS_TOKEN
region: $DIGITALOCEAN_REGION
size: $DIGITALOCEAN_SIZE

[image]
events: $IMAGE_EVENTS
zookeeper: $IMAGE_ZOOKEEPER
mesos_master: $IMAGE_MESOS_MASTER
mesos_slave: $IMAGE_MESOS_SLAVE
marathon: $IMAGE_MARATHON
chronos: $IMAGE_CHRONOS
haproxy_marathon: $IMAGE_HAPROXY_MARATHON
haproxy: $IMAGE_HAPROXY
elasticsearch: $IMAGE_ELASTICSEARCH
logstash: $IMAGE_LOGSTASH

[cpu]
events: $CPU_EVENTS
zookeeper: $CPU_ZOOKEEPER
mesos_master: $CPU_MESOS_MASTER
mesos_slave: $CPU_MESOS_SLAVE
marathon: $CPU_MARATHON
chronos: $CPU_CHRONOS
haproxy_marathon: $CPU_HAPROXY_MARATHON
haproxy: $CPU_HAPROXY
elasticsearch: $CPU_ELASTICSEARCH
logstash: $CPU_LOGSTASH

[mesos]
secret: $MESOS_SECRET
EOF
}

#
# config (internal)
#

MESOSCLOUD_TMP=.mesoscloud

CYAN='\033[0;36m'
WHITE='\033[1;39m'
RESET='\033[0m'

LOCK=$MESOSCLOUD_TMP/.lock

#
# functions
#

info() {
    # best effort only
    while [ -e $LOCK ]; do
	sleep 0.05
    done
    touch $LOCK

    if [ -n "$2" ]; then
	echo "$WHITE$2 $1$RESET" >&2
    else
	echo "$WHITE$1$RESET" >&2
    fi

    if [ -n "$3" ]; then
	echo "$CYAN$3$RESET" >&2
    fi
    rm -f $LOCK
}

say() {
    echo " _`python -c "print '_' * len('''$@''')"`_"
    echo "< $@ >"
    echo " -`python -c "print '-' * len('''$@''')"`-"
    echo "	\\   $CYAN^${RESET}__$CYAN^$RESET"
    echo "	 \\  (oo)\\_______"
    echo "	    (__)\\       )\\/\\"
    echo "		||----w |"
    echo "		||     ||"
}

err() {
    echo " _`python -c "print '_' * len('''$@''')"`_"
    echo "< $@ >"
    echo " -`python -c "print '-' * len('''$@''')"`-"
    echo "	\\   $CYAN^${RESET}__$CYAN^$RESET"
    echo "	 \\  (xx)\\_______"
    echo "	    (__)\\       )\\/\\"
    echo "	      U ||----w |"
    echo "		||     ||"
    exit 1
}

#
# droplet functions
#

droplets() {
    if [ -e $MESOSCLOUD_TMP/droplets.json -a -e $MESOSCLOUD_TMP/droplets.json.cache ]; then
	return
    fi

    curl -fsS -H 'Content-Type: application/json' -H "Authorization: Bearer $DIGITALOCEAN_ACCESS_TOKEN" https://api.digitalocean.com/v2/droplets > $MESOSCLOUD_TMP/droplets.json

    if [ $? -ne 0 ]; then
	err "We couldn't fetch a list of droplets from api.digitalocean.com :("
    fi

    if ! python -m json.tool $MESOSCLOUD_TMP/droplets.json > /dev/null; then
	err "We couldn't parse output from api.digitalocean.com  :("
    fi
}

droplet_exists() {
    test -n "$1" || err "usage: droplet_exists <name>"

    info "droplet exists?" "$1"

    droplets

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1
}

droplet_summary() {
    test -n "$1" || err "usage: droplet_summary <name>"

    info "droplet summary" "$1"

    droplets

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1

    cat <<EOF
name            $1
id              `droplet_id $1`
status          `droplet_status $1`
size            `droplet_size $1`
region          `droplet_region $1`
image           `droplet_image $1`
kernel          `droplet_kernel $1`
address public  `droplet_address_public $1`
address private `droplet_address_private $1`
EOF
}

droplet_create() {
    test -n "$1" || err "usage: droplet_create <name>"

    info "droplet create" "$1"

    curl -fsS -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $DIGITALOCEAN_ACCESS_TOKEN" -d "{\"name\":\"$1\",\"region\":\"$DIGITALOCEAN_REGION\",\"size\":\"$DIGITALOCEAN_SIZE\",\"image\":\"ubuntu-14-04-x64\",\"ssh_keys\":[\"$SSH_KEY_FINGERPRINT\"],\"backups\":false,\"ipv6\":false,\"user_data\":null,\"private_networking\":true}" https://api.digitalocean.com/v2/droplets > $MESOSCLOUD_TMP/droplets.json

    if [ $? -ne 0 ]; then
	err "We couldn't fetch a list of droplets from api.digitalocean.com :("
    fi

    if ! python -m json.tool $MESOSCLOUD_TMP/droplets.json > /dev/null; then
	err "We couldn't parse output from api.digitalocean.com :("
    fi
}

droplet_locked() {
    test -n "$1" || exit 1

    info "droplet locked?" "$1"

    id=`droplet_id $1` || err "We can't find the droplet! :("

    curl -fsS -H 'Content-Type: application/json' -H "Authorization: Bearer $DIGITALOCEAN_ACCESS_TOKEN" https://api.digitalocean.com/v2/droplets/$id > $MESOSCLOUD_TMP/$1.json

    if [ $? -ne 0 ]; then
	err "We couldn't fetch a droplet from api.digitalocean.com :("
    fi

    if ! python -m json.tool $MESOSCLOUD_TMP/$1.json > /dev/null; then
	err "We couldn't parse output from api.digitalocean.com :("
    fi

    cat $MESOSCLOUD_TMP/$1.json | python -c "import json, sys; sys.exit(0 if json.load(sys.stdin)['droplet']['locked'] else 1)"
}

droplet_id() {
    test -n "$1" || err "usage: droplet_id <name>"

    droplets

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; print([d['id'] for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][-1])"
}

droplet_image() {
    test -n "$1" || err "usage: droplet_image <name>"

    droplets

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; print('%(distribution)s %(name)s' % [d['image'] for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][-1])"
}

droplet_kernel() {
    test -n "$1" || err "usage: droplet_kernel <name>"

    droplets

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; print('%(version)s' % [d['kernel'] for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][-1])"
}

droplet_size() {
    test -n "$1" || err "usage: droplet_size <name>"

    droplets

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; print(['%(memory)s MB, %(vcpus)s CPU, %(disk)s GB' % d['size'] for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][-1])"
}

droplet_region() {
    test -n "$1" || err "usage: droplet_region <name>"

    droplets

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; print([d['region']['name'] for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][-1])"
}

droplet_status() {
    test -n "$1" || err "usage: droplet_status <name>"

    droplets

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; print([d['status'] for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][-1])"
}

droplet_delete() {
    test -n "$1" || err "usage: droplet_delete <name>"

    info "droplet delete" "$1"

    id=`droplet_id $1`

    if [ -z "$id" ]; then
	return
    fi

    curl -fsS -X DELETE -H 'Content-Type: application/json' -H "Authorization: Bearer $DIGITALOCEAN_ACCESS_TOKEN" https://api.digitalocean.com/v2/droplets/$id
}

droplet_address_public() {
    test -n "$1" || exit 1

    droplets

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; print([n for n in [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][0]['networks']['v4'] if n['type'] == 'public'][0]['ip_address'])"
}

droplet_address_private() {
    test -n "$1" || exit 1

    droplets

    cat $MESOSCLOUD_TMP/droplets.json | python -c "import json, sys; print([n for n in [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][0]['networks']['v4'] if n['type'] == 'private'][0]['ip_address'])"
}

droplet_ssh() {
    test -n "$1" || err "usage: droplet_ssh <name> <command>"
    test -n "$2" || err "usage: droplet_ssh <name> <command>"

    pids=""
    for name in $1; do
	ssh_cmd="ssh -o BatchMode=yes root@`droplet_address_public $name` '$2'"
	info "droplet ssh" $name "$ssh_cmd"
	eval "$ssh_cmd" &
	pids="$pids $!"
    done

    for pid in $pids; do
	wait $pid || err "exit status: $?"
    done
}

#
# do functions
#

do_setup() {

    # depends
    if [ "$DIGITALOCEAN_ACCESS_TOKEN" = "" ]; then
	err "You need to set DIGITALOCEAN_ACCESS_TOKEN"
    fi

    if [ ! -f ~/.ssh/id_rsa ]; then
	err "You need an ssh key (missing ~/.ssh/id_rsa)"
    fi

    if [ ! -f ~/.ssh/id_rsa.pub ]; then
	err "You need an ssh key (missing ~/.ssh/id_rsa.pub)"
    fi

    SSH_KEY_FINGERPRINT=`ssh-keygen -f ~/.ssh/id_rsa.pub -l | awk '{print $2}'`

    #
    mkdir -p $MESOSCLOUD_TMP
}

do_setup_cache() {
    rm -rf $MESOSCLOUD_TMP
    mkdir -p $MESOSCLOUD_TMP
    droplets
    touch $MESOSCLOUD_TMP/droplets.json.cache
}

do_create() {
    say "We're going to create your droplets ($MESOSCLOUD_NODES)!"

    rm -rf $MESOSCLOUD_TMP
    mkdir -p $MESOSCLOUD_TMP

    for name in $MESOSCLOUD_NODES; do
	droplet_exists $name || droplet_create $name
    done

    for name in $MESOSCLOUD_NODES; do
	while droplet_locked $name; do
            sleep 1
	done
    done

    #
    touch $MESOSCLOUD_TMP/droplets.json.cache

    #
    say "Let's make sure we can connect."

    for name in $MESOSCLOUD_NODES; do
	info "ssh-keygen -R" $name
	ssh-keygen -R `droplet_address_public $name`
    done

    for name in $MESOSCLOUD_NODES; do
	info "droplet ssh" $name
	while true; do
	    ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@`droplet_address_public $name` true && break
	    sleep 1
	done
    done
}

do_ssh() {
    shift
    name=$1

    shift
    case $name in
	nodes)
	    for name in $MESOSCLOUD_NODES; do
		ssh -o BatchMode=yes root@`droplet_address_public $name` "$@" &
	    done
	    for name in $MESOSCLOUD_NODES; do
		wait
	    done
	    ;;
	masters)
	    for name in $MESOSCLOUD_MASTERS; do
		ssh -o BatchMode=yes root@`droplet_address_public $name` "$@" &
	    done
	    for name in $MESOSCLOUD_MASTERS; do
		wait
	    done
	    ;;
        slaves)
	    for name in $MESOSCLOUD_SLAVES; do
		ssh -o BatchMode=yes root@`droplet_address_public $name` "$@" &
	    done
	    for name in $MESOSCLOUD_SLAVES; do
		wait
	    done
	    ;;
	*)
	    exec ssh -o BatchMode=yes root@`droplet_address_public $name` "$@"
	    ;;
    esac
}

do_delete() {
    do_setup_cache

    say "We're going to delete your droplets ($MESOSCLOUD_NODES)."

    for name in $MESOSCLOUD_NODES; do
	droplet_delete $name
    done

    rm -rf $MESOSCLOUD_TMP
}

do_status() {
    do_setup_cache

    for name in $MESOSCLOUD_NODES; do
        droplet_summary $name
    done

    say "It's time to connect to your mesoscloud!"

    info "SSH example:"
    echo ""

    echo "A=`droplet_address_public ${MESOSCLOUD_NAME}-1`; B=`droplet_address_public ${MESOSCLOUD_NAME}-2`; C=`droplet_address_public ${MESOSCLOUD_NAME}-3`; D=`droplet_address_private ${MESOSCLOUD_NAME}-1`; E=`droplet_address_private ${MESOSCLOUD_NAME}-2`; F=`droplet_address_private ${MESOSCLOUD_NAME}-3`"

    echo "ssh -L 5050:\$D:5050 -L 8080:\$D:8080 -L 4400:\$D:4400 -L 9200:\$D:9200 root@\$A"
}

do_sftp() {
    exec sftp -o BatchMode=yes root@`droplet_address_public $2`
}

#
# setup functions
#

setup_docker() {
    say "Let's setup the docker daemon"

    droplet_ssh "$MESOSCLOUD_NODES" "\
grep -Fq \"'* hard nofile 1048576'\" /etc/security/limits.conf || echo '* hard nofile 1048576' >> /etc/security/limits.conf; \
grep -Fq \"'* soft nofile 1048576'\" /etc/security/limits.conf || echo '* soft nofile 1048576' >> /etc/security/limits.conf; \
grep -Fq \"'* hard nproc 1048576'\" /etc/security/limits.conf || echo '* hard nproc 1048576' >> /etc/security/limits.conf; \
grep -Fq \"'* soft nproc 1048576'\" /etc/security/limits.conf || echo '* soft nproc 1048576' >> /etc/security/limits.conf\
"

    droplet_ssh "$MESOSCLOUD_NODES" "which docker > /dev/null || wget -qO- https://get.docker.com/ | sh"
}

setup_events() {
    say "Let's setup the events container"

    droplet_ssh "$MESOSCLOUD_NODES" "docker pull $IMAGE_EVENTS"

    for name in $MESOSCLOUD_NODES; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep -q ^events\\\$ || docker run -d \
--cpu-period=200000 --cpu-quota=`python -c \"print int($CPU_EVENTS * 200000)\"` \
-v /var/run/docker.sock:/var/run/docker.sock \
-v /srv/events:/srv/events \
--name=events --restart=always $IMAGE_EVENTS\
"
    done
}

setup_zookeeper() {
    say "Let's setup the zookeeper container"

    droplet_ssh "$MESOSCLOUD_MASTERS" "docker pull $IMAGE_ZOOKEEPER"

    for name in $MESOSCLOUD_MASTERS; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep -q ^zookeeper\\\$ || docker run -d \
--cpu-period=200000 --cpu-quota=`python -c \"print int($CPU_ZOOKEEPER * 200000)\"` \
-e MYID=`echo $name | awk -F- '{print $NF}'` \
-e SERVERS=`droplet_address_private ${MESOSCLOUD_NAME}-1`,`droplet_address_private ${MESOSCLOUD_NAME}-2`,`droplet_address_private ${MESOSCLOUD_NAME}-3` \
--name=zookeeper --net=host --restart=always $IMAGE_ZOOKEEPER\
"
	while true; do
	    ssh -o BatchMode=yes root@`droplet_address_public $name` "nc -vz `droplet_address_private $name` 2181" && break
	    sleep 1
	done
    done
}

setup_mesos_master() {
    say "Let's setup the mesos-master container"

    droplet_ssh "$MESOSCLOUD_MASTERS" "docker pull $IMAGE_MESOS_MASTER"

    for name in $MESOSCLOUD_MASTERS; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep -q ^master\\\$ || docker run -d \
--cpu-period=200000 --cpu-quota=`python -c \"print int($CPU_MESOS_MASTER * 200000)\"` \
-e MESOS_HOSTNAME=`droplet_address_private $name` \
-e MESOS_IP=`droplet_address_private $name` \
-e MESOS_QUORUM=2 \
-e MESOS_ZK=zk://`droplet_address_private ${MESOSCLOUD_NAME}-1`:2181,`droplet_address_private ${MESOSCLOUD_NAME}-2`:2181,`droplet_address_private ${MESOSCLOUD_NAME}-3`:2181/mesos \
-e SECRET=$MESOS_SECRET \
--name=master --net=host --restart=always $IMAGE_MESOS_MASTER\
"
	while true; do
	    ssh -o BatchMode=yes root@`droplet_address_public $name` "nc -vz `droplet_address_private $name` 5050" && break
	    sleep 1
	done
    done
}

setup_mesos_slave() {
    say "Let's setup the mesos-slave container"

    droplet_ssh "$MESOSCLOUD_SLAVES" "docker pull $IMAGE_MESOS_SLAVE"

    for name in $MESOSCLOUD_SLAVES; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep -q ^slave\\\$ || docker run -d \
--cpu-period=200000 --cpu-quota=`python -c \"print int($CPU_MESOS_SLAVE * 200000)\"` \
-e MESOS_HOSTNAME=`droplet_address_private $name` \
-e MESOS_IP=`droplet_address_private $name` \
-e MESOS_MASTER=zk://`droplet_address_private ${MESOSCLOUD_NAME}-1`:2181,`droplet_address_private ${MESOSCLOUD_NAME}-2`:2181,`droplet_address_private ${MESOSCLOUD_NAME}-3`:2181/mesos \
-e SECRET=$MESOS_SECRET \
-v /sys/fs/cgroup:/sys/fs/cgroup \
-v /var/run/docker.sock:/var/run/docker.sock \
--name=slave --net=host --privileged --restart=always $IMAGE_MESOS_SLAVE\
"
	while true; do
	    ssh -o BatchMode=yes root@`droplet_address_public $name` "nc -vz `droplet_address_private $name` 5051" && break
	    sleep 1
	done
    done
}

setup_marathon() {
    say "Let's setup the marathon container"

    droplet_ssh "$MESOSCLOUD_MASTERS" "docker pull $IMAGE_MARATHON"

    for name in $MESOSCLOUD_MASTERS; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep -q ^marathon\\\$ || docker run -d \
--cpu-period=200000 --cpu-quota=`python -c \"print int($CPU_MARATHON * 200000)\"` \
-e MARATHON_HOSTNAME=`droplet_address_private $name` \
-e MARATHON_HTTPS_ADDRESS=`droplet_address_private $name` \
-e MARATHON_HTTP_ADDRESS=`droplet_address_private $name` \
-e MARATHON_MASTER=zk://`droplet_address_private ${MESOSCLOUD_NAME}-1`:2181,`droplet_address_private ${MESOSCLOUD_NAME}-2`:2181,`droplet_address_private ${MESOSCLOUD_NAME}-3`:2181/mesos \
-e MARATHON_ZK=zk://`droplet_address_private ${MESOSCLOUD_NAME}-1`:2181,`droplet_address_private ${MESOSCLOUD_NAME}-2`:2181,`droplet_address_private ${MESOSCLOUD_NAME}-3`:2181/marathon \
-e LIBPROCESS_IP=`droplet_address_private $name` \
-e SECRET=$MESOS_SECRET \
--name=marathon --net=host --restart=always $IMAGE_MARATHON\
"
	while true; do
	    ssh -o BatchMode=yes root@`droplet_address_public $name` "nc -vz `droplet_address_private $name` 8080" && break
	    sleep 1
	done
    done
}

setup_chronos() {
    say "Let's setup the chronos container"

    droplet_ssh "$MESOSCLOUD_MASTERS" "docker pull $IMAGE_CHRONOS"

    for name in $MESOSCLOUD_MASTERS; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep -q ^chronos\\\$ || docker run -d \
--cpu-period=200000 --cpu-quota=`python -c \"print int($CPU_CHRONOS * 200000)\"` \
-e CHRONOS_HOSTNAME=`droplet_address_private $name` \
-e CHRONOS_HTTP_ADDRESS=`droplet_address_private $name` \
-e CHRONOS_HTTP_PORT=4400 \
-e CHRONOS_MASTER=zk://`droplet_address_private ${MESOSCLOUD_NAME}-1`:2181,`droplet_address_private ${MESOSCLOUD_NAME}-2`:2181,`droplet_address_private ${MESOSCLOUD_NAME}-3`:2181/mesos \
-e CHRONOS_ZK_HOSTS=`droplet_address_private ${MESOSCLOUD_NAME}-1`:2181,`droplet_address_private ${MESOSCLOUD_NAME}-2`:2181,`droplet_address_private ${MESOSCLOUD_NAME}-3`:2181 \
-e LIBPROCESS_IP=`droplet_address_private $name` \
-e SECRET=$MESOS_SECRET \
--name=chronos --net=host --restart=always $IMAGE_CHRONOS\
"
	while true; do
	    ssh -o BatchMode=yes root@`droplet_address_public $name` "nc -vz `droplet_address_private $name` 4400" && break
	    sleep 1
	done
    done
}

setup_haproxy_marathon() {
    say "Let's setup the haproxy-marathon container"

    droplet_ssh "$MESOSCLOUD_MASTERS" "docker pull $IMAGE_HAPROXY_MARATHON"

    for name in $MESOSCLOUD_MASTERS; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep -q ^haproxy-marathon\\\$ || docker run -d \
--cpu-period=200000 --cpu-quota=`python -c \"print int($CPU_HAPROXY_MARATHON * 200000)\"` \
-e MARATHON=`droplet_address_private $name`:8080 \
-e ZK=`droplet_address_private $name`:2181 \
--name=haproxy-marathon --net=host --restart=always $IMAGE_HAPROXY_MARATHON\
"
    done
}

setup_haproxy() {
    say "Let's setup the haproxy container"

    droplet_ssh "$MESOSCLOUD_NODES" "docker pull $IMAGE_HAPROXY"

    for name in $MESOSCLOUD_NODES; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep -q ^haproxy\\\$ || docker run -d \
--cpu-period=200000 --cpu-quota=`python -c \"print int($CPU_HAPROXY * 200000)\"` \
-e ZK=`droplet_address_private $name`:2181 \
--name=haproxy --net=host --privileged --restart=always $IMAGE_HAPROXY\
"
	while true; do
	    nc -vz `droplet_address_public $name` 80 && break
	    sleep 1
	done
    done
}

setup_elasticsearch() {
    say "Let's setup the elasticsearch container"

    droplet_ssh "$MESOSCLOUD_MASTERS" "docker pull $IMAGE_ELASTICSEARCH"

    for name in $MESOSCLOUD_MASTERS; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep -q ^elasticsearch\\\$ || docker run -d \
--cpu-period=200000 --cpu-quota=`python -c \"print int($CPU_ELASTICSEARCH * 200000)\"` \
-v /srv/elasticsearch/data:/opt/elasticsearch/data \
-v /srv/elasticsearch/logs:/opt/elasticsearch/logs \
--name=elasticsearch --net=host --restart=always $IMAGE_ELASTICSEARCH \
elasticsearch \
-Des.discovery.zen.ping.multicast.enabled=false \
-Des.discovery.zen.ping.unicast.hosts=`droplet_address_private ${MESOSCLOUD_NAME}-1`,`droplet_address_private ${MESOSCLOUD_NAME}-2`,`droplet_address_private ${MESOSCLOUD_NAME}-3`\
"
    done
}

setup_logstash() {
    say "Let's setup the logstash container"

    droplet_ssh "$MESOSCLOUD_MASTERS" "docker pull $IMAGE_LOGSTASH"

    for name in $MESOSCLOUD_MASTERS; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep -q ^logstash\\\$ || docker run -d \
--cpu-period=200000 --cpu-quota=`python -c \"print int($CPU_LOGSTASH * 200000)\"` \
-v /srv/events:/srv/events \
-v /srv/logstash:/srv/logstash \
--name=logstash --net=host --restart=always $IMAGE_LOGSTASH logstash -e \"\
input { file { path => \\\"/srv/events/containers.log-*\\\" codec => json sincedb_path => \\\"/srv/logstash/sincedb\\\" } } output { elasticsearch { protocol => \\\"transport\\\" } }\
\""
    done
}

setup_elasticsearch_curator() {
    say "Let's setup the elasticsearch-curator job"

    cat > $MESOSCLOUD_TMP/job.json <<EOF
{
  "name": "elasticsearch-curator",
  "schedule": "R/`date -u +%Y-%m-%dT%H:%M:%SZ`/P1D",
  "container": {
    "type": "docker",
    "image": "$IMAGE_ELASTICSEARCH"
  },
  "command": "curator delete indices --older-than 7 --time-unit days --timestring %Y.%m.%d",
  "cpus": "0.1",
  "mem": "512"
}
EOF

    scp $MESOSCLOUD_TMP/job.json root@`droplet_address_public ${MESOSCLOUD_NAME}-1`:

    droplet_ssh ${MESOSCLOUD_NAME}-1 "\
curl -L -H \"Content-Type: application/json\" -X POST -d @job.json `droplet_address_private ${MESOSCLOUD_NAME}-1`:4400/scheduler/iso8601\
"
}

#
# main
#

main() {
    config_write

    do_setup "$@"

    if [ -n "$1" ]; then
	eval do_$1 "$@"
	exit 0
    fi

    do_create "$@"

    setup_docker
    setup_events
    setup_zookeeper
    setup_mesos_master
    setup_mesos_slave
    setup_marathon
    setup_chronos
    setup_haproxy_marathon
    setup_haproxy
    setup_elasticsearch
    setup_logstash
    setup_elasticsearch_curator

    do_status
}

main "$@"
