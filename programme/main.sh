#!/bin/bash

usage() { echo "Usage: $0 <number-of-cloud-instances> <instance-type>" 1>&2; exit 1; }

if [ $# -ne 2 ] ;
then
    usage
fi

instance_ids=""

. ./launchInstances.sh $1 $2
./cloudRender.sh $instance_ids #retrieved from launchInstances.sh
