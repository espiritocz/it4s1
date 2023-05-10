#!/bin/bash

#(c) 2018 Milan Lazecky, IT4Innovations
# Should be run in STAMPS WORKDIR
# This script will create mean amplitude and DA files
# TODO: include mean spatial coherence

if [ ! -e selpsc.in ]; then
 echo "File selpsc.in wasn't found. Are you in the STAMPS work directory?"
 pwd
 exit
fi

# preparation
echo 1 > temp_patch
cat width.txt >> temp_patch
echo 1 >> temp_patch
cat len.txt >> temp_patch
echo 1 > temp_selpsc
tail -n +2 selpsc.in >> temp_selpsc

# processing and preview
echo "Creating full mean_amp.flt and da.flt"
it4s1_mean_da temp_selpsc temp_patch da.flt mean_amp.flt
# correct by sqrting (STAMPS-based DA is squared)
octave-cli -q --eval="addpath('"$MATLABDIR"');lines="`cat len.txt`";a=freadbk('da.flt',lines,'float32');da=sqrt(a);fwritebk(da,'da.flt','float32')"
#no convert after salomon update
#cpxfiddle -w `cat width.txt` -M5/1 -o sunraster -c gray -q normal -f r4 -r 0,255 mean_amp.flt 2>/dev/null | convert - mean.png
#cpxfiddle -w `cat width.txt` -M5/1 -o sunraster -c jet -q normal -f r4 -r 0.35,1 da.flt 2>/dev/null | convert - da.png
cpxfiddle -w `cat width.txt` -M5/1 -o sunraster -c gray -q normal -f r4 -r 0,255 mean_amp.flt > mean.ras 2>/dev/null
cpxfiddle -w `cat width.txt` -M5/1 -o sunraster -c jet -q normal -f r4 -r 0.35,1 da.flt > da.ras 2>/dev/null

# cleaning
rm temp_patch temp_selpsc
