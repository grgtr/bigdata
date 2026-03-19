#!/bin/bash

SPARK_VERSION="3.5.0"
HADOOP_VERSION="3"
SPARK_NODES="192.168.10.19 192.168.10.55 192.168.10.17 192.168.10.18"

install_spark() {
    echo "=== Installing Spark on NameNode ==="
    sudo -u hadoop ssh -T hadoop@192.168.10.19 << EOF
cd ~
wget -q https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz
tar -xzf spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz
mv spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION} spark
rm spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz
EOF
}

configure_spark() {
    echo "=== Configuring Spark ==="
    sudo -u hadoop ssh -T hadoop@192.168.10.19 << 'EOF'
cat > ~/spark/conf/spark-defaults.conf << 'CONF'
spark.master                     yarn
spark.submit.deployMode          client
spark.eventLog.enabled           true
spark.eventLog.dir               hdfs://192.168.10.19:9000/spark-logs
spark.history.fs.logDirectory    hdfs://192.168.10.19:9000/spark-logs
spark.yarn.historyServer.address 192.168.10.19:18080
spark.sql.warehouse.dir          hdfs://192.168.10.19:9000/user/hive/warehouse
spark.sql.catalogImplementation  hive
CONF

cat > ~/spark/conf/spark-env.sh << 'ENV'
export JAVA_HOME=$(readlink -f $(which java) | sed 's|/bin/java||')
export HADOOP_CONF_DIR=$HOME/hadoop/etc/hadoop
export YARN_CONF_DIR=$HOME/hadoop/etc/hadoop
export SPARK_HOME=$HOME/spark
export LD_LIBRARY_PATH=$HADOOP_HOME/lib/native:$LD_LIBRARY_PATH
ENV

chmod +x ~/spark/conf/spark-env.sh

cat >> ~/.bashrc << 'ENVBLOCK'
export SPARK_HOME=$HOME/spark
export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
ENVBLOCK

source ~/.bashrc

~/hadoop/bin/hdfs dfs -mkdir -p /spark-logs
EOF
}

copy_hive_jars() {
    echo "=== Copying Hive jars to Spark ==="
    sudo -u hadoop ssh -T hadoop@192.168.10.19 << 'EOF'
cp ~/apache-hive-4.0.0-alpha-2-bin/lib/hive-*.jar ~/spark/jars/ 2>/dev/null || true
cp ~/apache-hive-4.0.0-alpha-2-bin/lib/guava-*.jar ~/spark/jars/ 2>/dev/null || true
EOF
}

start_history_server() {
    echo "=== Starting Spark History Server ==="
    sudo -u hadoop ssh -T hadoop@192.168.10.19 << 'EOF'
~/spark/sbin/start-history-server.sh
EOF
}

verify_installation() {
    echo "=== Verifying Spark installation ==="
    sudo -u hadoop ssh -T hadoop@192.168.10.19 << 'EOF'
~/spark/bin/spark-shell --version
jps | grep HistoryServer
EOF
}

install_spark
configure_spark
copy_hive_jars
start_history_server
verify_installation

echo "Spark installation completed!"
echo "History Server: http://192.168.10.19:18080"
