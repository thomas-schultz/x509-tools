#!/bin/bash

function it {
	if [ $1 -eq 0 ]; then
		echo "ok $COUNT - $2" >> $OUT
	else
		echo "not ok $COUNT - $2" >> $OUT
	fi
	COUNT=$(( COUNT + 1 ))
}

function nit {
	if [ $1 -eq 0 ]; then
		it 1 $2
	else
		it 0 $2
	fi
}
