#!/bin/bash

echo "=== Verifying table in Hive ==="
sudo -u hadoop ssh -T hadoop@192.168.10.19 << 'EOF'
~/apache-hive-4.0.0-alpha-2-bin/bin/hive -e "
SHOW TABLES;
DESCRIBE FORMATTED sales_analytics;
SELECT * FROM sales_analytics ORDER BY sale_date, category;
"
EOF

echo "=== Checking HDFS partitions ==="
sudo -u hadoop ssh -T hadoop@192.168.10.19 << 'EOF'
~/hadoop/bin/hdfs dfs -ls -R /user/hive/warehouse/sales_analytics
EOF

echo "=== Checking YARN application logs ==="
sudo -u hadoop ssh -T hadoop@192.168.10.19 << 'EOF'
yarn application -list -appStates FINISHED | tail -5
EOF
