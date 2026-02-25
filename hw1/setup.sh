#!/bin/bash

NAMENODE="192.168.10.19"
DATANODES="192.168.10.17 192.168.10.18 192.168.10.19"
REMOTE_NODES="$NAMENODE 192.168.10.17 192.168.10.18"
ALL_NODES="192.168.10.55 $REMOTE_NODES"
HADOOP_USER="hadoop"
UBUNTU_PASS=""

create_user_local() {
    echo "=== Creating user locally on jn ==="
    echo "$UBUNTU_PASS" | sudo -S useradd -m -s /bin/bash $HADOOP_USER 2>/dev/null || true
}

create_user_remote() {
    for NODE in $REMOTE_NODES; do
        echo "=== Creating user on $NODE ==="
        sshpass -p "$UBUNTU_PASS" ssh -o StrictHostKeyChecking=no ubuntu@$NODE \
            "echo '$UBUNTU_PASS' | sudo -S useradd -m -s /bin/bash $HADOOP_USER 2>/dev/null || true"
    done
}

setup_ssh_local() {
    echo "=== Generating SSH key locally ==="
    echo "$UBUNTU_PASS" | sudo -S -u $HADOOP_USER ssh-keygen -t ed25519 -f /home/$HADOOP_USER/.ssh/id_ed25519 -N '' -q || true
    
    PUBKEY=$(sudo cat /home/$HADOOP_USER/.ssh/id_ed25519.pub)
    PRIVKEY=$(sudo cat /home/$HADOOP_USER/.ssh/id_ed25519)
    
    echo "=== Setting up local SSH ==="
    echo "$UBUNTU_PASS" | sudo -S bash -c "
        mkdir -p /home/$HADOOP_USER/.ssh
        echo '$PUBKEY' > /home/$HADOOP_USER/.ssh/authorized_keys
        chmod 700 /home/$HADOOP_USER/.ssh
        chmod 600 /home/$HADOOP_USER/.ssh/authorized_keys
        chown -R $HADOOP_USER:$HADOOP_USER /home/$HADOOP_USER/.ssh
    "
}

setup_ssh_remote() {
    PUBKEY=$(sudo cat /home/$HADOOP_USER/.ssh/id_ed25519.pub)
    PRIVKEY=$(sudo cat /home/$HADOOP_USER/.ssh/id_ed25519)
    
    for NODE in $REMOTE_NODES; do
        echo "=== Setting up SSH on $NODE ==="
        sshpass -p "$UBUNTU_PASS" ssh ubuntu@$NODE "echo '$UBUNTU_PASS' | sudo -S bash -c '
            mkdir -p /home/$HADOOP_USER/.ssh
            echo \"$PUBKEY\" > /home/$HADOOP_USER/.ssh/authorized_keys
            chmod 700 /home/$HADOOP_USER/.ssh
            chmod 600 /home/$HADOOP_USER/.ssh/authorized_keys
            chown -R $HADOOP_USER:$HADOOP_USER /home/$HADOOP_USER/.ssh
        '"
    done
    
    for NODE in $REMOTE_NODES; do
        echo "=== Copying private key to $NODE ==="
        sshpass -p "$UBUNTU_PASS" ssh ubuntu@$NODE "echo '$UBUNTU_PASS' | sudo -S -u $HADOOP_USER bash -c \"
            cat > ~/.ssh/id_ed25519 << 'KEY'
$PRIVKEY
KEY
            chmod 600 ~/.ssh/id_ed25519
            ssh-keyscan -H $ALL_NODES 2>/dev/null > ~/.ssh/known_hosts
        \""
    done
    
    echo "=== Setting up known_hosts locally ==="
    echo "$UBUNTU_PASS" | sudo -S -u $HADOOP_USER bash -c "ssh-keyscan -H $ALL_NODES 2>/dev/null > /home/$HADOOP_USER/.ssh/known_hosts"
}

install_java() {
    echo "=== Installing Java locally ==="
    echo "$UBUNTU_PASS" | sudo -S apt-get update
    echo "$UBUNTU_PASS" | sudo -S apt-get install -y openjdk-8-jdk sshpass
    
    for NODE in $REMOTE_NODES; do
        echo "=== Installing Java on $NODE ==="
        sshpass -p "$UBUNTU_PASS" ssh ubuntu@$NODE \
            "echo '$UBUNTU_PASS' | sudo -S apt-get update && echo '$UBUNTU_PASS' | sudo -S apt-get install -y openjdk-8-jdk"
    done
}

install_hadoop() {
    echo "=== Downloading Hadoop locally ==="
    echo "$UBUNTU_PASS" | sudo -S -u $HADOOP_USER bash << 'EOF'
cd ~
wget -q https://downloads.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz
tar -xzf hadoop-3.3.6.tar.gz
mv hadoop-3.3.6 hadoop
rm hadoop-3.3.6.tar.gz
EOF

    for NODE in $REMOTE_NODES; do
        echo "=== Copying Hadoop to $NODE ==="
        sudo -u $HADOOP_USER scp -r /home/$HADOOP_USER/hadoop $HADOOP_USER@$NODE:~/
    done
}

configure_env() {
    echo "=== Configuring environment locally ==="
    echo "$UBUNTU_PASS" | sudo -S -u $HADOOP_USER bash << 'EOF'
JAVA_PATH=$(readlink -f $(which java) | sed 's|/bin/java||')

cat >> ~/.bashrc << ENVBLOCK
export JAVA_HOME=$JAVA_PATH
export HADOOP_HOME=\$HOME/hadoop
export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin
ENVBLOCK

sed -i "s|# export JAVA_HOME=.*|export JAVA_HOME=$JAVA_PATH|" ~/hadoop/etc/hadoop/hadoop-env.sh
EOF

    for NODE in $REMOTE_NODES; do
        echo "=== Configuring environment on $NODE ==="
        sudo -u $HADOOP_USER ssh -T $HADOOP_USER@$NODE << 'EOF'
JAVA_PATH=$(readlink -f $(which java) | sed 's|/bin/java||')

cat >> ~/.bashrc << ENVBLOCK
export JAVA_HOME=$JAVA_PATH
export HADOOP_HOME=$HOME/hadoop
export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
ENVBLOCK

sed -i "s|# export JAVA_HOME=.*|export JAVA_HOME=$JAVA_PATH|" ~/hadoop/etc/hadoop/hadoop-env.sh
EOF
    done
}

configure_hadoop() {
    for NODE in $ALL_NODES; do
        echo "=== Configuring Hadoop on $NODE ==="
        if [ "$NODE" == "192.168.10.55" ]; then
            sudo -u $HADOOP_USER bash << 'EOF'
mkdir -p ~/hadoop_data/namenode ~/hadoop_data/datanode ~/hadoop_data/namesecondary

cat > ~/hadoop/etc/hadoop/core-site.xml << 'XML'
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://192.168.10.19:9000</value>
    </property>
</configuration>
XML

cat > ~/hadoop/etc/hadoop/hdfs-site.xml << 'XML'
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>3</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>file:///home/hadoop/hadoop_data/namenode</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>file:///home/hadoop/hadoop_data/datanode</value>
    </property>
    <property>
        <name>dfs.namenode.checkpoint.dir</name>
        <value>file:///home/hadoop/hadoop_data/namesecondary</value>
    </property>
    <property>
        <name>dfs.namenode.secondary.http-address</name>
        <value>192.168.10.55:9868</value>
    </property>
</configuration>
XML

cat > ~/hadoop/etc/hadoop/workers << 'WORKERS'
192.168.10.17
192.168.10.18
192.168.10.19
WORKERS
EOF
        else
            sudo -u $HADOOP_USER ssh -T $HADOOP_USER@$NODE << 'EOF'
mkdir -p ~/hadoop_data/namenode ~/hadoop_data/datanode ~/hadoop_data/namesecondary

cat > ~/hadoop/etc/hadoop/core-site.xml << 'XML'
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://192.168.10.19:9000</value>
    </property>
</configuration>
XML

cat > ~/hadoop/etc/hadoop/hdfs-site.xml << 'XML'
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>3</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>file:///home/hadoop/hadoop_data/namenode</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>file:///home/hadoop/hadoop_data/datanode</value>
    </property>
    <property>
        <name>dfs.namenode.checkpoint.dir</name>
        <value>file:///home/hadoop/hadoop_data/namesecondary</value>
    </property>
    <property>
        <name>dfs.namenode.secondary.http-address</name>
        <value>192.168.10.55:9868</value>
    </property>
</configuration>
XML

cat > ~/hadoop/etc/hadoop/workers << 'WORKERS'
192.168.10.17
192.168.10.18
192.168.10.19
WORKERS
EOF
        fi
    done
}

update_hosts() {
    HOSTS_BLOCK="192.168.10.19 nn
192.168.10.55 snn
192.168.10.17 dn00
192.168.10.18 dn01"

    echo "=== Updating hosts locally ==="
    echo "$HOSTS_BLOCK" | sudo tee -a /etc/hosts

    for NODE in $REMOTE_NODES; do
        echo "=== Updating hosts on $NODE ==="
        sshpass -p "$UBUNTU_PASS" ssh ubuntu@$NODE \
            "echo '$UBUNTU_PASS' | sudo -S bash -c \"echo '$HOSTS_BLOCK' >> /etc/hosts\""
    done
}

start_cluster() {
    echo "=== Formatting NameNode ==="
    ssh $HADOOP_USER@$NAMENODE "~/hadoop/bin/hdfs namenode -format -force"
    
    echo "=== Starting HDFS ==="
    ssh $HADOOP_USER@$NAMENODE "~/hadoop/sbin/start-dfs.sh"
}

verify() {
    sleep 10
    echo "=== Checking processes ==="
    for NODE in $ALL_NODES; do
        echo "=== $NODE ==="
        if [ "$NODE" == "192.168.10.55" ]; then
            sudo -u $HADOOP_USER jps
        else
            ssh $HADOOP_USER@$NODE "jps"
        fi
    done
    
    echo "=== HDFS Report ==="
    ssh $HADOOP_USER@$NAMENODE "~/hadoop/bin/hdfs dfsadmin -report"
}

create_user_local
create_user_remote
setup_ssh_local
setup_ssh_remote
install_java
install_hadoop
configure_env
configure_hadoop
update_hosts
start_cluster
verify
