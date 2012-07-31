#!/bin/bash
# version 1.1
# By Vaughn Anderson
#
# Save the last location for a file playing, and then resume if it's been played before
# NOTES: The reason "title" is used for the resume function is that 
# the input file can change after VLC opens, and then the resume log is inaccurate.
# There doesn't seem to be any way through unix sockets to get the file name, 
# if there were, this would be the prefered method
# Also, since the title fluctuates between the actual title of the media played
# and some kind of empty title (can't figure out what it is) silly error checking in 
# a loop has to be done to ensure that VLC has loaded the file fully
# 
# Finally, when VLC has closed sometimes, the code doens't know this just from the 
# PID value, so if an empty title is found (after startup) then it must be assumed
# VLC has closed, and the script ends. This is a fail safe to ensure the script 
# doesn't lurk endlessly in the background.
#
# REQUIREMENTS:
# OS: LINUX (won't work on windows) as it uses unix sockets to communicate with/control VLC
# PREFERENCES:
# For this script to work, you need to turn on "Fake TTY" in the preferences in VLC
# Preference > Show Advanced > Interface > Main Interface > RC > Fake TTY (checked) (I don't know why)
# 
# SOURCES:
# Initial help found here: (unix sockets and remote control)
# https://n0tablog.wordpress.com/2009/02/09/controlling-vlc-via-rc-remote-control-interface-using-a-unix-domain-socket-and-no-programming/
# 
# Lua script that inspired me to write this
# It kind of does what I wanted, but you have to activate it every time you open VLC (*sigh*)
# http://scientificswede.blogspot.se/2012/05/extending-vlc-with-lua.html
#
# HOW TO USE THIS SCRIPT:
# The general premise is that this script is called when you double click a video file. And instead of 
# VLC being opened directly, it's opened via this script.
#	
# 1. Copy/paste this script to /home/[your username]/vlc_resume.sh
# 2. Edit VLC preferences and check "Fake TTY" (detailed above in REQUIREMENTS)
# 3. Edit /usr/share/applications/vlc.desktop (Ubuntu/Linux Mint, other distros may have this elsewhere)
# 	Make this change: (Comment out Exec line)
#	#Exec=/usr/bin/vlc %U 
#	
#	Add this line below it:
#	Exec=/home/[your username]/vlc_resume.sh %U
# 4. Test by double clicking on a video file that would normally open in VLC.
#	Jump ahead in the file, wait for a second and note the time/location, then close VLC.
#	Double click on the video file again, and it should start up where you left off. (ie, auto resume)

file=$1
if [ ! -f "$file" ]
then
  exit
fi

#Create directory for resume logs
if [ ! -d /tmp/vlcresume ]
then
    mkdir /tmp/vlcresume
fi

run()
{
  pid=$1

  while true; do
    #Pause until file is loaded
    #don't continue with resume recording until there
    #is a title to use for the log file name
    #this is a lame way to do this, but it works...
  
    title=`echo get_title | nc -U /tmp/vlc.sock`
    filenamemd5=`echo "$title" | md5sum | awk '{ print $1 }'`
   
    if [ "$title" -a "$filenamemd5" ]
    then
      #Title is available for md5 hash (used for log) 
      #continue with the resume checking and logging
      break
    else
      echo 'NO TITLE & NO MD5'
    fi
  done

  #md5 hash of the title is passed to the resume function (part of the log file name)
  filenamemd5_start=`echo get_title | nc -U /tmp/vlc.sock | md5sum | awk '{ print $1 }'`

  #Check for resume right away
  resume $filenamemd5_start

  #Save this md5 has for checking in the loop for file changes
  filenamemd5_last=$filenamemd5_start

  while true; do
    title=`echo get_title | nc -U /tmp/vlc.sock`
	
    #if there is no title, or any value, then exit likely VLC closed on us
    if [ "$title" -a "$filenamemd5" ]
    then
      echo 'FINE'
    else
      echo 'EXIT no title'
      exit
    fi
	
    #Record the current time
    if [[ $(ps -p $pid | grep $pid) ]]
    then
      #Get file name in case new file has been loaded
      #Make an md5 hash for the title.
      filenamemd5=`echo "$title" | md5sum | awk '{ print $1 }'`
      
      #Check to see if file changed
      if [ "$filenamemd5_last" != "$filenamemd5" ]
      then
        #NEW FILE: restart the loop check for new file names
        filenamemd5_last=$filenamemd5
        resume $filenamemd5
      else
        #Record current time position (VLC does this with seconds)
        resumelog="/tmp/vlcresume/$filenamemd5.txt"
        echo get_time | nc -U /tmp/vlc.sock > "$resumelog"		
      fi
    else 
      exit
    fi
    
    #A tight loop doesn't seem to hurt performance, and makes resume quicker
    #change to sleep 3 or sleep 5 if performance is hurt
    sleep 1 
  done
}

resume()
{
  #Use the MD5 hash passed to this function to read a number from a log file.
  filenamemd5=$1
  resumelog="/tmp/vlcresume/$filenamemd5.txt"
  
  #Look for last number in file, but NOT 0, because some errors creep in
  #to the log when opening/closing multiple videos
  resumetime=`grep ^[123456789] "$resumelog" | tail -n 1`

  if [ -n "$resumetime"  ]; then
    echo "RESUMING: $resumetime"
    echo seek $resumetime | nc -U /tmp/vlc.sock
  else
    echo "NOT RESUMING"
  fi
}

coproc vlc --extraintf=oldrc --rc-unix /tmp/vlc.sock "$file" &> out &
pid=$!
run $pid &
#fg %1


