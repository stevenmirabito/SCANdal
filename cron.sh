#!/bin/bash

#####################################
#  CSH Scanner Dropbox				#
#  Cronjob for purging old scans	#
#####################################

# Configuration
SCAN_DIR=/tmp/scans/*   # Directory where scans are stored
# End Configuration

# Loop over all of the scans
echo "Checking for scans older than 30 minutes..."

for file in $SCAN_DIR
do
        # Is the scan older than 30 minutes?
        if [ `stat --format=%Y $file` -le $(( `date +%s` - 1800 )) ]; then
                # Yes, delete it
                rm -f $file
                echo "Deleted: $file"
        fi
done

echo "Done!"