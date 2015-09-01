#! /bin/bash
curdir=`pwd`
cd $JULIAHOME
git apply $1 $curdir/snoop.patch
make
