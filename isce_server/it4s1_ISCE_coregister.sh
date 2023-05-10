#!/bin/bash
houm=/storage/brno2/home/laz048
if [ `hostname | cut -d '.' -f1`=='oven' ]; then
 OVEN=1; OVENDIR=/mnt/lazecky/temp
 else OVEN=0;
fi
source $houm/mount/S1/BASE/CZ/crop.in
source $houm/cz_s1/db_vars
export PROJECTIT4I=DD-13-5

#load it
export PATH=$PATH:/storage/brno2/home/laz048/sw/it4s1
source /home/laz048/sw/it4s1/it4s1_skirit_moduleload

#should be working on Sentineloshka ISCE server
#M=20160313
#S=20160301
#relorb=124
#IW=2
#DIR=/home/laz048/TEMP/tmp_isce/iw2


#Inputs are two dates of images of one rel.orbit to be coregistered together
M=$1
S=$2
relorb=$3
SWATH=$4

#Preliminary preparation
DIR=/home/laz048/TEMP/cz_s1/temp_coreg/$relorb'/'$M'_'$S
IT4DIR=$DIR
if [ $OVEN -eq 1 ]; then DIR=$OVENDIR/cz_s1/temp_coreg/$relorb'/'$M'_'$S; fi
if [ -d $DIR/$SWATH ]; then echo "Such directory exists already! I will delete it and do again!"; rm -r $DIR/$SWATH; fi
mkdir -p $DIR
cd $DIR
#Link the existing SRTM DEM files
#for x in `ls ~/mount/S1/BASE/DEM/SRTM*`; do ln -s $x; done
#Prepare the coregistration working file
cat << EOF > coreg_$M'_'$S'.xml'
<?xml version="1.0" encoding="UTF-8"?>
<topsApp>
<component name="topsinsar">
    <property name="Sensor name">SENTINEL1</property>
    <component name="master">
        <property name="output directory">$M</property>
    </component>
    <component name="slave">
        <property name="output directory">$S</property>
    </component>
    <property name="demFilename">SRTM1_DEM.wgs84</property>
</component>
</topsApp>
EOF

#First stage: preprocess those images
#prepare the working files:
for IMA in $M $S; do
 #Finding images for these days
 tmpoutfile=tmp_$IMA.txt
 tmpquery=tmp_query_$IMA
 #mysql -h $SENT_MYSQL_DB -u $SENT_MYSQL_USER --password=$SENT_MYSQL_PASS --database=$SENT_MYSQL_S1DB -e "SELECT DISTINCT abs_path FROM files WHERE rel_orb="$relorb" AND (name LIKE CONCAT('%',"$IMA",'%'))" > $IMA.sql 2>/dev/null
 #echo "SELECT DISTINCT abs_path FROM files WHERE rel_orb="$relorb" AND (name LIKE CONCAT('%',"$IMA",'%'));" > $tmpquery
 echo "SELECT DISTINCT abs_path FROM files WHERE rel_orb="$relorb" AND date(acq_date)='"$IMA"';" > $tmpquery
 it4s1_mysql.sh $tmpquery $tmpoutfile
 cp $tmpoutfile $IMA.list
 # tail -n+2 $IMA.sql > $IMA.list; rm $IMA.sql
 #tail -n+2 $tmpoutfile > $IMA.list;
 rm $tmpoutfile
 #have to remove duplicities..
 for DUP in `cat $IMA.list | rev | cut -d '/' -f1 | cut -c10- | rev | sort | uniq -d`; do
  echo "Identified duplicity for "$DUP". Removing."
  ls -t `grep $DUP $IMA.list` | tail -n +2 > sel.tmp.dup; 
  for TOREMOVE in `cat sel.tmp.dup | rev | cut -d '/' -f1 | cut -d '.' -f2 | rev`; do sed -i '/'$TOREMOVE'/d' $IMA.list; done
 done
 
 AorB=`head -n1 $IMA.list | rev | cut -d '/' -f1 | rev | cut -c 3`
 A='';for x in `cat $IMA.list`; do A=`echo $A"'"$x"'"`; done
 FILES=`echo $A | sed "s/''/','/g"`

 mkdir -p $DIR/pre/$IMA/$SWATH
 cat << EOF > $DIR/pre/$IMA/$SWATH/topsApp_preproc_$IMA'.xml'
<?xml version="1.0" encoding="UTF-8"?>
<topsApp>
<component name="topsinsar">
    <property name="Sensor name">SENTINEL1</property>
    <property name="swaths">[$SWATH]</property>
    <component name="master">
        <property name="safe">[$FILES]</property>
        <property name="output directory">$DIR/pre/$IMA/$SWATH</property>
        <property name="orbit directory">$houm/mount/S1/ORBITS/S1$AorB</property>
        <property name="auxiliary data directory">$houm/mount/S1/AUX</property>
        <property name="region of interest">[$lat1,$lat2,$lon1,$lon2]</property>
    </component>
  </component>
</topsApp>
EOF
done
#Preprocess them and perform the coregistration.

mkdir $DIR/$SWATH 2>/dev/null
#preprocessing an image pair
for IMA in $M $S; do
 #if master was already preprocessed, then link it
 #if [ $IMA == $M ] && [ -d $DIR/../$M/pre/$SWATH ]; then 
 #  echo "Linking previously processed image "$IMA
 #  ln -s $DIR/../$M/pre/$SWATH $DIR/$SWATH/$IMA
 #  cp $DIR/../$M/pre/$SWATH.xml $DIR/$SWATH/$IMA.xml
 # else
   cd $DIR/pre/$IMA/$SWATH
   echo "Preprocessing "$IMA""
   time topsApp.py topsApp_preproc_$IMA.xml --end='preprocess' >tops_preproc.log 2>tops_preproc.err
   #correct paths in xml files and move to more proper folder:
   echo $DIR/pre/$IMA/$SWATH | sed 's/\//\\\//g' > /tmp/t
   sed -i 's/'`cat /tmp/t`'/'$IMA'/g' $DIR/pre/$IMA/$SWATH/IW$SWATH.xml
   sed -i 's/\/IW'$SWATH'//g' $DIR/pre/$IMA/$SWATH/IW$SWATH.xml
   mv $DIR/pre/$IMA/$SWATH/IW$SWATH.xml $DIR/$SWATH/$IMA.xml
#downgrading to older version of isce (at IT4I)
if [ `grep -c azimuthwindowtype $DIR/$SWATH/$IMA.xml` -gt 0 ]; then
 for a in azimuthwindowcoefficient rangewindowcoefficient azimuthprocessingbandwidth rangeprocessingbandwidth rangewindowtype azimuthwindowtype; do
  xmlstarlet ed -L -d "productmanager_name/component/component/component/property[@name='$a']" $DIR/$SWATH/$IMA.xml
  #somehow slave.xml is not just a link but real file! perhaps python IO?
  #xmlstarlet ed -L -d "productmanager_name/component/component/component/property[@name='$a']" slave.xml
 done
fi

   mkdir $DIR/$SWATH/$IMA
   cd $DIR/pre/$IMA/$SWATH/IW$SWATH
   for B in `ls bur*slc.xml | rev | cut -c 5- | rev`; do
    gdal_translate -of ENVI -ot CFloat32 $B.vrt $B
    sed -i '/SourceProperties/d' $B.vrt
    sed -i '/xml version/d' $B.vrt
    xmlstarlet ed -L -u 'VRTDataset/VRTRasterBand/SimpleSource/SourceFilename' -v $IMA/$B $B.vrt
    sed -i '/DstRect/d' $B
    sed -i '/SrcRect/d' $B
    xmlstarlet ed -L -u 'imageFile/property[@name="file_name"]/value' -v $IMA/$B $B.xml
    mv $B* $DIR/$SWATH/$IMA/.
   done
  #fi
#I forgot why i have it here???
# if [ $IMA == $M ] && [ ! -d $DIR/../$M/pre/$SWATH ]; then 
#  #move preprocessed MASTER for later usage
#  #DEBUG - I have to rearrange it for the DB system location
#  mkdir -p $DIR/../$M/pre
#  cp -r $DIR/$SWATH/$IMA $DIR/../$M/pre/$SWATH
#  cp $DIR/$SWATH/$IMA.xml $DIR/../$M/pre/$SWATH.xml
# fi
done

 #perform coregistration at IT4I
 #first will prepare the script for it and this one will be run as qsub task
 #copying preprocessed data to it4i
ssh -o IdentitiesOnly=yes laz048@salomon.it4i.cz "mkdir -p $IT4DIR"
mv $DIR/coreg*xml $DIR/$SWATH/.
scp -o IdentitiesOnly=yes -r $DIR/$SWATH laz048@salomon.it4i.cz:$IT4DIR/.
 #for IMA in $M $S; do
 # ssh laz048@salomon.it4i.cz "mkdir -p $DIR/pre/$IMA; ln -s $DIR/$SWATH/$IMA $DIR/pre/$IMA/$SWATH";
 #done

 #script to be run at it4i for processing these data
cat << EOF > process_$M'_'$S.sh
source /home/laz048/IT4S1/bashrc
cd $IT4DIR/$SWATH
ln -s $M.xml master.xml
ln -s $S.xml slave.xml
for u in \`ls /home/laz048/DATA/.cz_s1/DEM/SRTM*\`; do ln -s \$u; done
 #correct the size of Slave to fit the master
it4s1_correct_size.sh $M $S
echo "Coregistering "$S" towards "$M":"
echo "Computing heights (and geocoding parameters)"
time topsApp.py --start='computeBaselines' --end='topo' coreg_$M'_'$S'.xml' >topsApp01.log 2>topsApp01.err
echo "Performing ESD correction"
time topsApp.py --start='subsetoverlaps' --end='esd' coreg_$M'_'$S'.xml' >topsApp02.log 2>topsApp02.err
echo "Resampling"
time topsApp.py --start='rangecoreg' --end='fineresamp' coreg_$M'_'$S'.xml' >topsApp03.log 2>topsApp03.err
if [ -d $IT4DIR/$SWATH/fine_coreg ]; then 
   it4s1_deramp.sh fine_coreg;
   echo 1 > $IT4DIR/$SWATH/finished;
  else
   echo 0 > $IT4DIR/$SWATH/finished;
fi
rm $IT4DIR/$SWATH/isce_processing
EOF

 #copy and run the script - sometimes it can work more than an hour -> qfree queue :-/
scp -o IdentitiesOnly=yes process_$M'_'$S.sh laz048@salomon.it4i.cz:$IT4DIR/$SWATH/.
echo "Starting coregistration process at it4i."
ssh -o IdentitiesOnly=yes laz048@salomon.it4i.cz "chmod 777 $IT4DIR/$SWATH/process_$M'_'$S.sh; qsub -q qfree -A $PROJECTIT4I $IT4DIR/$SWATH/process_$M'_'$S.sh"

echo "Cleaning a bit"
cd
rm -r $DIR

#Next step: move bursts to database and create IDs for them.
#I will solve it by cron checking every hour for newly coregistered files from IT4I
#echo "Now check file 'finished' in IT4I: " $DIR
