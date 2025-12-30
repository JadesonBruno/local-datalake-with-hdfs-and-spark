# Using the official Python 3.12.12 image based on Debian Bookworm
FROM python:3.11-bullseye AS spark-base

# Install essential packages and OpenJDK 11
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    sudo \
    curl \
    vim \
    unzip \
    rsync \
    openjdk-11-jdk \
    build-essential \
    software-properties-common \
    ssh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set environment variables for Java
ENV SPARK_HOME=${SPARK_HOME:-"/opt/spark"}
ENV HADOOP_HOME=${HADOOP_HOME:-"/opt/hadoop"}
ENV JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"

# Create necessary directories
RUN mkdir -p ${HADOOP_HOME} && \
    mkdir -p ${SPARK_HOME}
WORKDIR ${SPARK_HOME}

# Download and extract Apache Spark 3.5.1 with Hadoop 3
RUN curl --retry 30 --retry-delay 60 \
     https://archive.apache.org/dist/spark/spark-3.5.1/spark-3.5.1-bin-hadoop3.tgz \
    -o spark-3.5.1-bin-hadoop3.tgz && \
    tar -xvzf spark-3.5.1-bin-hadoop3.tgz -C ${SPARK_HOME} --strip-components=1 && \
    rm -rf spark-3.5.1-bin-hadoop3.tgz

# Download and extract Apache Hadoop 3.4.0
RUN curl --retry 30 --retry-delay 60 \
    https://dlcdn.apache.org/hadoop/common/hadoop-3.4.0/hadoop-3.4.0.tar.gz \
    -o hadoop-3.4.0.tar.gz && \
    tar -xvzf hadoop-3.4.0.tar.gz -C ${HADOOP_HOME} --strip-components=1 && \
    rm -rf hadoop-3.4.0.tar.gz

# Preparing the PySpark environment
FROM spark-base AS pyspark

# Install Python dependencies
RUN pip3 install --upgrade pip
COPY requirements.txt .
RUN pip3 install -r requirements.txt

# Adding Spark, Hadoop and Java binaries to PATH
ENV PATH="${SPARK_HOME}/sbin:${SPARK_HOME}/bin:${PATH}"
ENV PATH="${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${PATH}"
ENV PATH="${PATH}:${JAVA_HOME}/bin"

# Set Spark and Hadoop related environment variables
ENV SPARK_MASTER="spark://master:7077"
ENV SPARK_MASTER_HOST="master"
ENV SPARK_MASTER_PORT="7077"
ENV PYSPARK_PYTHON="python3"
ENV HADOOP_CONF_DIR="${HADOOP_HOME}/etc/hadoop"

# Set LD_LIBRARY_PATH for Hadoop native libraries
ENV LD_LIBRARY_PATH="${HADOOP_HOME}/lib/native:${LD_LIBRARY_PATH}"

# Hadoop user configurations
ENV HDFS_NAMENODE_USER="root"
ENV HDFS_DATANODE_USER="root"
ENV HDFS_SECONDARYNAMENODE_USER="root"
ENV YARN_RESOURCEMANAGER_USER="root"
ENV YARN_NODEMANAGER_USER="root"

# Set JAVA_HOME in Hadoop environment configuration
RUN echo "export JAVA_HOME=${JAVA_HOME}" >> ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh

# Copy configuration files for Spark and Hadoop
COPY yarn/spark-defaults.conf "${SPARK_HOME}/conf/"
COPY yarn/*.xml "${HADOOP_HOME}/etc/hadoop/"

# Make Spark scripts executable
RUN chmod u+x ${SPARK_HOME}/sbin/* && \
    chmod u+x ${SPARK_HOME}/bin/*

# Set PYTHONPATH for PySpark
ENV PYTHONPATH="${SPARK_HOME}/python:${PYTHONPATH}"

# Setup SSH for passwordless access
RUN mkdir -p ~/.ssh && \
    ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa && \
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys && \
    chmod 600 ~/.ssh/authorized_keys && \
    chmod 700 ~/.ssh

# Copy SSH configuration file
COPY ssh/ssh_config /root/.ssh/config

# Entrypoint script
COPY entrypoint.sh .

# Set execute permission for entrypoint script
RUN chmod +x entrypoint.sh

# Expose SSH port
EXPOSE 22

# Define the entrypoint
ENTRYPOINT [ "./entrypoint.sh" ]
