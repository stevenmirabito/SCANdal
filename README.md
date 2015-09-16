# CSH Scanner Dropbox
Allows CSH members to scan documents to a central server and pick them up from any computer. Documents will only remain on the server for 30 minutes before being automatically deleted via cron, and users will be able to delete their documents on demand as soon as they've downloaded them.

Thanks to [wwwslinger](https://github.com/wwwslinger) for the [Perl script](https://gist.github.com/wwwslinger/ac6b49cb991d2d5263a2) that makes this possible.

## Requirements
This application requires:
* Perl
* Web server with PHP support
* ImageMagik (for PDF conversion)
* start-stop-daemon (for the included init script)

As written, the webapp and scripts expect the following paths:
* Files installed to `/var/csh-scan`
* Scans are stored in `/tmp/scans`

If you want to use different paths, you must change the paths defined in the PHP files, init script, and cron script.

## Installation
1. Change to the installation directory: `cd /var`
2. Clone the repository: `git https://github.com/stevenmirabito/CSH-Scanner-Dropbox.git`
3. Rename the folder: `mv CSH-Scanner-Dropbox csh-scan`
4. Change directory into the installed folder: `cd csh-scan`
5. Make the scripts executable: `chmod +x dell1600n-net-scan* cron.sh`
6. Move the init script to /etc/init.d: `mv dell1600n-net-scan /etc/init.d/`
7. Change ownership of the init script: `chown root:root /etc/init.d/dell1600n-net-scan`
8. Set the init script to automatically run at boot: `chkconfig dell1600n-net-scan defaults`
9. Start the service: `service dell1600n-net-scan start`
10. Add the following line to your crontab (feel free to change the time if you want it to run more/less often, default is 5 minutes):
```
*/5 * * * * /var/csh-scan/cron.sh
```
11. Configure your webserver to point to `/etc/csh-scan/www`
12. Make a test scan to make sure everything works