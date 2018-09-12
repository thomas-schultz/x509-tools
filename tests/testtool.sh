#!/bin/bash

GOOD=0
FAIL=0
COUNT=0

function it {
        COUNT=$(( COUNT + 1 ))
        if [ $1 -eq 0 ]; then
                echo "ok $COUNT - $2" >> $OUT
                GOOD=$(( GOOD + 1 ))
        else
                echo "not ok $COUNT - $2" >> $OUT
                FAIL=$(( FAIL + 1 ))
        fi
}

function nit {
        if [ $1 -eq 0 ]; then
                it 1 $2
        else
                it 0 $2
        fi
}
