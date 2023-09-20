#!/usr/bin/ksh
#########################################################################
#									#
#	TITLE : 	systemmksysb_script_v1.ksh	        	#
#									#
#	AUTHOR :	Dirk Devoghel					#
#									#
#	SHELL :		Kornshell					#
#									#
#	DESCRIPTION :	Make a system backup either trough NFS or a pipe#
#			or locallly (+creation of a iso file + backup   #
#			to TSM						#
#		        TargetHost : Host on which to dump the mksysb   #
#		        TargetDir  : Directory on which to dump.        #
#		        XferType   : Way of storing : NFS or PIPE       #
#		        SaveOld    : TRUE/FALSE save old version        #
#		        NfsOptions : specify NFS options.               #
#		        MountPoint : NFS mountpoint                     #
#		        The defaults are :                              #
#		        TargetHost : $CWS                               #
#		        TargetDir  : /spdata/sys1/install/images        #
#		        XferType   : NFS                                #
#		        NfsOptions : bg,soft,rw,proto=tcp,bsy,nodev,nosuid #
#		        MountPoint : /mnt                               #
#		        SaveOld    : TRUE                               #
#		        BlockSize  : 1024                               #
#		        Compress   : TRUE                               #
#                       Endnotif   : FALSE                              #
#		        Eject      : TRUE                               #
#									#
#	KNOWN PROBLEMS : 						#
#									#
#	LOGS :  1.)systemmksysb_check_v1.X.log X=day of week            #
#									#
#	Y2K STATUS : READY						#
#									#
#	HISTORY : 1.)	30/12/1998 Dirk Devoghel.                      	#
#                 2.)   22/04/1999 Dirk Devoghel.                       #
#                 3.)   06/06/1999 Pieter Dubois                        #
#                       Added harmless alert + adapt with new sendalert.#
#                 4.)   15/12/2000 Dirk Devoghel.                       #
#		  5.)	24/01/2001 Nathalie Verlinden			#
#			Corrected Integer error				#
#		  6.)	30/01/2001 Nathalie Verlinden			#
#			Corrected MUTEX unlock error			#
#		  7.)   12/03/2001 Pierre-Yves Renard                   #
#			Added harmless alert when backup is OK          #
#		  8.)	22/05/2008 Benoit Godin				#
#			Added possibility to create a DVD iso file	#
#			containing the mksysb just created		#
#		  9.)   15/12/2010 Benoit Godin				#
#			Replaced "SENDALERT" with "logger" command for	#
#			usage with ITM v6				#
#		  91.)  wa for file '/dev/null 2>&1' created by cas_src #
#                                                                       #
#       RETURN CODES :50 BOOTSTRAP variable not defined                 #
#                     51 Error in Environment File                      #
#                     52 Error in mkszfile command                      #
#                     53 Error in mksysb command                        #
#                     54 Error in mkfifo command                        #
#                     55 Error in mount NFS                             #
#                     56 Error in rsh command                           #
#	              57 Unable to obtain lock				#
#		      58 Error in dd command				#
#		      59 Targetfile not correctly defined		#
#		      60 Argument not defined				#
#		      61 Error in mkcd command				#
#		      62 Error in dsmc command				#
#									#
#########################################################################

my_exit()
{
    #set -x
    ERR=$1
    if [ $XferType = "PIPE" ] ; then
       if ( ps -p $BG_PID ) ; then
          KPID=$(ps -ef|grep $BG_PID|grep "backbyname"|grep -v grep|awk '{print $2}')
          kill $KPID
          ERR=$DD_ERR
       fi
       [ -p $PIPE ] && rm $PIPE
       if [ $ERR -eq 0 ] 
       then
          $RSH $TargetHost rm -ef $TargetDir/$TargetFile.$$ < /dev/null  
       else
          $RSH $TargeHost rm -e $TargetDir/$TargetFile < /dev/null
          $RSH $TargetHost "[ -f $TargetDir/$TargetFile.$$ ] && mv -f $TargetDir/$TargetFile.$$ $TargetDir/$TargetFile " < /dev/null  
       fi
    elif [ $XferType = "NFS" ] ; then
       if [ $ERR -eq 0 ] 
       then
          rm -ef $MountPoint/$TargetFile.$$ 
       else
          rm -e $MountPoint/$TargetFile
          mv -f $MountPoint/$TargetFile.$$ $MountPoint/$TargetFile
       fi
       ( mount|grep "^$TargetHost $TargetDir $MountPoint " ) &&  umount -f $MountPoint
    elif [ $XferType = "LOCAL" ] ; then
       [ $OLDBLKSZ != "UNDEFINED" ] && chdev -l $(basename $TargetFile) -a block_size=$OLDBLKSZ
       if [ $ERR -eq 0 ] ; then
          [ $Eject = "TRUE" ] && tctl -f $TargetFile rewoffl
	  if [ $Endnotif = "TRUE" ]
           then
           	MSG="mksysb succeeded."
           	#$SENDALERT "$SCRIPT" "HARMLESS" "$HOST" "null" "$MSG" &
		logger -t "SMI_BACKUPFAIL" "HARMLESS" "for $SupTeam : $MSG"
          fi
       fi
    elif [ $XferType = "DVD" ] ; then
       for dir in mksysb cd_fs cd_images
       do
         if [ $(lsfs|grep -c -w /mkcd/$dir) = 1 ] ; then
            umount /mkcd/$dir >/dev/null 2>&1
            rmfs /mkcd/$dir
            rmdir /mkcd/$dir
         fi
       done
      [[ -d /mkcd ]] && rmdir /mkcd
      [[ -f "$ISOFileName" ]] && rm $ISOFileName
    fi
    if [ $ERR -eq 0 ] && [ -f $INIFILE ]
    then
      MSG="Last mksysb failed, this mksysb succeeded."
     # $SENDALERT "$SCRIPT" "HARMLESS" "$HOST" "null" "$MSG" &
	logger -t "SMI_BACKUPFAIL" "HARMLESS" "for $SupTeam : $MSG"
      rm -f $INIFILE
    elif [ $ERR -ne 0 ]
    then
      touch $INIFILE
    fi
    rm -f $HOSTENV 
    rm -f $SCRIPTENV 
    $MUTEX unlock $SCRIPT $$
    exec  >&-
    exec 1>&3
    echo $1
    exit $1
}

#########################################################################
#									#
# Definitions of Error variables                                        #
#									#
#########################################################################
BOOTSTRAP_ERR=50
ENVFILE_ERR=51
MKSZFILE_ERR=52
MKSYSB_ERR=53
MKFIFO_ERR=54
NFSMNT_ERR=55
RSHCMD_ERR=56
LOCK_ERR=57
DD_ERR=58
TAPE_ERR=59
ARG_ERR=60
DVD_ERR=61
TSM_ERR=62

#########################################################################
#									#
# Initialisations and checkings that have to be in any script that sends#
# messages to Tivoli.							#
#									#
#########################################################################

#
#Check if the BOOTSTRAP variable is set
#
if ! ( env | grep BOOTSTRAP >/dev/null )
then
   mail -s "BOOTSTRAP variable is not defined." root < /dev/null
   echo "$BOOTSTRAP_ERR" 
   exit $BOOTSTRAP_ERR
fi

#
#Set the basic environment variables
#
. $BOOTSTRAP

#
#Control WorkStation
#
CWS=$($ENVPRINT CWS.START CWS.STOP $ENVFILE)

#
#Kerberos rsh command
#
PSSP_RSH=$($ENVPRINT PSSP_RSH.START PSSP_RSH.STOP $ENVFILE)
RSH=$PSSP_RSH
[ -z "$PSSP_RSH" ] && RSH=/usr/bin/rsh


################# End Tivoli mandatory initialisations ##################


#########################################################################
#									#
# Script Specific initialisations					#
#									#
#########################################################################

#
#Name of the script : needed for tmpfile names
#
SCRIPT1=${0##*/}
SCRIPT=${SCRIPT1%.*}

#
#Date in hh:mm@dd/mm/yyy format.
#
DATEL=$(date +%H:%M@%d/%m/%Y)

#
#Logfile which gathers all information
#
LOGFILE=$SYSTEMLOG/$SCRIPT.$(date "+%u").log
#workaround for file '/dev/null 2>&1' created by cas_src
(ls -l /dev/null\ 2\>\&1 >/dev/null 2>&1) && (/usr/bin/rm /dev/null\ 2\>\&1) >/dev/null 2>&1
exec 3>&1
exec  > $LOGFILE
exec 2>&1

#Inifile : when exists, then last time script ran there was an error
INIFILE=$SYSTEMINI/$SCRIPT.ini

#
# Try to obtain a lock
#
$MUTEX lock $SCRIPT $$
if [ $? -ne 0 ]
then
   MSG="Mksysb script - Unable to obtain lock, script already running"
  # $SENDALERT "$SCRIPT" "WARNING" "$HOST" "null" "$MSG" &
   logger -t "SMI_BACKUPFAIL" "WARNING" "for $SupTeam : $MSG"
   printf "%20s%20s:%s\n" "$DATE" "WARNING" "$MSG"
   my_exit $LOCK_ERR
fi

#
#Basic check of the entries in the global environment file for the
#specific script: NEEDS an argument (name of script w/o .ksh)
#
. $SCRIPTENVCHECK $SCRIPT
RCENVCHK=$?
if [ $RCENVCHK -ne 0 ]
then
   MSG="Mksysb script - missing or wrong START/STOP statements in environment file"
  # $SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
    logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
   printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
   my_exit $ENVFILE_ERR
fi

#
#Take the environment for this script out of the global environment file,
#and put it into a temporary env file.
#
SCRIPTENV=$SYSTEMTMP/$SCRIPT.1.tmp
$ENVPRINT $SCRIPT.START $SCRIPT.STOP $ENVFILE > $SCRIPTENV

#
#ssh command (or other)
#
RCMD="$($ENVSELECT RCMD $SCRIPTENV)"
[ ! -z "$RCMD" ] && RSH=$RCMD

#
#For local running scripts
#Host specific environment file, taken out of script environment file
#
HOSTENV=$SYSTEMTMP/$SCRIPT.2.tmp
$ENVPRINT $HOST.START $HOST.STOP $SCRIPTENV > $HOSTENV


#
# TargetHost  System Wide Default
#
TargetHost_Default="$($ENVSELECT TargetHost_Default $SCRIPTENV)"
if [ -z "$TargetHost_Default" ] ; then
   if [ ! -z "$CWS" ] ; then
      TargetHost_Default=$CWS
   else
      TargetHost_Default=localhost
   fi 
fi
if [ -z "$TargetHost_Default" ] ; then
   MSG="Mksysb script - No TargetHost_Default specified (and CWS not defined)"
  # $SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
   logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
   printf "%20s%20s:%s\n" "$DATE" "WARNING" "$MSG"
fi

#
# TargetFile System Wide Default
#
TargetFile_Default="$($ENVSELECT TargetFile_Default $SCRIPTENV)"
[ -z "$TargetFile_Default" ] && TargetFile_Default="bos.obj.$HOST"

#
# TargetDir System Wide Default
#
TargetDir_Default="$($ENVSELECT TargetDir_Default $SCRIPTENV)"
[ -z "$TargetDir_Default" ] && TargetDir_Default="/spdata/sys1/install/images"

#
# XferType System Wide Default
#
XferType_Default="$($ENVSELECT XferType_Default $SCRIPTENV)"
[ -z "$XferType_Default" ] && XferType_Default=NFS
XferType_Default=$( echo $XferType_Default|tr '[a-z]' '[A-Z]' )

#
# NfsOptions System Wide Default
#
NfsOptions_Default="$($ENVSELECT NfsOptions_Default $SCRIPTENV)"
[ -z "$NfsOptions_Default" ] && NfsOptions_Default="bg,soft,rw,proto=tcp,bsy,nodev,nosuid"

#
# MountPoint System Wide Default
#
MountPoint_Default="$($ENVSELECT MountPoint_Default $SCRIPTENV)"
[ -z "$MountPoint_Default" ] && MountPoint_Default="/mnt"

#
# SaveOld    System Wide Default
#
SaveOld_Default="$($ENVSELECT SaveOld_Default $SCRIPTENV)"
[ -z "$SaveOld_Default" ] && SaveOld_Default="TRUE"
SaveOld_Default=$( echo $SaveOld_Default|tr '[a-z]' '[A-Z]' )

#
# Compress    System Wide Default
#
Compress_Default="$($ENVSELECT Compress_Default $SCRIPTENV)"
[ -z "$Compress_Default" ] && Compress_Default="TRUE"
Compress_Default=$( echo $Compress_Default|tr '[a-z]' '[A-Z]' )

#
# BlockSize    System Wide Default
#
integer BlockSize_Default BlockSize
BlockSize_Default="$($ENVSELECT BlockSize_Default $SCRIPTENV)"
[ -z "$BlockSize_Default" ] && BlockSize_Default="1024"

#
# Eject     System Wide Default
#
Eject_Default="$($ENVSELECT Eject_Default $SCRIPTENV)"
[ -z "$Eject_Default" ] && Eject_Default="TRUE"

#
# Endnotif  System Wide Default
#
Endnotif_Default="$($ENVSELECT Endnotif_Default $SCRIPTENV)"
[ -z "$Endnotif_Default" ] && Endnotif_Default="FALSE"

#
# DVDfs	   System Wide Default
#
DVDfs_Default="$($ENVSELECT DVDfs_Default $SCRIPTENV)"
# if DVDfs_Default is empty, then we will let the mkdvd create a fs

#
# ISOfs    System Wide Default
#
ISOfs_Default="$($ENVSELECT ISOfs_Default $SCRIPTENV)"
# same as for DVDfs_Default

#
# DVDvg System Wide Default
#
DVDvg="$($ENVSELECT DVDvg_Default $SCRIPTENV)"
[ -z "$DVDvg_Default" ] &&  DVDvg_Default=rootvg

#
# TSMServername System Wide Default
#
TSMServername_Default="$($ENVSELECT TSMServername_Default $SCRIPTENV)"

#
# ArchiveDesc   System Wide Default
#
ArchiveDesc_Default="$($ENVSELECT ArchiveDesc_Default $SCRIPTENV)"
[ -z "$ArchiveDesc_Default" ] && ArchiveDesc_Default=mksysb

#
# TargetHost 
#
TargetHost="$($ENVSELECT TargetHost $HOSTENV)"
[ -z "$TargetHost" ] && TargetHost=$TargetHost_Default

#
# TargetFile
#
TargetFile="$($ENVSELECT TargetFile $HOSTENV)"
[ -z "$TargetFile" ] && TargetFile=$TargetFile_Default

#
# XferType
#
XferType="$($ENVSELECT XferType $HOSTENV)"
[ -z "$XferType" ] && XferType=$XferType_Default
XferType=$( echo $XferType|tr '[a-z]' '[A-Z]' )
if [ $XferType != "NFS" ] && [ $XferType != "PIPE" ] && [ $XferType != "LOCAL" ] && [ $XferType != "DVD" ] ; then
   MSG="Mksysb script - Invalid XferType argument"
   #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
   logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
   printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
   my_exit $ARG_ERR
fi

#
# TargetDir
#
TargetDir="$($ENVSELECT TargetDir $HOSTENV)"
[ -z "$TargetDir" ] && [ $XferType != DVD ] && TargetDir=$TargetDir_Default

#
# NfsOptions
#
NfsOptions="$($ENVSELECT NfsOptions $HOSTENV)"
[ -z "$NfsOptions" ] && NfsOptions=$NfsOptions_Default

#
# MountPoint
#
MountPoint="$($ENVSELECT MountPoint $HOSTENV)"
[ -z "$MountPoint" ] && MountPoint=$MountPoint_Default

#
# SaveOld   
#
SaveOld="$($ENVSELECT SaveOld $HOSTENV)"
[ -z "$SaveOld" ] && SaveOld=$SaveOld_Default
SaveOld=$( echo $SaveOld|tr '[a-z]' '[A-Z]' )
if [ $SaveOld != "TRUE" ] && [ $SaveOld != "FALSE" ] ; then
   MSG="Mksysb script - Invalid SaveOld argument"
   #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
   logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
   printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
   my_exit $ARG_ERR
fi

#
# Compress  
#
Compress="$($ENVSELECT Compress $HOSTENV)"
[ -z "$Compress" ] && Compress=$Compress_Default
Compress=$( echo $Compress|tr '[a-z]' '[A-Z]' )
if [ $Compress != "TRUE" ] && [ $Compress != "FALSE" ] ; then
   MSG="Mksysb script - Invalid Compress argument"
   #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
   logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
   printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
   my_exit $ARG_ERR
fi

#
# BlockSize  
#
BlockSize="$($ENVSELECT BlockSize $HOSTENV)"
[ -z "$BlockSize" ] && BlockSize=$BlockSize_Default
if [ $(echo "$BlockSize - $BlockSize/512*512"|bc) -ne 0 ] ; then
   MSG="Mksysb script - Invalid BlockSize argument "
   #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
   logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
   printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
   my_exit $ARG_ERR
fi

# 
# Endnotif
#
Endnotif="$($ENVSELECT Endnotif $HOSTENV)"
[ -z "$Endnotif" ] && Endnotif=$Endnotif_Default

#
# Eject     
#
Eject="$($ENVSELECT Eject $HOSTENV)"
[ -z "$Eject" ] && Eject=$Eject_Default
Eject=$( echo $Eject|tr '[a-z]' '[A-Z]' )
if [ $Eject != "TRUE" ] && [ $Eject != "FALSE" ] ; then
   MSG="Mksysb script - Invalid Eject argument"
   #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
   logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
   printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
   my_exit $ARG_ERR
fi

#
# DVDfs
#
DVDfs="$($ENVSELECT DVDfs $HOSTENV)"
[ -z "DVDfs" ] && DVDfs=$DVDfs_Default

#
# ISOfs
#
ISOfs="$($ENVSELECT ISOfs $HOSTENV)"
[ -z "$ISOfs" ] && ISOfs=$ISOfs_Default

#
# DVDvg
#
DVDvg="$($ENVSELECT DVDvg $HOSTENV)"
[ -z "$DVDvg" ] && DVDvg=$DVDvg_Default

#
# TSMServername
#
TSMServername="$($ENVSELECT TSMServername $HOSTENV)"
[ -z "$TSMServername" ] && TSMServername=$TSMServername_Default

#
# ArchiveDesc
#
ArchiveDesc="$($ENVSELECT ArchiveDesc $HOSTENV)"
[ -z "$ArchiveDesc" ] && ArchiveDesc=$ArchiveDesc_Default

if ! ( mkszfile ) ; then
   MSG="Mksysb script - mkszfile failed"
   #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
   logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
   printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
   my_exit $MKSZFILE_ERR
fi

PIPE=/tmp/pipe.mksysb.$$
case $XferType in 
   PIPE) if ! ( mkfifo $PIPE ) ; then 
              MSG="Mksysb script - mkfifo failed"
              #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
	      logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
              printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
              my_exit $MKFIFO_ERR
         fi
         if [ $SaveOld = "FALSE" ] ; then
            if ! ( $RSH $TargetHost rm -ef $TargetDir/$TargetFile < /dev/null ) ; then
                 MSG="Mksysb script - RSH rm failed"
                 #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
                 logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
                 printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
                 my_exit $RSHCMD_ERR
            fi
         else
            if ! ( $RSH $TargetHost \
                 "if [ -f $TargetDir/$TargetFile ];then (mv -f $TargetDir/$TargetFile $TargetDir/$TargetFile.$$);else echo no old mksysb file;fi" < /dev/null ) ; then
                 MSG="Mksysb script - RSH mv failed"
                 #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
                 logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
                 printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
                 my_exit $RSHCMD_ERR
            fi
         fi
         mksysb -e $PIPE &
         BG_PID=$!
         ERR=$(dd if=$PIPE | $RSH $TargetHost "dd of=$TargetDir/$TargetFile  ; echo \$?")
         if [ $? -ne 0 ] || [ $ERR -ne 0 ] ; then
              MSG="Mksysb script - dd failed"
              #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
              logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
              printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
              my_exit $DD_ERR 
         fi
         wait $BG_PID
         if [ $? -ne 0 ] ; then  
              MSG="Mksysb script - mksysb failed"
              #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
              logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
              printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
              my_exit $MKSYSB_ERR 
         fi ;;
                   
   NFS) if ! ( mount -o $NfsOptions $TargetHost:$TargetDir $MountPoint ) ; then
             MSG="Mksysb script - NFS mount failed"
             #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
             logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
             printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
             my_exit $NFSMNT_ERR
        fi
        if [ $SaveOld = "FALSE" ] ; then
           rm -ef $MountPoint/$TargetFile
        else
           mv -f $MountPoint/$TargetFile $MountPoint/$TargetFile.$$
        fi
        if ! ( mksysb -e $MountPoint/$TargetFile ) ; then
             MSG="Mksysb script - mksysb failed"
             #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
	     logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
             printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
             my_exit $MKSYSB_ERR
        fi ;;
   LOCAL) if [ ! -c $TargetFile ] ; then
              MSG="$TargetFile is not a device special file"
              #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
	      logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
              printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
              my_exit $TAPE_ERR
          fi
          OLDBLKSZ="UNDEFINED"
          OLDBLKSZ=$(lsattr -El $(basename $TargetFile) -a block_size -F value)
          chdev -l $(basename $TargetFile) -a block_size=$BlockSize
          if [ $Compress = "FALSE" ] ; then
             if ! ( /usr/bin/mksysb -i -p -e $TargetFile ) ; then
               MSG="Mksysb script - mksysb failed"
               #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
               logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
               printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
               my_exit $MKSYSB_ERR
             fi
          else
             if ! ( /usr/bin/mksysb -i -e $TargetFile ) ; then
               MSG="Mksysb script - mksysb failed"
               #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
		logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
               printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
               my_exit $MKSYSB_ERR
             fi
          fi ;;
   DVD) FsOptions=""
        if [ ! -z "$TargetDir" ] ; then
           if [ ! -d $TargetDir ] ; then
              MSG="$TargetDir is not a directory"
              #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
              logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
              printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
              my_exit $ARG_ERR
           else
              FsOptions="$FsOptions -M $TargetDir"
           fi
        fi

        if [ ! -z "$DVDfs" ] ; then
           if [ ! -d $DVDfs ] ; then
              MSG="$DVDfs is not a directory"
              #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
	      logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
              printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
              my_exit $ARG_ERR
           else
              FsOptions="$FsOptions -C $DVDfs"
           fi
        fi

        if [ ! -z "$ISOfs" ] ; then
           if [ ! -d $ISOfs ] ; then
              MSG="$ISOfs is not a directory"
              #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
              logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
              printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
              my_exit $ARG_ERR
           else
              FsOptions="$FsOptions -I $ISOfs"
           fi
        fi

        if [ $(echo $TargetFile|grep -c "^/dev/cd.$") = 1 ] ; then
           CreateDVD=yes        
        else
           CreateDVD=no
        fi

        dsmcopt=""
        [ ! -z "$TSMServername" ] && dsmcopt="-se=$TSMServername"

        if [ $CreateDVD = no ] ; then
           if ! ( dsmc q se $dsmcopt >/dev/null 2>&1) ; then
              MSG="Unable to connect to TSM"
              #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
		logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
              printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
              my_exit $TSM_ERR
           fi

           /usr/sbin/mkcd -L -e $FsOptions -V $DVDvg -R -S&
           MkcdPid=$!
           wait $MkcdPid
           RC=$?
     
           if [ $RC != 0 ] ; then
              MSG="mkcd failed"
              #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
	      logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
              printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
              my_exit $DVD_ERR
           fi

           # Save the file to TSM
           if [ -z "$ISOfs" ] ; then
              ISOFileName=/mkcd/cd_images/cd_image_$MkcdPid
           else
              ISOFileName=$ISOfs/cd_image_$MkcdPid
           fi

           print "Archiving file $ISOFileName with desc $ArchiveDesc"
           if ( ! dsmc archive $ISOFileName $dsmcopt -desc="$ArchiveDesc" ) ; then
              MSG="TSM backup of ISO file failed"
              #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
	      logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
              printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
              my_exit $TSM_ERR
           fi
        else
           if ! (/usr/sbin/mkcd -L -d $TargetFile -e $FsOptions -V $DVDvg) ; then
              MSG="mkcd failed"
              #$SENDALERT "$SCRIPT" "CRITICAL" "$HOST" "null" "$MSG" &
              logger -t "SMI_BACKUPFAIL" "CRITICAL" "for $SupTeam : $MSG"
              printf "%20s%20s:%s\n" "$DATE" "CRITICAL" "$MSG"
              my_exit $DVD_ERR
           fi
        fi
        ;;
esac

my_exit 0

####################### End of Script ####################################
