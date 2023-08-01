#!/bin/bash

cd "${BASH_SOURCE%/*}" || exit
find . -type d -exec rm -rf {} \; 2>/dev/null
rm -f test.t
