#!/bin/bash

# Конфигурация
HIVE_JDBC="jdbc:hive2://nn:5433"
HIVE_USER="hadoop"
HDFS_DATA_DIR="/user/hadoop/sales_data"
TABLE_NAME="sales"

if [ -z "$1" ]; then
    echo "Usage: $0 <sale_date>"
    exit 1
fi
SALE_DATE="$1"
DATA_FILE="$HDFS_DATA_DIR/data_$SALE_DATE.csv"

hdfs dfs -test -e "$DATA_FILE"
if [ $? -ne 0 ]; then
    echo "Error: File $DATA_FILE not found in HDFS"
    exit 2
fi

beeline -u "$HIVE_JDBC" -n "$HIVE_USER" -e "
    LOAD DATA INPATH '$DATA_FILE' INTO TABLE $TABLE_NAME PARTITION (sale_date='$SALE_DATE');
"


if [ $? -eq 0 ]; then
    echo "Data loaded successfully for date $SALE_DATE"
      hdfs dfs -mv "$DATA_FILE" "$HDFS_DATA_DIR/archive/data_$SALE_DATE.csv" 2>/dev/null
else
    echo "Error loading data"
    exit 3
fi
