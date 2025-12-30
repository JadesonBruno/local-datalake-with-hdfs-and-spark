#!/bin/bash

set -e # Exit on error

SPARK_WORKLOAD=$1
MAX_RETRIES=30
RETRY_DELAY=10

echo "========== DEBUG =========="
echo "SPARK_WORKLOAD: $SPARK_WORKLOAD"
echo "SPARK_HOME: '$SPARK_HOME'"
echo "HADOOP_HOME: '$HADOOP_HOME'"
echo "JAVA_HOME: '$JAVA_HOME'"
echo "=========================="

echo "SPARK_WORKLOAD: $SPARK_WORKLOAD"

/etc/init.d/ssh start

if [ "$SPARK_WORKLOAD" == "master" ];
then

  if [ -d "${HADOOP_HOME}/data/namenode" ] || [ -z "$(ls -A ${HADOOP_HOME}/data/namenode)" ]; then
    echo "Formatting the namenode..."
    hdfs namenode -format -force
    echo "✅ Namenode formatted."
  else
    echo "ℹ️ Namenode already formatted. Skipping format step."
  fi

  # Initializing the processes on the master
  echo "Starting daemons (namenode, secondarynamenode, resourcemanager)..."
  hdfs --daemon start namenode
  hdfs --daemon start secondarynamenode
  yarn --daemon start resourcemanager || echo "⚠️ Warning: ResourceManager priority error (non-critical)"

  # Wait until HDFS exits safe mode
  echo "Waiting for HDFS to exit safe mode (máximo $((MAX_RETRIES * RETRY_DELAY))s)......"
  RETRIES=0
  while [ $RETRIES -lt $MAX_RETRIES ]; do
    echo "DEBUG: Checking safe mode status..."
    hdfs dfsadmin -safemode get
    echo "DEBUG: Checking DataNodes..."
    hdfs dfsadmin -report | head -20
    
    if hdfs dfsadmin -safemode get 2>/dev/null | grep -q "Safe mode is OFF"; then
      echo "✅ HDFS is out of safe mode!"
      break
    fi
    echo "Attempt $((RETRIES + 1))/$MAX_RETRIES: HDFS is still in safe mode..."
    sleep $RETRY_DELAY
    RETRIES=$((RETRIES + 1))
  done

  if [ $RETRIES -eq $MAX_RETRIES ]; then
    echo "❌ ERROR: HDFS did not exit safe mode after $(($MAX_RETRIES * $RETRY_DELAY))s."
    exit 1
  fi

  # Create folder /data-lake-logs with limit of attempts
  echo "Creating /data-lake-logs directory in HDFS..."
  RETRIES=0
  while [ $RETRIES -lt $MAX_RETRIES ]; do
    if hdfs dfs -mkdir -p /data-lake-logs 2>/dev/null; then
      echo "✅ The folder /data-lake-logs has been created in HDFS!"
      break
    fi
    echo "Attempt $((RETRIES + 1))/$MAX_RETRIES: Failed to create /data-lake-logs in HDFS..."
    sleep $RETRY_DELAY
    RETRIES=$((RETRIES + 1))
  done

  if [ $RETRIES -eq $MAX_RETRIES ]; then
    echo "❌ ERROR: Could not create /data-lake-logs in HDFS after $(($MAX_RETRIES * $RETRY_DELAY))s."
    exit 1
  fi

  # Create folder ${SPARK_HOME}/data with limit of attempts
  echo "Creating ${SPARK_HOME}/data directory in HDFS..."
  RETRIES=0
  while [ $RETRIES -lt $MAX_RETRIES ]; do
    if hdfs dfs -mkdir -p ${SPARK_HOME}/data 2>/dev/null; then
      echo "✅ The folder ${SPARK_HOME}/data has been created in HDFS!"
      break
    fi
    echo "Attempt $((RETRIES + 1))/$MAX_RETRIES: Failed to create ${SPARK_HOME}/data in HDFS..."
    sleep $RETRY_DELAY
    RETRIES=$((RETRIES + 1))
  done
  
  if [ $RETRIES -eq $MAX_RETRIES ]; then
    echo "❌ ERROR: Could not create ${SPARK_HOME}/data in HDFS after $(($MAX_RETRIES * $RETRY_DELAY))s."
    exit 1
  fi

  # Copy the data to HDFS with error handling
  echo "Copying data from local to HDFS at ${SPARK_HOME}/data..."
  if ls ${SPARK_HOME}/data/* 1>/dev/null 2>&1; then
    if hdfs dfs -copyFromLocal ${SPARK_HOME}/data/* ${SPARK_HOME}/data 2>/dev/null; then
      echo "✅ Data copied successfully"
    else
      echo "⚠️ Warning: Failed to copy some data (may already exist)"
    fi
  else
    echo "ℹ️ No local data found (this is normal on first startup)"
  fi

  echo "Listing contents of ${SPARK_HOME}/data in HDFS:"
  hdfs dfs -ls ${SPARK_HOME}/data || echo "ℹ️ HDFS folder is empty"

  echo "✅ Master setup completed."


elif [ "$SPARK_WORKLOAD" == "worker" ];
then
  echo "Starting worker daemons (datanode, nodemanager)..."
  hdfs --daemon start datanode
  yarn --daemon start nodemanager || echo "⚠️ Warning: NodeManager priority error (non-critical)"
  echo "✅ Worker setup completed."


elif [ "$SPARK_WORKLOAD" == "history" ];
then
  echo "Waiting folder /data-lake-logs in HDFS (máximo $((MAX_RETRIES * RETRY_DELAY))s)..."
  RETRIES=0
  while [ $RETRIES -lt $MAX_RETRIES ]; do
    if hdfs dfs -test -d /data-lake-logs 2>/dev/null; then
      echo "✅ spark-logs folder exists in HDFS!"
      break
    fi
    echo "Attempt $((RETRIES + 1))/$MAX_RETRIES: Waiting /data-lake-logs..."
    sleep $RETRY_DELAY
    RETRIES=$((RETRIES + 1))
  done

  if [ $RETRIES -eq $MAX_RETRIES ]; then
    echo "❌ ERROR: /data-lake-logs does not exist in master after $(($MAX_RETRIES * $RETRY_DELAY))s."
    exit 1
  fi

  echo "Starting history server..."
  if start-history-server.sh; then
    echo "✅ History server started successfully."
  else
    echo "❌ ERROR: Failed to start history server."
    exit 1
  fi

else
  echo "❌ ERROR: ${SPARK_WORKLOAD} is not a valid option. Use 'master', 'worker', or 'history'."
  exit 1
fi

echo "========== ENTRYPOINT FINALIZADO COM SUCESSO =========="
tail -f /dev/null
