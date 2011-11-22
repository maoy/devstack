#!/usr/bin/env bash

# **upstart.sh** is an opinionated openstack developer installation.

# This script installs and configures *nova*, *glance*, *horizon* and *keystone*

# This script allows you to specify configuration options of what git
# repositories to use, enabled services, network configuration and various
# passwords.  If you are crafty you can run the script on multiple nodes using
# shared settings for common resources (mysql, rabbitmq) and build a multi-node
# developer install.

# To keep this script simple we assume you are running on an **Ubuntu 11.10
# Oneiric** machine.  It should work in a VM or physical server.  Additionally
# we put the list of *apt* and *pip* dependencies and other configuration files
# in this repo.  So start by grabbing this script and the dependencies.

# Learn more and get the most recent version at http://devstack.org

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

# stack.sh keeps the list of **apt** and **pip** dependencies in external
# files, along with config templates and other useful files.  You can find these
# in the ``files`` directory (next to this script).  We will reference this
# directory using the ``FILES`` variable in this script.
FILES=$TOP_DIR/files
if [ ! -d $FILES ]; then
    echo "ERROR: missing devstack/files - did you grab more than just stack.sh?"
    exit 1
fi



# Settings
# ========

# This script is customizable through setting environment variables.  If you
# want to override a setting you can either::
#
#     export MYSQL_PASSWORD=anothersecret
#     ./stack.sh
#
# You can also pass options on a single line ``MYSQL_PASSWORD=simple ./stack.sh``
#
# Additionally, you can put any local variables into a ``localrc`` file, like::
#
#     MYSQL_PASSWORD=anothersecret
#     MYSQL_USER=hellaroot
#
# We try to have sensible defaults, so you should be able to run ``./stack.sh``
# in most cases.
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
source ./stackrc

# Destination path for installation ``DEST``
DEST=${DEST:-/opt/stack}

# Configure services to syslog instead of writing to individual log files
SYSLOG=${SYSLOG:-False}



# OpenStack is designed to be run as a regular user (Horizon will fail to run
# as root, since apache refused to startup serve content from root user).  If
# stack.sh is run as root, it automatically creates a stack user with
# sudo privileges and runs as that user.

if [[ $EUID -eq 0 ]]; then
    ROOTSLEEP=${ROOTSLEEP:-10}
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
set -o xtrace


# Install upstart
# ================
#



# Launch Services
# ===============

# nova api crashes if we start it with a regular screen command,
# so send the start command by forcing text into the window.
# Only run the services specified in ``ENABLED_SERVICES``

# our screen helper to launch a service in a hidden named screen
function screen_it {
    NL=`echo -ne '\015'`
    if [[ "$ENABLED_SERVICES" =~ "$1" ]]; then
        if [[ "$USE_TMUX" =~ "yes" ]]; then
            tmux new-window -t stack -a -n "$1" "bash"
            tmux send-keys "$2" C-M
        else
            screen -S stack -X screen -t $1
            # sleep to allow bash to be ready to be send the command - we are
            # creating a new window in screen and then sends characters, so if
            # bash isn't running by the time we send the command, nothing happens
            sleep 1
            screen -S stack -p $1 -X stuff "$2$NL"
        fi
    fi
}

function upstart_install {
    SHORT_NAME=$1
    BIN_NAME=$2
    SERVICE_DIR=$3
    if [[ "$ENABLED_SERVICES" =~ "$SHORT_NAME" ]]; then
        # first, generate ${BIN_NAME}.conf to /etc/init
        sudo cp -f $FILES/upstart/init/$BIN_NAME.conf /etc/init/
        sudo sed -e "s,%USER%,$USER,g" -i /etc/init/$BIN_NAME.conf
        sudo sed -e "s,%DIR%,$SERVICE_DIR,g" -i /etc/init/$BIN_NAME.conf
        sudo sed -e "s,%LOGDIR%,/var/log,g" -i /etc/init/$BIN_NAME.conf
        # second make symbol link in /etc/init.d/
        sudo rm -f /etc/init.d/$BIN_NAME
        sudo ln -s /lib/init/upstart-job /etc/init.d/$BIN_NAME
    fi
}

# create a new named screen to run processes in
#screen -d -m -S stack -t stack
sleep 1


if [[ "$ENABLED_SERVICES" =~ "n-sch" ||
      "$ENABLED_SERVICES" =~ "n-api" ||
      "$ENABLED_SERVICES" =~ "n-cpu" ||
      "$ENABLED_SERVICES" =~ "n-vnc" ||
      "$ENABLED_SERVICES" =~ "n-vol" ||
      "$ENABLED_SERVICES" =~ "n-net" ]]; then
    # if we have any nova service, we want to get rid of --nodaemon line
    sed '/nodaemon/d' -i $NOVA_DIR/bin/nova.conf
fi
# launch the glance registry service
#if [[ "$ENABLED_SERVICES" =~ "g-reg" ]]; then
#    screen_it g-reg "cd $GLANCE_DIR; bin/glance-registry --config-file=etc/glance-registry.conf"
#fi
upstart_install g-reg glance-registry $GLANCE_DIR

# launch the glance api and wait for it to answer before continuing
upstart_install g-api glance-api $GLANCE_DIR
#if [[ "$ENABLED_SERVICES" =~ "g-api" ]]; then
#    screen_it g-api "cd $GLANCE_DIR; bin/glance-api --config-file=etc/glance-api.conf"
#    echo "Waiting for g-api ($GLANCE_HOSTPORT) to start..."
#    if ! timeout $SERVICE_TIMEOUT sh -c "while ! wget -q -O- http://$GLANCE_HOSTPORT; do sleep 1; done"; then
#      echo "g-api did not start"
#      exit 1
#    fi
#fi

# launch the keystone and wait for it to answer before continuing
#if [[ "$ENABLED_SERVICES" =~ "key" ]]; then
#    screen_it key "cd $KEYSTONE_DIR && $KEYSTONE_DIR/bin/keystone --config-file $KEYSTONE_CONF -d"
#    echo "Waiting for keystone to start..."
#    if ! timeout $SERVICE_TIMEOUT sh -c "while ! wget -q -O- http://127.0.0.1:5000; do sleep 1; done"; then
#      echo "keystone did not start"
#      exit 1
#    fi
#fi
upstart_install key keystone $KEYSTONE_DIR

# launch the nova-api and wait for it to answer before continuing
upstart_install n-api nova-api $NOVA_DIR
#if [[ "$ENABLED_SERVICES" =~ "n-api" ]]; then
#    screen_it n-api "cd $NOVA_DIR && $NOVA_DIR/bin/nova-api"
#    echo "Waiting for nova-api to start..."
#    if ! timeout $SERVICE_TIMEOUT sh -c "while ! wget -q -O- http://127.0.0.1:8774; do sleep 1; done"; then
#      echo "nova-api did not start"
#      exit 1
#    fi
#fi

# Launching nova-compute should be as simple as running ``nova-compute`` but
# have to do a little more than that in our script.  Since we add the group
# ``libvirtd`` to our user in this script, when nova-compute is run it is
# within the context of our original shell (so our groups won't be updated).
# Use 'sg' to execute nova-compute as a member of the libvirtd group.

#screen_it n-cpu "cd $NOVA_DIR && sg libvirtd $NOVA_DIR/bin/nova-compute"
upstart_install n-cpu nova-compute $NOVA_DIR
#screen_it n-vol "cd $NOVA_DIR && $NOVA_DIR/bin/nova-volume"
upstart_install n-vol nova-volume $NOVA_DIR
#screen_it n-net "cd $NOVA_DIR && $NOVA_DIR/bin/nova-network"
upstart_install n-net nova-network $NOVA_DIR
#screen_it n-sch "cd $NOVA_DIR && $NOVA_DIR/bin/nova-scheduler"
upstart_install n-sch nova-scheduler $NOVA_DIR

#if [[ "$ENABLED_SERVICES" =~ "n-vnc" ]]; then
#    screen_it n-vnc "cd $NOVNC_DIR && ./utils/nova-wsproxy.py --flagfile $NOVA_DIR/bin/nova.conf --web . 6080"
#fi
upstart_install n-vnc nova-novnc $NOVNC_DIR
if [[ "$ENABLED_SERVICES" =~ "horizon" ]]; then
    #screen_it horizon "cd $HORIZON_DIR && sudo tail -f /var/log/apache2/error.log"
    #do nothing 
    echo 
fi

# Fin
# ===




# Using the cloud
# ===============

echo ""
echo ""
echo ""

# If you installed the horizon on this server, then you should be able
# to access the site using your browser.
if [[ "$ENABLED_SERVICES" =~ "horizon" ]]; then
    echo "horizon is now available at http://$HOST_IP/"
fi

# If keystone is present, you can point nova cli to this server
if [[ "$ENABLED_SERVICES" =~ "key" ]]; then
    echo "keystone is serving at http://$HOST_IP:5000/v2.0/"
    echo "examples on using novaclient command line is in exercise.sh"
    echo "the default users are: admin and demo"
    echo "the password: $ADMIN_PASSWORD"
fi

# indicate how long this took to run (bash maintained variable 'SECONDS')
echo "upstart.sh completed in $SECONDS seconds."

