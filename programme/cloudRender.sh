#!/bin/bash

usage() { echo "Usage: $0 <cloud-instance-id-1> <cloud-instance-id-2> [<cloud-instance-id-3> ...]" 1>&2; exit 1; }

if [ $# -lt 2 ] ;
then
    usage
fi

INSTANCE_IDS=$@

. ./settings

mkdir -p $LOG_DIR

# Task 4 & 5: Run povray on given instances and measure time
START=$(date +%s.%N)

echo "Assume all instances have the same type and get cpu information of instance 1 ($1)"
host=$(aws ec2 describe-instances --instance-ids $1 --output text --query 'Reservations[*].Instances[*].PublicIpAddress')
cpu_per_instance=$(ssh -oStrictHostKeyChecking=no -i $KEY_FILE $EC2_USER@$host "grep -c ^processor /proc/cpuinfo")
echo "Cpu per instance: $cpu_per_instance"

# Some code from homework 2
# Read .ini file to get frame numbers
while read line
do
    if [[ $line == Initial_Frame* ]] || [[ $line == Final_Frame* ]] ;
    then
	equal_pos=`expr index $line =`
	length=`expr length $line`
	frame_number=${line:equal_pos:length}
	
	if [[ $line == Initial_Frame* ]] ;
	then
	    INITIAL_FRAME=$frame_number
	else
	    FINAL_FRAME=$frame_number
	fi
    fi
done < ${INPUT_DIR}/scherk.ini

# M = number of frames
M=$((FINAL_FRAME - INITIAL_FRAME + 1))
echo "$M frames will be rendered in parallel"

# gm instance (just the last instance)
gm_instance_id=$(echo $INSTANCE_IDS | cut -d" " -f$#)
gm_instance_internal_ip=$(aws ec2 describe-instances --instance-ids $gm_instance_id --output text --query 'Reservations[*].Instances[*].PrivateIpAddress')

# Render images on instances
id=0
for instance_id in $INSTANCE_IDS;
do
    id=$((id+1))

    SUBSET_START_FRAME=$(python -c "print int(float($M)/$# * ($id-1))+1")
    SUBSET_END_FRAME=$(python -c "print int(float($M)/$# * $id)")    
    echo "$instance_id renders frames $SUBSET_START_FRAME - $SUBSET_END_FRAME"
    
    frames=$(echo $SUBSET_END_FRAME - $SUBSET_START_FRAME + 1 | bc)

    host=$(aws ec2 describe-instances --instance-ids $instance_id --output text --query 'Reservations[*].Instances[*].PublicIpAddress')

    {
    ssh -oStrictHostKeyChecking=no -i $KEY_FILE $EC2_USER@$host <<EOF
    for i in \$(seq 1 $cpu_per_instance); do
	start_frame=\$(python -c "print int(float($frames)/$cpu_per_instance * (\$i-1)) + $SUBSET_START_FRAME")
        end_frame=\$(python -c "print int(float($frames)/$cpu_per_instance * \$i) - 1 + $SUBSET_START_FRAME")
        ~/bin/povray ~/inputdata/scherk.ini +I ~/inputdata/scherk.pov +Oscherk.png +FN +W1024 +H768 +SF\$start_frame +EF\$end_frame &
    done
    wait #for povray

    if [ $gm_instance_id != $instance_id ] ; 
    then
        echo "Copy images from instance $instance_id to gm instance $gm_instance_id"
        scp -oStrictHostKeyChecking=no scherk*.png $EC2_USER@$gm_instance_internal_ip:~
    fi
EOF
    echo "Rendered images on instance $instance_id"
    } 1>> "$LOG_DIR/$instance_id.out" 2>> "$LOG_DIR/$instance_id.err" &
done

# Wait until rendering completed
wait
echo "Rendering on instances completed"

# Create gif
echo "Create gif with instance $gm_instance_id"
host=$(aws ec2 describe-instances --instance-ids $gm_instance_id --output text --query 'Reservations[*].Instances[*].PublicIpAddress')
ssh -oStrictHostKeyChecking=no -i $KEY_FILE $EC2_USER@$host "~/bin/gm convert -loop 0 -delay 0 ~/*.png scherk.gif"
echo "Created gif with instance $gm_instance_id"

# Copy gif to local host
echo "Copy gif to localhost (current directory)"
scp -oStrictHostKeyChecking=no -i $KEY_FILE $EC2_USER@$host:~/scherk.gif ./
echo "Copied gif to localhost (current directory)"

END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc | awk '{printf "%f", $0}')
echo "Execution time ($# instances): $TIME seconds"

# Terminate instances
echo "Terminate instances"
START=$(date +%s.%N)
aws ec2 terminate-instances --instance-ids $INSTANCE_IDS
aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc | awk '{printf "%f", $0}')
echo "Termination time ($# instances): $TIME seconds"
