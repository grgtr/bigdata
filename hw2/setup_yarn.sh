#!/bin/bash


HADOOP_HOME=/home/hadoop/hadoop
NAMENODE="nn"                        # hostname or IP of NameNode (192.168.10.19)
DATANODES=("dn00" "dn01")            # hostnames or IPs of DataNodes (17,18)
# NAMENODE="192.168.10.19"
# DATANODES=("192.168.10.17" "192.168.10.18")

ALL_NODES=("$NAMENODE" "${DATANODES[@]}")
HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"

# ============================================
# Check that the script is running on the NameNode
# ============================================
if [[ $(hostname) != "$NAMENODE" && $(hostname -I | grep -q "$NAMENODE") -ne 0 ]]; then
    echo "Error: script must be run on the NameNode ($NAMENODE)"
    exit 1
fi


echo "Creating configuration files..."

# mapred-site.xml
cat > "$HADOOP_CONF_DIR/mapred-site.xml" << 'EOF'
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
    <property>
        <name>mapreduce.application.classpath</name>
        <value>$HADOOP_HOME/share/hadoop/mapreduce/*:$HADOOP_HOME/share/hadoop/mapreduce/lib/*</value>
    </property>
</configuration>
EOF

# yarn-site.xml
cat > "$HADOOP_CONF_DIR/yarn-site.xml" << 'EOF'
<?xml version="1.0"?>
<configuration>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.nodemanager.env-whitelist</name>
        <value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_HOME,PATH,LANG,TZ,HADOOP_MAPRED_HOME</value>
    </property>
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>nn</value>   <!-- Replace with IP 192.168.10.19 if hostnames are not resolvable -->
    </property>
</configuration>
EOF

# workers (list of nodes for NodeManager)
cat > "$HADOOP_CONF_DIR/workers" << 'EOF'
192.168.10.19
192.168.10.17
192.168.10.18
EOF

echo "Configuration created locally."

for node in "${DATANODES[@]}"; do
    echo "Copying to $node..."
    scp "$HADOOP_CONF_DIR/mapred-site.xml" \
        "$HADOOP_CONF_DIR/yarn-site.xml" \
        "$HADOOP_CONF_DIR/workers" \
        "$node:$HADOOP_CONF_DIR/"
    if [ $? -ne 0 ]; then
        echo "Error copying to $node. Check SSH access."
        exit 1
    fi
done

echo "Stopping current YARN services (if any)..."
"$HADOOP_HOME/sbin/stop-yarn.sh" 2>/dev/null
sleep 2

echo "Starting YARN..."
"$HADOOP_HOME/sbin/start-yarn.sh"
if [ $? -ne 0 ]; then
    echo "Error starting YARN."
    exit 1
fi

echo "Starting HistoryServer..."
"$HADOOP_HOME/bin/mapred" --daemon start historyserver
sleep 2

verify() {
    echo "========================================"
    echo "Checking running services"
    echo "========================================"

    # NameNode
    echo "--- NameNode ($NAMENODE) ---"
    ssh "$NAMENODE" "jps | grep -E 'NameNode|DataNode|SecondaryNameNode|ResourceManager|NodeManager|JobHistoryServer'"

    # DataNodes
    for node in "${DATANODES[@]}"; do
        echo "--- DataNode $node ---"
        ssh "$node" "jps | grep -E 'DataNode|NodeManager'"
    done

    echo "========================================"
}

# Run verification
verify

echo "YARN deployment completed."
