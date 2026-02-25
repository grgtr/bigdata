#!/bin/bash

echo "=== Checking cluster processes ==="
echo "NameNode:"
sudo -u hadoop ssh -T hadoop@192.168.10.19 "jps | grep NameNode"

echo "Secondary NameNode:"
sudo -u hadoop jps | grep SecondaryNameNode

echo "DataNodes:"
for NODE in 192.168.10.17 192.168.10.18 192.168.10.19; do
    echo "  $NODE:"
    sudo -u hadoop ssh -T hadoop@$NODE "jps | grep DataNode"
done

echo ""
echo "=== HDFS Report ==="
sudo -u hadoop ssh -T hadoop@192.168.10.19 "~/hadoop/bin/hdfs dfsadmin -report | head -30"

echo ""
echo "=== Test HDFS operations ==="
sudo -u hadoop ssh -T hadoop@192.168.10.19 << 'INNER'
echo "test" > /tmp/verify.txt
~/hadoop/bin/hdfs dfs -mkdir -p /verify
~/hadoop/bin/hdfs dfs -put -f /tmp/verify.txt /verify/
~/hadoop/bin/hdfs dfs -cat /verify/verify.txt
echo "✓ HDFS read/write OK"
INNER

echo ""
echo "=== Web UI ==="
echo "NameNode: http://192.168.10.19:9870"
echo "Secondary NameNode: http://192.168.10.55:9868"
