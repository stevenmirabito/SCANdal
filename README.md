# CSH Scan Dropbox
Allows CSH members to scan documents to a central server and pick them up from any computer. Documents will only remain on the server for 30 minutes before being automatically deleted via cron, and users will be able to delete their documents on demand as soon as they've downloaded them.

Thanks to [wwwslinger](https://github.com/wwwslinger) for the [Perl script](https://gist.github.com/wwwslinger/ac6b49cb991d2d5263a2) that makes this possible.

## Requirements
This application requires:
* Web server with PHP support
* Perl
* ImageMagik (for PDF conversion)

## Usage
Invoke the scanner server daemon with the following command (omit the option argument if PDF conversion is not desired):
`perl dell1600n-net-scan.pl --listen <printer hostname> --name CSH --multi-session --resolution 300 --option pdf`