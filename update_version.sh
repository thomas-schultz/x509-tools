#!/bin/bash

version=`date "+%Y-%m-%d %H:%M:%S"`

sed -i "s/VERSION=".*"/VERSION='x509-tools $version';/g" ./x509-tool.sh && \
echo "updated to $version"
