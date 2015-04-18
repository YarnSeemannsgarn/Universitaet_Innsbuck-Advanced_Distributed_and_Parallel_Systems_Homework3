#!/bin/bash

usage() { echo "Usage: $0 <number-of-cloud-instances> <instance-type>" 1>&2; exit 1; }

if [ $# -ne 2 ] ;
then
    usage
fi

NUM_INSTANCES=$1
INSTANCE_TYPE=$2

. ./settings

# Task 3 & 5: Start given number of instances and measure time
START=$(date +%s.%N)

echo "Launch $1 ec2 instances with image id $IMAGE_ID"
instance_ids=$(aws ec2 run-instances --image-id $IMAGE_ID --count $NUM_INSTANCES --instance-type $INSTANCE_TYPE --associate-public-ip-address --key-name $KEY_NAME --security-group-ids $SECURITY_GROUP_ID --output text --query 'Instances[*].InstanceId')
echo "Launched instances with instance ids $instance_ids"

echo "Wait until instances are running"
aws ec2 wait instance-running --instance-ids $instance_ids
echo "Instances are running"

for instance_id in $instance_ids;
do
    echo "SSH to instance $instance_id until SSH works"
    host=$(aws ec2 describe-instances --instance-ids $instance_id --output text --query 'Reservations[*].Instances[*].PublicIpAddress')
    ssh -oStrictHostKeyChecking=no -i $KEY_FILE $EC2_USER@$host exit
    while [ $? -ne 0 ] ; 
    do
	sleep 1
	ssh -oStrictHostKeyChecking=no -i $KEY_FILE $EC2_USER@$host exit    
    done
    echo "SSH finished"

    echo "Copy povray files and ssh key to instance $instance_id"
    scp -oStrictHostKeyChecking=no -i $KEY_FILE -r $BIN_DIR $INPUT_DIR $EC2_USER@$host:~
    scp -oStrictHostKeyChecking=no -i $KEY_FILE $KEY_FILE $EC2_USER@$host:~/.ssh/id_rsa
    echo "Copied povray files and ssh key to instance $instance_id"
done

END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc | awk '{printf "%f", $0}')
echo "Launching time ($NUM_INSTANCES instances): $TIME seconds"

export instance_ids
