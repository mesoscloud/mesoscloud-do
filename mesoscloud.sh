#!/bin/sh

# mesoscloud
#
# https://github.com/mesoscloud/mesoscloud-do

main() {

    # depends
    if [ -z "$DIGITALOCEAN_ACCESS_TOKEN" ]; then
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
    M=.mesoscloud

    #
    CLUSTER=${CLUSTER:-node}

    nodes="${CLUSTER}-1 ${CLUSTER}-2 ${CLUSTER}-3"
    masters="${CLUSTER}-1 ${CLUSTER}-2 ${CLUSTER}-3"
    slaves="${CLUSTER}-1 ${CLUSTER}-2 ${CLUSTER}-3"

    SIZE=${SIZE:-4gb}

    REGION=${REGION:-nyc3}

    #
    if [ "$1" = ssh ]; then
	touch $M/droplets.json.cache

	shift
	name=$1

	shift
	case $name in
	    nodes)
		for name in $nodes; do
		    ssh -o BatchMode=yes root@`droplet_address_public $name` "$@" &
		done
		for name in $nodes; do
		    wait
		done
		exit 0
		;;
	    masters)
		for name in $masters; do
		    ssh -o BatchMode=yes root@`droplet_address_public $name` "$@" &
		done
		for name in $masters; do
		    wait
		done
		exit 0
		;;
            slaves)
		for name in $slaves; do
		    ssh -o BatchMode=yes root@`droplet_address_public $name` "$@" &
		done
		for name in $slaves; do
		    wait
		done
		exit 0
		;;
	    *)
		exec ssh -o BatchMode=yes root@`droplet_address_public $name` "$@"
		;;
	esac
    fi

    #
    M=.mesoscloud
    mkdir -p $M
    rm -rf $M/*.json*

    #
    if [ -z "$SECRET" ]; then
	if [ -e $M/secret ]; then
	    SECRET=`cat $M/secret`
	else
	    SECRET=`pw 32`
	    touch $M/secret
	    chmod 600 $M/secret
	    echo $SECRET > $M/secret
	fi
    fi

    #
    mesoscloud_status() {
	for name in $nodes; do
	    droplet_summary $name
	done

	echo ""
	say "It's time to connect to your mesoscloud!"
	echo ""
	info "SSH example:"
	echo ""
	echo "ssh -L 5050:`droplet_address_private ${CLUSTER}-1`:5050 -L 8080:`droplet_address_private ${CLUSTER}-1`:8080 -L 4400:`droplet_address_private ${CLUSTER}-1`:4400 -L 9200:`droplet_address_private ${CLUSTER}-1`:9200 root@`droplet_address_public ${CLUSTER}-1`"
	echo ""
	echo "Note, you may need to substitute private addresses depending on which node is the current mesos master / leader."
	echo ""
	echo "open http://localhost:5050  # Mesos"
	echo "open http://localhost:8080  # Marathon"
	echo "open http://localhost:4400  # Chronos"
	echo ""
    }

    #
    if [ "$1" = delete ]; then
	say "We're going to delete your droplets ($nodes)."

	for name in $nodes; do
	    droplet_delete $name
	done

	exit 0
    fi

    #
    if [ "$1" = status ]; then
	touch $M/droplets.json.cache

	mesoscloud_status

	exit 0
    fi

    #
    say "We're going to create your droplets ($nodes)!"

    for name in $nodes; do
	droplet_exists $name || droplet_create $name
    done

    for name in $nodes; do
	while droplet_locked $name; do
            sleep 1
	done
    done

    #
    touch $M/droplets.json.cache

    #
    say "Let's make sure we can connect."

    for name in $nodes; do
	info "ssh-keygen -R" $name
	ssh-keygen -R `droplet_address_public $name`
    done

    for name in $nodes; do
	info "droplet ssh" $name
	while true; do
	    ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@`droplet_address_public $name` true && break
	    sleep 1
	done
    done

    #
    say "docker"

    droplet_ssh "$nodes" "\
grep -Fq \"'* hard nofile 1048576'\" /etc/security/limits.conf || echo '* hard nofile 1048576' >> /etc/security/limits.conf; \
grep -Fq \"'* soft nofile 1048576'\" /etc/security/limits.conf || echo '* soft nofile 1048576' >> /etc/security/limits.conf; \
grep -Fq \"'* hard nproc 1048576'\" /etc/security/limits.conf || echo '* hard nproc 1048576' >> /etc/security/limits.conf; \
grep -Fq \"'* soft nproc 1048576'\" /etc/security/limits.conf || echo '* soft nproc 1048576' >> /etc/security/limits.conf\
"

    droplet_ssh "$nodes" "which docker > /dev/null || wget -qO- https://get.docker.com/ | sh"

    #
    say "events"

    EVENTS_IMAGE=mesoscloud/events:0.1.0

    droplet_ssh "$nodes" "docker pull $EVENTS_IMAGE"

    for name in $nodes; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep ^events\\\$ || docker run -d \
-v /var/run/docker.sock:/var/run/docker.sock \
-v /srv/events:/srv/events \
--name=events --restart=always $EVENTS_IMAGE\
"
    done

    #
    say "zookeeper"

    ZOOKEEPER_IMAGE=mesoscloud/zookeeper:3.4.6-ubuntu-14.04

    droplet_ssh "$masters" "docker pull $ZOOKEEPER_IMAGE"

    for name in $masters; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep ^zookeeper\\\$ || docker run -d \
-e MYID=`echo $name | awk -F- '{print $NF}'` \
-e SERVERS=`droplet_address_private ${CLUSTER}-1`,`droplet_address_private ${CLUSTER}-2`,`droplet_address_private ${CLUSTER}-3` \
--name=zookeeper --net=host --restart=always $ZOOKEEPER_IMAGE\
"
	while true; do
	    ssh -o BatchMode=yes root@`droplet_address_public $name` "nc -vz `droplet_address_private $name` 2181" && break
	    sleep 1
	done
    done

    #
    say "mesos-master"

    MESOS_MASTER_IMAGE=mesoscloud/mesos-master:0.23.0-ubuntu-14.04

    droplet_ssh "$masters" "docker pull $MESOS_MASTER_IMAGE"

    for name in $masters; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep ^master\\\$ || docker run -d \
-e MESOS_HOSTNAME=`droplet_address_private $name` \
-e MESOS_IP=`droplet_address_private $name` \
-e MESOS_QUORUM=2 \
-e MESOS_ZK=zk://`droplet_address_private ${CLUSTER}-1`:2181,`droplet_address_private ${CLUSTER}-2`:2181,`droplet_address_private ${CLUSTER}-3`:2181/mesos \
-e SECRET=$SECRET \
--name=master --net=host --restart=always $MESOS_MASTER_IMAGE\
"
	while true; do
	    ssh -o BatchMode=yes root@`droplet_address_public $name` "nc -vz `droplet_address_private $name` 5050" && break
	    sleep 1
	done
    done

    #
    say "mesos-slave"

    MESOS_SLAVE_IMAGE=mesoscloud/mesos-slave:0.23.0-ubuntu-14.04

    droplet_ssh "$slaves" "docker pull $MESOS_SLAVE_IMAGE"

    for name in $slaves; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep ^slave\\\$ || docker run -d \
-e MESOS_HOSTNAME=`droplet_address_private $name` \
-e MESOS_IP=`droplet_address_private $name` \
-e MESOS_MASTER=zk://`droplet_address_private ${CLUSTER}-1`:2181,`droplet_address_private ${CLUSTER}-2`:2181,`droplet_address_private ${CLUSTER}-3`:2181/mesos \
-e SECRET=$SECRET \
-v /sys/fs/cgroup:/sys/fs/cgroup \
-v /var/run/docker.sock:/var/run/docker.sock \
--name=slave --net=host --privileged --restart=always $MESOS_SLAVE_IMAGE\
"
	while true; do
	    ssh -o BatchMode=yes root@`droplet_address_public $name` "nc -vz `droplet_address_private $name` 5051" && break
	    sleep 1
	done
    done

    #
    say "marathon"

    MARATHON_IMAGE=mesoscloud/marathon:0.10.0-ubuntu-14.04

    droplet_ssh "$masters" "docker pull $MARATHON_IMAGE"

    for name in $masters; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep ^marathon\\\$ || docker run -d \
-e MARATHON_HOSTNAME=`droplet_address_private $name` \
-e MARATHON_HTTPS_ADDRESS=`droplet_address_private $name` \
-e MARATHON_HTTP_ADDRESS=`droplet_address_private $name` \
-e MARATHON_MASTER=zk://`droplet_address_private ${CLUSTER}-1`:2181,`droplet_address_private ${CLUSTER}-2`:2181,`droplet_address_private ${CLUSTER}-3`:2181/mesos \
-e MARATHON_ZK=zk://`droplet_address_private ${CLUSTER}-1`:2181,`droplet_address_private ${CLUSTER}-2`:2181,`droplet_address_private ${CLUSTER}-3`:2181/marathon \
-e LIBPROCESS_IP=`droplet_address_private $name` \
-e SECRET=$SECRET \
--name=marathon --net=host --restart=always $MARATHON_IMAGE\
"
	while true; do
	    ssh -o BatchMode=yes root@`droplet_address_public $name` "nc -vz `droplet_address_private $name` 8080" && break
	    sleep 1
	done
    done

    #
    say "chronos"

    CHRONOS_IMAGE=mesoscloud/chronos:2.3.4-ubuntu-14.04

    droplet_ssh "$masters" "docker pull $CHRONOS_IMAGE"

    for name in $masters; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep ^chronos\\\$ || docker run -d \
-e CHRONOS_HOSTNAME=`droplet_address_private $name` \
-e CHRONOS_HTTP_ADDRESS=`droplet_address_private $name` \
-e CHRONOS_HTTP_PORT=4400 \
-e CHRONOS_MASTER=zk://`droplet_address_private ${CLUSTER}-1`:2181,`droplet_address_private ${CLUSTER}-2`:2181,`droplet_address_private ${CLUSTER}-3`:2181/mesos \
-e CHRONOS_ZK_HOSTS=`droplet_address_private ${CLUSTER}-1`:2181,`droplet_address_private ${CLUSTER}-2`:2181,`droplet_address_private ${CLUSTER}-3`:2181 \
-e LIBPROCESS_IP=`droplet_address_private $name` \
-e SECRET=$SECRET \
--name=chronos --net=host --restart=always $CHRONOS_IMAGE\
"
	while true; do
	    ssh -o BatchMode=yes root@`droplet_address_public $name` "nc -vz `droplet_address_private $name` 4400" && break
	    sleep 1
	done
    done

    #
    say "haproxy-marathon"

    HAPROXY_MARATHON_IMAGE=mesoscloud/haproxy-marathon:0.1.0

    droplet_ssh "$masters" "docker pull $HAPROXY_MARATHON_IMAGE"

    for name in $masters; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep ^haproxy-marathon\\\$ || docker run -d \
-e MARATHON=`droplet_address_private $name`:8080 \
-e ZK=`droplet_address_private $name`:2181 \
--name=haproxy-marathon --net=host --restart=always $HAPROXY_MARATHON_IMAGE\
"
    done

    #
    say "haproxy"

    HAPROXY_IMAGE=mesoscloud/haproxy:1.5.14-ubuntu-14.04

    droplet_ssh "$nodes" "docker pull $HAPROXY_IMAGE"

    for name in $nodes; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep ^haproxy\\\$ || docker run -d \
-e ZK=`droplet_address_private $name`:2181 \
--name=haproxy --net=host --privileged --restart=always $HAPROXY_IMAGE\
"
	while true; do
	    nc -vz `droplet_address_public $name` 80 && break
	    sleep 1
	done
    done

    #
    say "elasticsearch"

    ELASTICSEARCH_IMAGE=mesoscloud/elasticsearch:1.7.1-ubuntu-14.04

    droplet_ssh "$masters" "docker pull $ELASTICSEARCH_IMAGE"

    for name in $masters; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep ^elasticsearch\\\$ || docker run -d \
-v /srv/elasticsearch/data:/opt/elasticsearch/data \
-v /srv/elasticsearch/logs:/opt/elasticsearch/logs \
--name=elasticsearch --net=host --restart=always $ELASTICSEARCH_IMAGE \
elasticsearch \
-Des.discovery.zen.ping.multicast.enabled=false \
-Des.discovery.zen.ping.unicast.hosts=`droplet_address_private ${CLUSTER}-1`,`droplet_address_private ${CLUSTER}-2`,`droplet_address_private ${CLUSTER}-3`\
"
    done

    #
    say "logstash"

    LOGSTASH_IMAGE=mesoscloud/logstash:1.5.4-ubuntu-14.04

    droplet_ssh "$masters" "docker pull $LOGSTASH_IMAGE"

    for name in $masters; do
	droplet_ssh $name "\
docker ps | sed 1d | awk \"{print \\\$NF}\" | grep ^logstash\\\$ || docker run -d \
-v /srv/events:/srv/events \
-v /srv/logstash:/srv/logstash \
--name=logstash --net=host --restart=always $LOGSTASH_IMAGE logstash -e \"\
input { file { path => \\\"/srv/events/containers.log-*\\\" codec => json sincedb_path => \\\"/srv/logstash/sincedb\\\" } } output { elasticsearch { protocol => \\\"transport\\\" } }\
\""
    done

    #
    say "elasticsearch-curator"

    cat > $M/job.json <<EOF
{
  "name": "elasticsearch-curator",
  "schedule": "R/`date -u +%Y-%m-%dT%H:%M:%SZ`/P1D",
  "container": {
    "type": "docker",
    "image": "$ELASTICSEARCH_IMAGE"
  },
  "command": "curator delete indices --older-than 7 --time-unit days --timestring %Y.%m.%d",
  "cpus": "0.1",
  "mem": "512"
}
EOF

    scp $M/job.json root@`droplet_address_public ${CLUSTER}-1`:

    droplet_ssh ${CLUSTER}-1 "\
curl -L -H \"Content-Type: application/json\" -X POST -d @job.json `droplet_address_private ${CLUSTER}-1`:4400/scheduler/iso8601\
"

    #
    say "s3fs"

    droplet_ssh "$nodes" "\
which s3fs > /dev/null || {
apt-get install -y automake autotools-dev g++ git libcurl4-gnutls-dev libfuse-dev libssl-dev libxml2-dev make pkg-config &&
curl -fL https://github.com/s3fs-fuse/s3fs-fuse/archive/v1.79.tar.gz | tar xzf - -C /usr/src &&
cd /usr/src/s3fs-fuse-1.79 &&
./autogen.sh &&
./configure --prefix=/usr &&
make &&
make install;
}\
"

    droplet_ssh "$nodes" "\
touch /etc/s3fs &&
chmod 600 /etc/s3fs &&
echo $AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY > /etc/s3fs
"

    droplet_ssh "$nodes" "\
grep -Fq s3fs /etc/fstab || echo \"s3fs#$BUCKET /data fuse allow_other,passwd_file=/etc/s3fs 0 0\" >> /etc/fstab
"

    droplet_ssh "$nodes" "\
mkdir -p /data
"

    droplet_ssh "$nodes" "\
mount | grep -q \"^s3fs on /data\" || mount /data
"

    #
    mesoscloud_status

}


#
# functions
#

C='\033[0;36m'
W='\033[1;39m'
X='\033[0m'

info() {

    L=$M/.lock

    while [ -e $L ]; do
	sleep 0.05
    done
    touch $L

    msg="$1"

    if [ -n "$2" ]; then
	msg="$2 $1"
    fi

    echo "$W$msg$X" >&2

    if [ -n "$3" ]; then
	echo "$C$3$X" >&2
    fi

    rm -f $L
}

say() {
    echo " _`python -c "print '_' * len('''$@''')"`_"
    echo "< $@ >"
    echo " -`python -c "print '-' * len('''$@''')"`-"
    echo "	\\   $C^${X}__$C^$X"
    echo "	 \\  (oo)\\_______"
    echo "	    (__)\\       )\\/\\"
    echo "		||----w |"
    echo "		||     ||"
}

err() {
    echo " _`python -c "print '_' * len('''$@''')"`_"
    echo "< $@ >"
    echo " -`python -c "print '-' * len('''$@''')"`-"
    echo "	\\   $C^${X}__$C^$X"
    echo "	 \\  (xx)\\_______"
    echo "	    (__)\\       )\\/\\"
    echo "	      U ||----w |"
    echo "		||     ||"
    exit 1
}

pw() {
    python -c "import os, re; print(re.sub(r'[^a-zA-Z0-9]', '', os.urandom($1 * 1024))[:$1])"
}

# droplet

droplets() {

    if [ -e $M/droplets.json -a -e $M/droplets.json.cache ]; then
	return
    fi

    curl -fsS -H 'Content-Type: application/json' -H "Authorization: Bearer $DIGITALOCEAN_ACCESS_TOKEN" https://api.digitalocean.com/v2/droplets > $M/droplets.json

    if [ $? -ne 0 ]; then
	err "We couldn't fetch a list of droplets from api.digitalocean.com :("
    fi

    if ! python -m json.tool $M/droplets.json > /dev/null; then
	err "We couldn't parse output from api.digitalocean.com  :("
    fi
}

droplet_exists() {
    test -n "$1" || err "usage: droplet_exists <name>"

    info "droplet exists?" "$1"

    droplets

    cat $M/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1
}

droplet_summary() {
    test -n "$1" || err "usage: droplet_summary <name>"

    info "droplet summary" "$1"

    droplets

    cat $M/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1

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

    curl -fsS -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $DIGITALOCEAN_ACCESS_TOKEN" -d "{\"name\":\"$1\",\"region\":\"$REGION\",\"size\":\"$SIZE\",\"image\":\"ubuntu-14-04-x64\",\"ssh_keys\":[\"$SSH_KEY_FINGERPRINT\"],\"backups\":false,\"ipv6\":false,\"user_data\":null,\"private_networking\":true}" https://api.digitalocean.com/v2/droplets > $M/droplets.json

    if [ $? -ne 0 ]; then
	err "We couldn't fetch a list of droplets from api.digitalocean.com :("
    fi

    if ! python -m json.tool $M/droplets.json > /dev/null; then
	err "We couldn't parse output from api.digitalocean.com :("
    fi

}

droplet_locked() {
    test -n "$1" || exit 1

    info "droplet locked?" "$1"

    id=`droplet_id $1` || err "We can't find the droplet! :("

    curl -fsS -H 'Content-Type: application/json' -H "Authorization: Bearer $DIGITALOCEAN_ACCESS_TOKEN" https://api.digitalocean.com/v2/droplets/$id > $M/$1.json

    if [ $? -ne 0 ]; then
	err "We couldn't fetch a droplet from api.digitalocean.com :("
    fi

    if ! python -m json.tool $M/$1.json > /dev/null; then
	err "We couldn't parse output from api.digitalocean.com :("
    fi

    cat $M/$1.json | python -c "import json, sys; sys.exit(0 if json.load(sys.stdin)['droplet']['locked'] else 1)"
}

droplet_id() {
    test -n "$1" || err "usage: droplet_id <name>"

    droplets

    cat $M/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1

    cat $M/droplets.json | python -c "import json, sys; print([d['id'] for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][-1])"
}

droplet_image() {
    test -n "$1" || err "usage: droplet_image <name>"

    droplets

    cat $M/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1

    cat $M/droplets.json | python -c "import json, sys; print('%(distribution)s %(name)s' % [d['image'] for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][-1])"
}

droplet_kernel() {
    test -n "$1" || err "usage: droplet_kernel <name>"

    droplets

    cat $M/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1

    cat $M/droplets.json | python -c "import json, sys; print('%(version)s' % [d['kernel'] for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][-1])"
}

droplet_size() {
    test -n "$1" || err "usage: droplet_size <name>"

    droplets

    cat $M/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1

    cat $M/droplets.json | python -c "import json, sys; print(['%(memory)s MB, %(vcpus)s CPU, %(disk)s GB' % d['size'] for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][-1])"
}

droplet_region() {
    test -n "$1" || err "usage: droplet_region <name>"

    droplets

    cat $M/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1

    cat $M/droplets.json | python -c "import json, sys; print([d['region']['name'] for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][-1])"
}

droplet_status() {
    test -n "$1" || err "usage: droplet_status <name>"

    droplets

    cat $M/droplets.json | python -c "import json, sys; sys.exit(0 if [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'] else 1)" || return 1

    cat $M/droplets.json | python -c "import json, sys; print([d['status'] for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][-1])"
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

    cat $M/droplets.json | python -c "import json, sys; print([n for n in [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][0]['networks']['v4'] if n['type'] == 'public'][0]['ip_address'])"
}

droplet_address_private() {
    test -n "$1" || exit 1

    droplets

    cat $M/droplets.json | python -c "import json, sys; print([n for n in [d for d in json.load(sys.stdin)['droplets'] if d['name'] == '$1'][0]['networks']['v4'] if n['type'] == 'private'][0]['ip_address'])"
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
#
#

main "$@"
