#!/bin/bash

#####################################
#  CSH Scanner Dropbox				#
#  Cronjob for purging old scans	#
#####################################

# Configuration
SCAN_DIR=/tmp/scans   # Directory where scans are stored
# End Configuration

# Let the user know we're starting
echo "Checking for scans older than 30 minutes..."

# Are there any scans to check?
if [ "$(ls -A $SCAN_DIR)" ]; then
     # Yes, loop over all of the scans
	for file in $SCAN_DIR/*
	do
			# Is the scan older than 30 minutes?
			if [ `stat --format=%Y $file` -le $(( `date +%s` - 1800 )) ]; then
					# Yes, delete it
					rm -f $file
					echo "Deleted: $file"
			fi
	done

		# Let the user know we're done processing
	echo "Done!"
else
	# Let the user know there's nothing to do
    echo "No scans to process."
fi
