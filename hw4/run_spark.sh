#!/bin/bash

echo "=== Uploading Spark job to NameNode ==="
scp spark_job.py hadoop@192.168.10.19:~/

echo "=== Running Spark job ==="
sudo -u hadoop ssh -T hadoop@192.168.10.19 << 'EOF'
~/spark/bin/spark-submit \
    --master yarn \
    --deploy-mode client \
    --num-executors 3 \
    --executor-memory 1G \
    --executor-cores 1 \
    --driver-memory 1G \
    ~/spark_job.py
EOF

echo "=== Job completed ==="
