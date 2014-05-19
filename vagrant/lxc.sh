#!/bin/bash
# Setup lxc boxes to run tests

dir=$(dirname $0)

. $dir/functions.sh

# basic packages
apt-get install -y lxc bridge-utils libvirt-bin debootstrap clusterssh dnsmasq

echo "cgroup  /sys/fs/cgroup  cgroup  defaults  0   0" >> /etc/fstab
mount /sys/fs/cgroup

lxc-checkconfig

function buildbox() {
    id=$1
    num=$2

    container=/var/lib/lxc/$id

    if [[  -d $container ]]; then 
        echo "container $container already exists"  
        lxc-stop -n $i
    else
        echo "creating container $container"
        # create box - could clone after the first but it seems that debootstrap caches dloaded
        # stuff so creating is fast anyway
        SUITE=jessie MIRROR=http://ftp.fr.debian.org/debian lxc-create -n "$id" -t debian
        # install iptables for traffic shaping in tests
        chroot $container/rootfs apt-get install -y iptables        
    fi
    # update configuration, expecially mac address
    cat > "$container/config" <<EOF
lxc.rootfs = /var/lib/lxc/$id/rootfs

# Common configuration
lxc.include = /usr/share/lxc/config/debian.common.conf

# Container specific configuration
lxc.mount = /var/lib/lxc/$id/fstab
lxc.utsname = $id
lxc.arch = amd64

#network configuration
lxc.network.type = veth
lxc.network.flags = up
lxc.network.link = virbr0
lxc.network.ipv4 = 0.0.0.0/24
lxc.network.hwaddr = 00:1E:62:AA:AA:$(printf '%X\n' $((0xAA + $num)))
EOF

    # TODO adjust number of hosts...
    update_etc_hosts "$container/rootfs/etc/hosts"
}

function build_all_boxes() {
    NUM=0

    for i in n1 n2 n3 n4 n5; do
        buildbox $i $NUM
        NUM=$(($NUM + 1))
    done
}

function start_all_boxes() {
    for i in n1 n2 n3 n4 n5; do
        lxc-start -n $i -d

        wait_host_is_up $i

        # add host key to vagrant's known_hosts keys
        su vagrant -c "ssh-keygen -R $id"
        ssh-keyscan -H $i >> ~vagrant/.ssh/known_hosts

        container=/var/lib/lxc/$id

        # add vagrant's private key to hosts' root account authorized keys
        sshdir=$container/rootfs/root/.ssh
        [[ -d $sshdir ]] || mkdir -p $sshdir
        chmod 0700 $sshdir

        cat ~vagrant/.ssh/id_rsa.pub > $container/rootfs/root/.ssh/authorized_keys
    done
}

build_all_boxes
start_all_boxes
