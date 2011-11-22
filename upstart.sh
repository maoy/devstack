#!/usr/bin/env bash

# **upstart.sh** is an opinionated openstack developer installation.

# This script installs *nova*, *glance*, *horizon* and *keystone*

# Use this script after you have used stack.sh, and you are satisfied with
# the configuration, but do not like to run it in screen.
# What this script does is to create upstart scripts in /etc/init 
# so that the services are automatically started after the machine boots,
# and the logs are stored in /var/log.

# upstart.sh works with the following OpenStack services:
# g-api,g-reg,key,n-api,n-cpu,n-net,n-sch,n-vnc,horizon,mysql,rabbit,openstackx
# for mysql, rabbit, openstackx, and horizon, the script does nothing but they
# shoud just work.

# Sanity Check
# ============

# Warn users who aren't on oneiric, but allow them to override check and attempt
# installation with ``FORCE=yes ./stack``
DISTRO=$(lsb_release -c -s)

if [[ ! ${DISTRO} =~ (oneiric) ]]; then
    echo "WARNING: this script has only been tested on oneiric"
    if [[ "$FORCE" != "yes" ]]; then
        echo "If you wish to run this script anyway run with FORCE=yes"
        exit 1
    fi
fi

# Keep track of the current devstack directory.
TOP_DIR=$(cd $(dirname "$0") && pwd)

# upstart.sh keeps the upstart templates in external files.
# You can find these in the ``files`` directory (next to this script).  
# We will reference this
# directory using the ``FILES`` variable in this script.
FILES=$TOP_DIR/files
if [ ! -d $FILES ]; then
    echo "ERROR: missing devstack/files - did you grab more than just stack.sh?"
    exit 1
fi

# Settings
# ========

#
# We source our settings from ``stackrc``.  This file is distributed with devstack
# and contains locations for what repositories to use.  If you want to use other
# repositories and branches, you can add your own settings with another file called
# ``localrc``
#
# If ``localrc`` exists, then ``stackrc`` will load those settings.  This is
# useful for changing a branch or repository to test other versions.  Also you
# can store your other settings like **MYSQL_PASSWORD** or **ADMIN_PASSWORD** instead
# of letting devstack generate random ones for you.

# Actually the only variables we need are DEST and ENABLED_SERVICES, in case you 
# have customized it.
source ./stackrc

# Destination path for installation ``DEST``
DEST=${DEST:-/opt/stack}

# You should use the regular user that you used for stack.sh to run this script.

if [[ $EUID -eq 0 ]]; then
    echo "You are running this script as root. Don't. Use the user created by stack.sh instead."
    exit 1
fi

# Set the destination directories for openstack projects
NOVA_DIR=$DEST/nova
HORIZON_DIR=$DEST/horizon
GLANCE_DIR=$DEST/glance
KEYSTONE_DIR=$DEST/keystone
NOVACLIENT_DIR=$DEST/python-novaclient
OPENSTACKX_DIR=$DEST/openstackx
NOVNC_DIR=$DEST/noVNC
SWIFT_DIR=$DEST/swift
SWIFT_KEYSTONE_DIR=$DEST/swift-keystone2
QUANTUM_DIR=$DEST/quantum

# Default Quantum Plugin
Q_PLUGIN=${Q_PLUGIN:-openvswitch}

# Specify which services to launch.  These generally correspond to screen tabs
ENABLED_SERVICES=${ENABLED_SERVICES:-g-api,g-reg,key,n-api,n-cpu,n-net,n-sch,n-vnc,horizon,mysql,rabbit,openstackx}

# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following along as the install occurs.
# set -o xtrace

# Install upstart scripts
# ================
#
# Only install the services specified in ``ENABLED_SERVICES``
CMD=$1

if [ "$CMD" = "" ]; then
    echo "usage: upstart.sh [install|uninstall|start|stop|status]"
    exit 1
fi

function upstart_install {
    SHORT_NAME=$1 # e.g. n-cpu
    BIN_NAME=$2 # e.g. nova-compute
    SERVICE_DIR=$3 # e.g. $NOVA_DIR
    if [[ "$ENABLED_SERVICES" =~ "$SHORT_NAME" ]]; then
        # first, generate ${BIN_NAME}.conf and put in/etc/init
        sudo cp -f $FILES/upstart/init/$BIN_NAME.conf /etc/init/
        sudo sed -e "s,%USER%,$USER,g" -i /etc/init/$BIN_NAME.conf
        sudo sed -e "s,%DIR%,$SERVICE_DIR,g" -i /etc/init/$BIN_NAME.conf
        sudo sed -e "s,%LOGDIR%,/var/log,g" -i /etc/init/$BIN_NAME.conf
        # second, make symbol link in /etc/init.d/
        sudo rm -f /etc/init.d/$BIN_NAME
        sudo ln -s /lib/init/upstart-job /etc/init.d/$BIN_NAME
        # finally, install logrotate
        sudo cp -f $FILES/upstart/logrotate.d/$BIN_NAME /etc/logrotate.d/
        echo "$BIN_NAME is installed."
    fi
}

function upstart_uninstall {
    # uninstall implies stop?
    upstart_stop $1 $2 $3
    SHORT_NAME=$1 # e.g. n-cpu
    BIN_NAME=$2 # e.g. nova-compute
    SERVICE_DIR=$3 # e.g. $NOVA_DIR
    if [[ "$ENABLED_SERVICES" =~ "$SHORT_NAME" ]]; then
        sudo rm -f /etc/init.d/$BIN_NAME
        sudo rm -f /etc/init/$BIN_NAME.conf
        sudo rm -f /etc/logrotate.d/$BIN_NAME
        echo "$BIN_NAME is uninstalled."
    fi
}

function upstart_start {
    SHORT_NAME=$1 # e.g. n-cpu
    BIN_NAME=$2 # e.g. nova-compute
    SERVICE_DIR=$3 # e.g. $NOVA_DIR
    if [[ "$ENABLED_SERVICES" =~ "$SHORT_NAME" ]]; then
        sudo service $BIN_NAME start
    fi
}

function upstart_stop {
    SHORT_NAME=$1 # e.g. n-cpu
    BIN_NAME=$2 # e.g. nova-compute
    SERVICE_DIR=$3 # e.g. $NOVA_DIR
    if [[ "$ENABLED_SERVICES" =~ "$SHORT_NAME" ]]; then
        sudo service $BIN_NAME stop
    fi
}

function upstart_status {
    SHORT_NAME=$1 # e.g. n-cpu
    BIN_NAME=$2 # e.g. nova-compute
    SERVICE_DIR=$3 # e.g. $NOVA_DIR
    if [[ "$ENABLED_SERVICES" =~ "$SHORT_NAME" ]]; then
        sudo service $BIN_NAME status
    fi
}


# install the glance registry service
upstart_$CMD g-reg glance-registry $GLANCE_DIR

# install the glance api 
upstart_$CMD g-api glance-api $GLANCE_DIR

# install keystone
upstart_$CMD key keystone $KEYSTONE_DIR

# install the nova-* services
upstart_$CMD n-api nova-api $NOVA_DIR
upstart_$CMD n-cpu nova-compute $NOVA_DIR
upstart_$CMD n-vol nova-volume $NOVA_DIR
upstart_$CMD n-net nova-network $NOVA_DIR
upstart_$CMD n-sch nova-scheduler $NOVA_DIR

# install novnc
upstart_$CMD n-vnc nova-novnc $NOVNC_DIR
# novnc install has a special replacement
if [ "$CMD" = "install" ]; then
    if [[ "$ENABLED_SERVICES" =~ "n-vnc" ]]; then
        sudo sed -e "s,%NOVA_DIR%,$NOVA_DIR,g" -i /etc/init/nova-novnc.conf
    fi
fi


# indicate how long this took to run (bash maintained variable 'SECONDS')
# echo "upstart.sh completed in $SECONDS seconds."

