#!/usr/bin/perl -w

# Perl hack to do network scanning using Dell 1600n printer/scanner/fax/copier.
# Read LICENCE section below for terms and conditions.
# Run with no args for usage.
# $Id: dell1600n-net-scan.pl,v 1.64 2010-09-19 16:19:33 jon Exp $
#
# Jon Chambers, 2005-05-19
#
# Contains excellent and gratefully received patches from:
#   Dani Gutiérrez (Ricoh FX200)
#   Philip Roche (Xerox Phaser 6110)
#   Laurent Ernes (Samsung CLX-2160N)
#   Christophe Danker (Samsung SCX-4720FN)
#
use strict;
use IO::Socket;
use IO::Select;
use POSIX;
use Sys::Hostname;
use Time::HiRes qw( usleep );

#=========================================================================

# VERSION
$main::version = "1.14";
$main::cvsId = '$Id: dell1600n-net-scan.pl,v 1.64 2010-09-19 16:19:33 jon Exp $';

#=========================================================================

# LICENCE

$main::licence = "
This software is open source.  Feel free to copy and distribute as
you like.  If you use it as the basis of other software then it would
be polite to credit me.  If this software is useful to you then feel
free to send a nice postcard from wherever you are to 
Jon Chambers, 30 Stephenson Rd, London W7 1NW, UK.

This program is provided in the hope that it will be useful.  It comes
with no warranty.  USE AT YOUR OWN RISK.

Jon Chambers (jon\@jon.demon.co.uk), 2007-11-17
";

#=========================================================================

# fill the nice globals with defaults

# uncomment the appropriate default for your model
$main::model = "1600n";
#$main::model = "1815dn";
#$main::model = "fx200";
#$main::model = "6110mfp";
#$main::model = "clx2160n";
#$main::model = "scx4720fn";

# get hostname (minus any domain part and non-alphanumerics)
$main::clientName = hostname();
$main::clientName =~ s/\..*$//g;
$main::clientName =~ s/[^\w]//g;

# If defined then should be a 4-digit PIN number
#$main::clientPin = 1234;
$main::clientPin = undef;

$main::printerAddr = "";
$main::printerPort = 1124;

$main::scanFileDir = ".";
$main::scanFilePrefix = "scan-";

$main::softwareName = "dell1600n-net-scan";

# if set then specifies a particular network interface
$main::bindAddr = undef;

# broadcast address too find scanners
$main::broadcastAddr = "255.255.255.255";

# time to wait between re-registrations (seconds)
$main::scanWaitLoopTimeoutSec = 60;

# set non-0 to print lots of debug nonsense
$main::debug = 0;

# kernel-specific network stuff for now-defunct UPNP multicast
$main::IP_ADD_MEMBERSHIP_linux = 35; # Linux
#$main::IP_ADD_MEMBERSHIP_windows = 5; # Windows

# choose linux by default
$main::IP_ADD_MEMBERSHIP = $main::IP_ADD_MEMBERSHIP_linux;

# Command to send file as email attachment.
# (See PostProcessFile comments for substitutions.)
%main::emailCmd = ( "cmd" => "echo new scan | mutt &infiles; -s \"new scan\" &email;",
            "inFilePrefix" => "-a ",
            "delInFiles" => 0 );

# The following options must match or things will go wrong.
$main::preferredFileType = 2; # ( 2=>TIFF, 4=>PDF, 8=>JPEG )
$main::preferredFileCompression = 0x08;  # ( 0x08 => CCIT Group 4, 0x20 => JPEG )
$main::preferredFileComposition = 0x01;  # ( 0x01 => TIFF/PDF, 0x40 => JPEG )

$main::preferredResolution = 200;

# Profiles for Dell 1815dn and Xerox Phaser 6110mfp
# See comments above for legal values for type, compression and composition
%main::profiles = (
    "TIFF 100" => { "type" => 2, "cprss" => 0x08, "cmpsn" => 0x01, "res" => 100 },
    "TIFF 200" => { "type" => 2, "cprss" => 0x08, "cmpsn" => 0x01, "res" => 200 },
    "TIFF 300" => { "type" => 2, "cprss" => 0x08, "cmpsn" => 0x01, "res" => 300 },
    "PDF 100"  => { "type" => 4, "cprss" => 0x08, "cmpsn" => 0x01, "res" => 100 },
    "PDF 200"  => { "type" => 4, "cprss" => 0x08, "cmpsn" => 0x01, "res" => 200 },
    "PDF 300"  => { "type" => 4, "cprss" => 0x08, "cmpsn" => 0x01, "res" => 300 },
    "JPEG 200" => { "type" => 8, "cprss" => 0x20, "cmpsn" => 0x40, "res" => 200 },
    "JPEG 300" => { "type" => 8, "cprss" => 0x20, "cmpsn" => 0x40, "res" => 300 },
    "COLOUR PDF 200" => { "type" => 8, "cprss" => 0x20, "cmpsn" => 0x40, "res" => 200, "profileOption" => "pdf" },
    "COLOUR PDF 300" => { "type" => 8, "cprss" => 0x20, "cmpsn" => 0x40, "res" => 300, "profileOption" => "pdf" },
);

$main::emailAddr = undef;

# command to convert to PDF
#$main::pdfConvertCmd = undef;
# NOTE: convert is part of the imagemagick package
# NOTE2: zip compressed pdf files are not supported by Adobe Acrobat before
#   version 3.
%main::pdfConvertCmd = ( "cmd" => "convert -compress zip &infiles; &outFile;",
            "outFile" => "&scanFileDir;/&scanFilePrefix;&timestamp;.pdf",
            "delInFiles" => 0 );

# if set then all scans will be converted to PDF
$main::forceToPdf = 0;

# if true then exit after single session
$main::singleSession = 1;

# instance number (concatenated with IP address to create uid for 1815dn and 6110mfp)
$main::instanceId = 0;

# Define optional commands here.
# These take the form of a hash (keyed by option name) of command hashes (in the
#    same format as %main::pdfConvertCmd above)
# If the option is selected the command hash will be passed to 
#   PostProcessFile() (see comments in function for available substitutions)
%main::options = ();

# tgz option writes scanned files to a tgz archive.
# Not enormously useful but a fair usage example...
$main::options{ "tgz" } = {
    "cmd" => "tar zcvf &outFile; &infiles;",
    "outFile" => "&scanFileDir;/&scanFilePrefix;&timestamp;.tgz",
    "delInFiles" => 0,
    "description" => "Write scanned files to a tgz archive"
    };

# gimp option opens files with the GIMP.
$main::options{ "gimp" } = {
    "cmd" => "gimp &infiles;&",
    "description" => "Open scanned files with the GIMP"
    };

# Not enormously useful but a fair usage example...
$main::options{ "multipage-tiff" } = {
    "cmd" => "convert &infiles; &outFile; ",
    "outFile" => "&scanFileDir;/&scanFilePrefix;&timestamp;.tiff",
    "delInFiles" => 1,
    "description" => "Create multipage tiff document"
    };
    
# As %main::pdfConvertCmd but usable via options (and profile options)
$main::options{ "pdf" } = { 
    "cmd" => "convert -compress zip &infiles; &outFile;",
    "outFile" => "&scanFileDir;/&scanFilePrefix;&timestamp;.pdf",
    "delInFiles" => 0,
    "description" => "Convert all scans to PDF format"
    };

# to_web option moves scanned files to web tree
#$main::options{ "to_web" } = {
#    "cmd" => "mv -v &infiles; /home/www/images/",
#    "description" => "Move scanned files to web tree"
#    };

#=========================================================================

# Global state variables

# scan data storage
$main::dataBuf = "";

# filenames scanned this session
@main::sessionFiles = ();

# PDF convert flag
$main::pdfConvert = 0;

# received scan metadata 
$main::fileType = 0; # ( 2=>TIFF, 4=>PDF, 8=>JPEG )
$main::widthPixels = 0;
$main::heightPixels = 0;
$main::xResolution = 0;
$main::yResolution = 0;

# our IP address (raw format)
$main::ipAddr = undef;

# which of the options (if any) is selected
$main::selectedOption = undef;

#=========================================================================

sub GetTimestamp()
# Return local timestamp string as YYYYMMDD-hhmmsss
{
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
    localtime();
    return sprintf( "%04d%02d%02d-%02d%02d%02d",
             $year + 1900,
             $mon + 1,
             $mday,
             $hour,
             $min,
             $sec );
} # GetTimestamp

#=========================================================================

sub ListenForPrinters()
# listens for printers on multicast 239.255.255.250:1900
# Now this code is just included as a curiosity - BroadcastDiscover 
#   is quicker and easier
{
    my $group = '239.255.255.250';
    my $port = 1900;

    print "Listening on multicast group $group:$port\n";

    my $sock = IO::Socket::INET->
    new( Proto => 'udp', LocalPort => $port )
    || die "Error opening socket";
    $sock->setsockopt( 0, 
               $main::IP_ADD_MEMBERSHIP, 
               pack("C8", split(/\./, "$group.0.0.0.0")))
    || die "Couldn't set group: $!\n";

    while (1) {
    my $data;
    next unless $sock->recv( $data, 512 );
    print $data."\n";
    }

} # ListenForPrinters

#=========================================================================

sub BroadcastDiscover()
# Use UDP broadcast to discover devices
{

    print "Broadcasting to $main::broadcastAddr for $main::model-compatible scanners\n\n";

    my $sock = new IO::Socket::INET->new( Proto     => 'udp',
                      LocalAddr => $main::bindAddr,
                      Broadcast => 1
                      )
    or die "Error opening UDP socket";

    my %packet = InitPacket( GetNormalPacketHeader() );
    if ( $main::model eq "1600n" ){
    AppendMessageToPacket( \%packet, 0x25, "std-scan-discovery-all",
                   0x02, 0 );
    } else {
    # 1815dn-compatible (maybe works for fx200 too?)
    AppendMessageToPacket( \%packet, 0x25, "std-scan-discovery-all",
                   0x02, 0 );
    AppendMessageToPacket( \%packet, 0x25, "std-scan-discovery-type",
                   0x06, 1 );
    }
    my $sin = sockaddr_in( $main::printerPort, 
               inet_aton( $main::broadcastAddr ) );
    $sock->send( PackMessage( \%packet ), 0, $sin ) or
    die "Nothing sent";

    # init a select object on our socket
    my $sel = new IO::Select( $sock );

    my $numFound = 0;

    while (1) {

    my @ready = $sel->can_read( 5 );

    if ( ! @ready ){
        # no input yet (we hit the timeout) so exit
        print "Finished querying for network scanners, found $numFound\n";
        exit( 0 );
    }

    my $data;
    if ( ! $sock->recv( $data, 1024 ) ){
        usleep( 100 );
        next;
        } 

    ProcessReceivedPacket( \$data, $sock, "udp" );
    print "\n";

    $numFound++;

    } # while

} # BroadcastDiscover

#=========================================================================

sub OpenUdpPort( $ )
# Open udp socket to printer
{

    my ( $addr ) = @_;

    my $sock = new IO::Socket::INET->new(PeerPort  => $main::printerPort,
                     PeerAddr  => $addr,
                     LocalAddr => $main::bindAddr,
                     Proto     => 'udp'
                     )
    or die "Can't connect to: $addr:$main::printerPort\n";


    # note our ip addr
    $main::ipAddr = $sock->sockaddr();
    print "My IP address is ". join( ".", unpack( "C4", $main::ipAddr ))."\n";
    # sanity check (Windows will fail this)
    if ( ! unpack( "V", $main::ipAddr ) ){
    print "Oh dear, WIN32 UDP sockets are bad... trying to determine local IP address...\n";
    my $tmpsock = new IO::Socket::INET->new(PeerPort  => 5200,
                        PeerAddr  => $addr, 
                        LocalAddr => $main::bindAddr,
                        Proto     => 'tcp' ) ||
                            die "Error making TCP connection to $addr:5200";
    $main::ipAddr = $tmpsock->sockaddr();
    print "My IP address is ". join( ".", unpack( "C4", $main::ipAddr )).
        "\n";
    }

    # Work out the manufacturer from the model number supplied;
    my $make;
    if ( $main::model eq "fx200" ) {
        $make = "Ricoh";
    } elsif ( $main::model eq "6110mfp" ) {
        $make = "Xerox Phaser";
    } elsif ( $main::model eq "clx2160n" || $main::model eq "scx4720fn" ) {
        $make = "Samsung";
    } else {
        $make = "Dell";
    }
    print "Registering with $make $main::model $addr:$main::printerPort as $main::clientName\n";

    return $sock;

} # OpenUdpPort

#=========================================================================

sub PostProcessFile( $ )
# Performs post-processing on the current file list
# param 1 : reference to hash with members:
#   cmd: post-process command (required)
#   outFile : output file (optional)
#   inFilePrefix : prefix to infile(s) (optional)
#   delInFiles : if set and true then input files will be deleted
#
# The following substitutions will be made on cmd:
#   &infiles; => list of input files (optionally prefixed by inFilePrefix)
#   &outFile; => outFile
#
# The following substitutions will be made on outFile:
#   &scanFileDir; => $main::scanFileDir 
#   &scanFilePrefix => $main::scanFilePrefix
#   &timestamp; => the current timestamp
#
{
    my ( $in ) = @_;

    # sanity check
    if ( ! scalar @main::sessionFiles ){
    print "PostProcessFile: No files left to process\n";
    return;
    }

    my $cmd = $$in{ "cmd" };
    if ( ! defined( $cmd ) ){ return }

    my $prefix = $$in{ "inFilePrefix" };
    if ( ! defined( $prefix ) ){ $prefix = "" }

    my $outFile = $$in{ "outFile" };

    my $timestamp = GetTimestamp();

    # perform substitutions on outFile
    if ( defined $outFile ){
    $outFile =~ s/&scanFileDir;/$main::scanFileDir/sg;
    $outFile =~ s/&scanFilePrefix;/$main::scanFilePrefix/sg;
    $outFile =~ s/&timestamp;/$timestamp/sg;
    }

    # build post-process command
    my $infiles = "";
    foreach my $file ( @main::sessionFiles ){
    $infiles .= $prefix . $file . " ";
    }
    $cmd =~ s/&infiles;/$infiles/sg;

    if ( defined ( $outFile ) ){
    $cmd =~ s/&outFile;/$outFile/sg;
    }

    if ( defined ( $main::emailAddr ) ){
    $cmd =~ s/&email;/$main::emailAddr/sg;
    }
    print "Running: $cmd\n";

    my $ret = system( $cmd );
    if ( $ret != 0 ){
    print "WARNING: Got non-zero return code - this is generally bad...\n";
    }

    if ( $$in{ "delInFiles" } ){
    foreach my $xxx ( @main::sessionFiles ){
        print "Deleting $xxx\n";
        unlink $xxx;
    }
    @main::sessionFiles = ();
    }

    if ( defined( $outFile ) ){
    push @main::sessionFiles, $outFile;
    }

} # PostProcessFile()

#=========================================================================

sub ProcessReceivedPacket( $$$ )
# Displays the contents of a packet received from the printer to screen
#   and processes it as appropriate
# Processed data is removed from the packet.
# In "udp" mode the packet must be whole (ie: the data size must
#   match that read from the header.  In "tcp" mode, in case of a
#   an incomplete packet the the function returns to allow more data
#   to be read from the socket
# param 1 : reference to binary data
# param 2 : socket object (in case a reply is required)
# param 3 : mode, either "tcp" or "udp"
{

    my ( $data, $sock, $mode ) = @_;

    if ( $main::debug ){
    print "** Processing packet of " . ( length ${$data} ) . " bytes\n";
    }

    # init a reply packet ready for use
    my %packet = InitPacket( GetReplyPacketHeader() );

    my $bLastPacket = 0;
    my $bPrefsRequested = 0;

    # process as much of the data as we can
    while ( length ${$data} >= 8 ){

    # copy data into an array
    my @datArray = unpack( "C*", ${$data} );

    # extract the header
    my @header = splice( @datArray, 0, 8 );

    my $now = ctime( time() );
    chop $now;

    if ( $main::debug ){
        print "$now:  header: ".join( " ", @header )."\n";
    }

    my $ok = 1;
    if ( @header != 8 ){
        print "*** header less than 8 bytes\n";
        $ok = 0;
    }

    my $expectedSize = ($header[7]+($header[6]<<8) );
    my $actualSize =  @datArray;

    # if tcp mode then check whether we need more data
    if ( ( $mode eq "tcp" ) &&  ( $actualSize < $expectedSize ) ){
        if ( $main::debug ){
        print "*** Incomplete packet (expect $expectedSize, ".
            "got $actualSize)\n";
        }
        return;
    }

    # if udp mode then we expect an exact match
    if ( ( $mode eq "udp" ) && ( $expectedSize != $actualSize ) ) {
        print "*** data size mismatch: (expect $expectedSize, got $actualSize)\n";
        $ok = 0;
    } # if

    my ( $cmdName, $cmdValue );
    if ( ! $ok ){

        # unrecognised data block : just HexDump it
        print "Unexpected block format:\n";

        print HexDump ${$data};

    } else {

        # remove the data that we will process from the start of the data buffer
        ${$data} = substr ${$data}, ( 8 + $expectedSize );

        # trim the excess elements from the end of @datArray
        @datArray = @datArray[ 0..($expectedSize - 1) ];

        # loop until all the data has been processes
        while ( @datArray ){

        # extract the command
        my @cmdSub = splice( @datArray, 0, 3 );
        $cmdName  = pack( "C*", 
                  splice(  @datArray, 0,
                       ( ( $cmdSub[ 1 ] << 8 ) + 
                         $cmdSub[ 2 ] )) );

        if ( $main::debug ){
            print "  $cmdName ($cmdSub[0]): ";
        }

        # extract the payload
        my @plSub = splice( @datArray, 0, 3 );


        my $plType = $plSub[ 0 ];
        my $plSize = ( $plSub[ 1 ] << 8 ) + $plSub[ 2 ];

        if ( $main::debug ){
            print "[$plType] ";
        }

        my @plArray = splice( @datArray, 0, $plSize );

        # extract payload in a manner appropriate to type
        if ( $plType == 0x0b  ){

            # treat as a string
            $cmdValue = pack( "C*", @plArray );
            if ( $main::debug ){ print $cmdValue; }

        } elsif ( ( ( $plType == 0x06 ) || ( $plType == 0x05 ) ) && 
              ( @plArray == 4 ) ){

            # treat as an int
            $cmdValue = ( ( $plArray[0] << 24 ) +
                  ( $plArray[1] << 16 ) +
                  ( $plArray[2] << 8 ) +
                  $plArray[3] );

            if ( $main::debug ){ print $cmdValue; }

        } elsif ( ( $plType == 0x04 ) && ( @plArray == 2 ) ){

            # treat as a short
            $cmdValue = ( ( $plArray[0] << 8 ) +
                  $plArray[1] );
            if ( $main::debug ){ print $cmdValue; }

        } elsif ( ( $plType == 0x0a ) && ( @plArray == 4 ) ){

            # IP address
            $cmdValue = $cmdValue = join( ".", @plArray );
            if ( $main::debug ){ print $cmdValue; }

        } else {
            # unknown type
            $cmdValue = join( " ", @plArray );
            if ( $main::debug ){ print $cmdValue; }
        }

        if ( $main::debug ){ print "\n"; }

        # respond appropriately (if we know how)

        if ( $cmdName eq "std-scan-request-tcp-connection" ){
            ProcessTcpRequest();

        } elsif ( $cmdName eq "std-scan-session-open" ){

            my $respVal = 
            (  $main::model eq "1815dn"
            || $main::model eq "6110mfp" 
            || $main::model eq "fx200"
            || $main::model eq "clx2160n"
            || $main::model eq "scx4720fn" ) ? 1 : 0;

            AppendMessageToPacket( \%packet, 
                       0x22,
                       "std-scan-session-open-response",
                       0x05,
                       $respVal );

        } elsif ( $cmdName eq "std-scan-getclientpref" ){

            # make a note that client prefs have been requested but don't fill them in yet
            $bPrefsRequested = 1;

        } elsif ( $cmdName eq "std-scan-document-start" ){

            AppendMessageToPacket( \%packet, 
                       0x22,
                       "std-scan-document-start-response",
                       0x05,
                       0 );

            # reset session file list
            @main::sessionFiles = ();

        } elsif ( $cmdName eq "std-scan-document-file-type" ){

            $main::fileType = $cmdValue;

        } elsif ( $cmdName eq "std-scan-document-xresolution" ){

            $main::xResolution = $cmdValue;

        } elsif ( $cmdName eq "std-scan-document-yresolution" ){

            $main::yResolution = $cmdValue;

        } elsif ( $cmdName eq "std-scan-page-widthpixel" ){

            $main::widthPixels = $cmdValue;

        } elsif ( $cmdName eq "std-scan-page-heightpixel" ){

            $main::heightPixels = $cmdValue;


        } elsif ( $cmdName eq "std-scan-page-start" ){

            AppendMessageToPacket( \%packet, 
                       0x22,
                       "std-scan-page-start-response",
                       0x05,
                       0 );

            # write out any pre-existing page data
            if ( length  $main::dataBuf ){
            OutputScanData();
            }

            # reset the data buffer ready to store a page
            $main::dataBuf = "";

        } elsif ( $cmdName eq "std-scan-page-end" ){

            AppendMessageToPacket( \%packet, 
                       0x22,
                       "std-scan-page-end-response",
                       0x05,
                       0 );

        } elsif ( $cmdName eq "std-scan-document-end" ){

            AppendMessageToPacket( \%packet, 
                       0x22,
                       "std-scan-document-end-response",
                       0x05,
                       0 );

            # write out data
            OutputScanData();

            # reset the data buffer
            $main::dataBuf = "";

        } elsif ( $cmdName eq "std-scan-session-end" ){

            AppendMessageToPacket( \%packet, 
                       0x22,
                       "std-scan-session-end-response",
                       0x05,
                       0 );
            # shut down after the next send
            $bLastPacket = 1;

            # do PDF conversion
            if ( $main::pdfConvert ){
            if ( defined( $main::pdfConvertCmd{"cmd"} ) ){
                PostProcessFile( \%main::pdfConvertCmd );
            } else {
                print "*** \%main::pdfConvertCmd not set - ".
                "skipping PDF conversion\n";
            }
            } # if pdf

            # do any extra requested option processing
            if ( defined( $main::selectedOption ) ){
            PostProcessFile( \%{ $main::options{ $main::selectedOption } } );
            }

            # email the result to somewhere if required
            if ( defined( $main::emailAddr ) ){

            # just in case
            if ( ! defined( $main::emailCmd{ "cmd" } ) ){
                print "WARNING: you must define \%main::emailCmd in the script for the email facility to work\n";
            } else {
                PostProcessFile( \%main::emailCmd );
            }
            } # if emailAddr


        } elsif ( $cmdName eq "std-scan-scandata-error" ){

            # start of a chunk of binary scan data
            my @binHead = splice( @datArray, 0, 8 );

            my $chunkSize = ( $binHead[ 6 ] << 8 ) + $binHead[ 7 ];

            if ( $main::debug ){ 
            print "Reading $chunkSize bytes of scan data\n";
            }

            $main::dataBuf .= pack( "C*", 
                        splice( @datArray, 0, 
                            $chunkSize ) );

            if ( $main::debug ){ 
            print "(accumulated " . 
                ( length $main::dataBuf ) . " bytes of data...)\n";
            }

        } elsif ( $cmdName eq "std-scan-discovery-ip" ){

            print "IP Address: $cmdValue\n";

        } elsif ( $cmdName eq "std-scan-discovery-firmware-version" ){

            print "Firmware version: $cmdValue\n";

        } elsif ( $cmdName eq "std-scan-discovery-model-name" ){

            print "Model: $cmdValue\n";

        } elsif ( $cmdName eq "std-scan-getclientpref-application-name" ){

            # chop off leading '0' and trailing "\0"s
            $cmdValue =~ s/^0([^\0]*)\0*$/$1/g;

            if ( defined( $main::profiles{ $cmdValue } ) ){
            print "Selected profile ".$main::profiles{ $cmdValue }."\n";

            $main::preferredFileType = $main::profiles{ $cmdValue }{ "type" };
            $main::preferredFileCompression = $main::profiles{ $cmdValue }{ "cprss" };
            $main::preferredFileComposition = $main::profiles{ $cmdValue }{ "cmpsn" };
            $main::preferredResolution = $main::profiles{ $cmdValue }{ "res" };

            if ( defined( $main::profiles{ $cmdValue }{ "profileOption" } ) )
            {
                # override selected option
                $main::selectedOption = $main::profiles{ $cmdValue }{ "profileOption" }
            }

            } elsif ( $cmdValue ne "" ) {
                print "Ignoring unknown profile ".$cmdValue."\n";
            }

        } # if

        } # while

    } # if

    if ( $main::debug ){ print "\n"; }

    } # while


    # if prefs have been requested then fill them in
    if ( $bPrefsRequested ){

    my ( $x1, $x2, $y1, $y2, $paperSizeDetect );
    if ( $main::model eq "1815dn" 
      || $main::model eq "6110mfp" 
      || $main::model eq "clx2160n"
      || $main::model eq "scx4720fn" ){
        if ( $main::preferredFileType == 8 ){
        # JPEG: currently set equal to TIFF value but may need to be different, Jon 2007-01-02
        ( $x1, $x2, $y1, $y2, $paperSizeDetect ) = ( 0x40533333, 0x434eb333, 0x40533333, 0x4392d99a, 4 );
        } else {
        # TIFF/PDF
        ( $x1, $x2, $y1, $y2, $paperSizeDetect ) = ( 0x40533333, 0x434eb333, 0x40533333, 0x4392d99a, 4 );
        }
    } else {
        ( $x1, $x2, $y1, $y2, $paperSizeDetect ) = ( 0, 0, 0, 0, 0 );
    }

    AppendMessageToPacket( \%packet, 
                   0x22,
                   "std-scan-getclientpref-x1",
                   0x07,
                   $x1 );
    AppendMessageToPacket( \%packet, 
                   0x22,
                   "std-scan-getclientpref-x2",
                   0x07,
                   $x2 );
    AppendMessageToPacket( \%packet, 
                   0x22,
                   "std-scan-getclientpref-y1",
                   0x07,
                   $y1 );
    AppendMessageToPacket( \%packet, 
                   0x22,
                   "std-scan-getclientpref-y2",
                   0x07,
                   $y2 );
    AppendMessageToPacket( \%packet, 
                   0x22,
                   "std-scan-getclientpref-xresolution",
                   0x04,
                   $main::preferredResolution );
    AppendMessageToPacket( \%packet, 
                   0x22,
                   "std-scan-getclientpref-yresolution",
                   0x04,
                   $main::preferredResolution );
    AppendMessageToPacket( \%packet, 
                   0x22,
                   "std-scan-getclientpref-image-composition",
                   0x06,
                   $main::preferredFileComposition );
    AppendMessageToPacket( \%packet, 
                   0x22,
                   "std-scan-getclientpref-brightness",
                   0x02,
                   0x80 );
    AppendMessageToPacket( \%packet, 
                   0x22,
                   "std-scan-getclientpref-image-compression",
                   0x06,
                   $main::preferredFileCompression );
    AppendMessageToPacket( \%packet, 
                   0x22,
                   "std-scan-getclientpref-file-type",
                   0x06,
                   $main::preferredFileType );
    AppendMessageToPacket( \%packet, 
                   0x22,
                   "std-scan-getclientpref-paper-size-detect",
                   0x06,
                   $paperSizeDetect );
    AppendMessageToPacket( \%packet, 
                   0x22,
                   "std-scan-getclientpref-scanner-type",
                   0x06,
                   0 );

    if (   $main::model eq "1815dn"
        || $main::model eq "6110mfp"
        || $main::model eq "clx2160n"
        || $main::model eq "scx4720fn" )
    {
        AppendMessageToPacket( \%packet, 
                   0x22,
                   "std-scan-getclientpref-application-list",
                   0x0b,
                   GetProfileNameData()
                   );
    } # if

    } # if prefs requested

    # send packet if some messages have been appended to it
    if ( @{$packet{ "messages" }} > 0 ){

    if ( $main::debug ){
        print "Sending message with " . ( scalar( @{$packet{ "messages" }} ) ) . " items\n";
    }

    $sock->send( PackMessage( \%packet ) );
    }

    if ( $bLastPacket ){
    # initialise a clean socket shutdown
    if ( $main::debug ){
        print "Shutting down TCP connection\n";
    }
    $sock->shutdown( 2 );
    }

} # ProcessReceivedPacket

#=========================================================================

sub GetNormalPacketHeader()
# returns a "normal" packet header (eg: 02 00 01 02 00 00)
{
    if ( $main::model eq "1815dn" ){
        return pack( "C*", 0x02 ,0x01, 0x01, 0x02 ,0x00 ,0x00 );
    } elsif ( $main::model eq "fx200" ){
        return pack( "C*", 0x03 ,0x00, 0x01, 0x02 ,0x00 ,0x00 );
    } elsif ( $main::model eq "6110mfp" ){
        return pack( "C*", 0x04 ,0x00, 0x01, 0x02 ,0x00 ,0x00 );
    } elsif ( $main::model eq "clx2160n" || $main::model eq "scx4720fn" ){
        return pack( "C*", 0x01 ,0x00, 0x01, 0x02 ,0x00 ,0x00 );
    } else {
        return pack( "C*", 0x02 ,0x00, 0x01, 0x02 ,0x00 ,0x00 );
    }

} # GetNormalPacketHeader

#=========================================================================

sub GetReplyPacketHeader()
# returns a "reply" packet header (eg: 02 00 02 02 00 00)
{
    if ( $main::model eq "1815dn" ){
        return pack( "C*", 0x02 ,0x01, 0x02, 0x02 ,0x00 ,0x00 );
    } elsif ( $main::model eq "fx200" ){
        return pack( "C*", 0x03 ,0x00, 0x02, 0x02 ,0x00 ,0x00 );
    } elsif ( $main::model eq "6110mfp" ){
        return pack( "C*", 0x04 ,0x00, 0x02, 0x02 ,0x00 ,0x00 );
    } elsif ( $main::model eq "clx2160n" || $main::model eq "scx4720fn" ){
        return pack( "C*", 0x01 ,0x00, 0x02, 0x02 ,0x00 ,0x00 );
    } else {
        return pack( "C*", 0x02 ,0x00, 0x02, 0x02 ,0x00 ,0x00 );
    }

} # GetReplyPacketHeader

#=========================================================================

sub InitPacket( $ )
# initialise a packet to send to printer
# param 1 : 6 byte header (eg: as from GetNormalPacketHeader() )
# returns a hash containing an initialised packet
{

    my ( $header ) = @_;

    die "Bad packet header" if ( length $header != 6 );

    my %packet = ( "header" => $header );

    @{$packet{ "messages" }} = ();

    return %packet;

} # InitPacket

#=========================================================================

sub AppendMessageToPacket( $$$$$ )
# appends a message to a packet
# param 1 : reference to packet (hash)
# param 2 : message name type
# param 3 : message name
# param 4 : message value type
# param 5 : message value
# dies in case of trouble
{

    my ( $nameType, $name, $valueType, $value ) = @_[1..4];

    my $message = pack ( "Cn", $nameType, length $name ) . $name;

    if ( $valueType == 0x02 ){
    # unsigned char

    $message .= pack( "CnC", $valueType, 1, $value );

    } elsif ( $valueType == 0x04 ){
    # unsigned short

    $message .= pack( "Cnn", $valueType, 2, $value );

    } elsif ( $valueType == 0x07 || $valueType == 0x06 || $valueType == 0x05 ){
    # unsigned int

    $message .= pack( "CnN", $valueType, 4, $value );

    } elsif ( $valueType == 0x0a ){
    # ip address type

    $message .= pack( "Cn", $valueType, length $value ) . $value;

    } elsif ( $valueType == 0x0b ){
    # char[] type

    $message .= pack( "Cn", $valueType, length $value ) . $value;

    } else {
    die "Unknown value type: $valueType";

    }                # if

    push @{ $_[0] { "messages" }}, $message;

} # AppendMessageToPacket

#=========================================================================

sub HexDump( $ )
# A poor man's hex dump
{
    my $ret = "";
    my $numBytes = 0;

    foreach my $byte ( unpack( "C*", $_[0] ) ){

    $ret .= sprintf( "%02X ", $byte );
    if (  ! ( ( ++$numBytes ) % 16 ) ) { $ret .= "\n" }
    } # foreach

    if ( ( ++$numBytes ) % 16 ) { $ret .= "\n" }

    return $ret;

} # HexDump 

#=========================================================================

sub PackMessage( $ )
# packs a printer message into binary format (ready to send)
# param 1 : reference to packet hash
# returns binary value
{
    my $payload;

    # build the payload
    foreach my $message ( @{ $_[0] { "messages" }} ){
    $payload .= $message;
    }

    my $packet =  $_[0] { "header" } . 
    pack( "n", length $payload ) .
    $payload;


    if ( $main::debug ){
    print "Sending packet:\n" . HexDump( $packet );
    }

    # return the full message
    return $packet;

} # PackMessage

#=========================================================================

sub ProcessTcpRequest()
# opens a TCP/IP socket to $main::printerAddr and processes scan requests received
{

    my $sock = new IO::Socket::INET->new(PeerPort  => $main::printerPort,
                     PeerAddr  => $main::printerAddr,
                     LocalAddr => $main::bindAddr,
                     Proto     => 'tcp'
                     )
    or die "Can't connect to: $main::printerAddr:$main::printerPort (tcp/ip)\n";

    print "** Opened TCP/IP connection to $main::printerAddr:$main::printerPort\n";

    my $data = "";
    my $mesg;

    # If this is 1815dn or 6110mfp mode then we must zero scan prefs in order to 
    # prompt the scanner to specify the profile name
    if ( $main::model eq "1815dn" || $main::model eq "6110mfp"){
    $main::preferredFileType = 0;
    $main::preferredFileCompression = 0;
    $main::preferredFileComposition = 0;
    $main::preferredResolution = 0;
    } # if

    my $isOpen = 1;
    while ( $isOpen && defined( $sock->recv( $mesg, 2048, 0 ) ) ) {

    # an empty mesg means a shutdown has occurred
    if ( $mesg eq "" ){ 
        $sock->close(); 
        $isOpen = 0; 
        next; 
    }

    # append to data buffer and process the result
    $data .= $mesg;
    ProcessReceivedPacket( \$data, $sock, "tcp" );

    } # while

    print "** Closed TCP/IP connection to $main::printerAddr:$main::printerPort\n";

    # quit after single session if required
    if ( $main::singleSession != 0 ){ exit 0 }

} # ProcessTcpRequest

#=========================================================================

sub OutputScanData()
# writes out contents of $main::dataBuf to file
{

    my $suffix = "dat";

    # format-specific stuff
    if ( $main::fileType == 2  ){
    # TIFF
    $suffix = "tif";
    $main::pdfConvert = $main::forceToPdf;
    AddTiffHeaders();

    } elsif ( $main::fileType == 4 ){
    # PDF
    $suffix = "tif";
    $main::pdfConvert = 1;
    AddTiffHeaders();

    } elsif ( $main::fileType == 8 ){
    # JPEG
    $main::pdfConvert = $main::forceToPdf;
           $suffix = "jpg";

    } else {
    print "*** WARNING: Unexpected file format ($main::fileType)\n";

    } # if

    my $fileName = "$main::scanFileDir/$main::scanFilePrefix" .
    GetTimestamp() . ".$suffix";

    print "Writing data to $fileName\n";

    open SCANOUT, ">$fileName" or die "opening $fileName";

    # set output handle to raw binary mode
    binmode( SCANOUT );

    print SCANOUT $main::dataBuf;

    close SCANOUT;

    # add this filename to the list
    push @main::sessionFiles, $fileName;

} # OutputScanData

#=========================================================================

sub AddTiffHeaders()
# adds TIFF headers to data stored in $main::dataBuf;
{

    # build timestamp
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
    localtime();
    my $stamp = sprintf( "%04d-%02d-%02d %02d:%02d:%02d",
             $year + 1900,
             $mon + 1,
             $mday,
             $hour,
             $min,
             $sec );

    # note our data size (before we modify it!)
    my $dataSize = length $main::dataBuf;

    # calculate offsets to Image File Directory and other bits
    my $dataOffset = 8;

    my $stampOffset = $dataOffset + length $main::dataBuf;

    # align to word boundary
    if ( $stampOffset % 2 ){ $stampOffset++ }

    my $softwareNameOffset = $stampOffset + length( $stamp ) 
    + 1;            # don't forget NULL
    if ( $softwareNameOffset % 2 ){ $softwareNameOffset++ }

    my $xresOffset = $softwareNameOffset + length( $main::softwareName ) + 1;
    if ( $xresOffset % 2 ){ $xresOffset++ }

    my $yresOffset = $xresOffset + 8;
    my $ifdOffset = $yresOffset + 8;

    # we now have enough information to insert the file header
    $main::dataBuf = pack( "CCCCV", 0x49, 0x49, 0x2A, 0x00, $ifdOffset ) . 
    $main::dataBuf;

    # pad
    if ( length ( $main::dataBuf ) % 2 ){ $main::dataBuf .= pack( "C", 0 ) }

    # add timestamp string ( + NULL terminator )
    $main::dataBuf .= $stamp . pack( "C", 0 );

    # pad
    if ( length ( $main::dataBuf ) % 2 ){ $main::dataBuf .= pack( "C", 0 ) }

    # add software string name ( + NULL )
    $main::dataBuf .= $main::softwareName . pack( "C", 0 );

    # pad
    if ( length ( $main::dataBuf ) % 2 ){ $main::dataBuf .= pack( "C", 0 ) }

    # add x and y resolutions
    $main::dataBuf .= pack( "VV", $main::xResolution, 1 );
    $main::dataBuf .= pack( "VV", $main::yResolution, 1 );

    # append field count
    $main::dataBuf .= pack( "v", 14 );

    # NewSubFileType
    $main::dataBuf .= pack( "vvVV", 0xfe, 4, 1, 2 );

    # ImageWidth
    $main::dataBuf .= pack( "vvVV", 0x100, 4, 1, $main::widthPixels );

    # ImageLength
    $main::dataBuf .= pack( "vvVV", 0x101, 4, 1, $main::heightPixels );

    # Compression ( 4 == CCIT Group 4)
    $main::dataBuf .= pack( "vvVvv", 0x103, 3, 1, 4, 0 );

    # PhotometricInterpretation ( 0 = White Is Zero )
    $main::dataBuf .= pack( "vvVvv", 0x106, 3, 1, 0, 0 );

    # StripOffsets
    $main::dataBuf .= pack( "vvVV", 0x111, 4, 1, 8 );

    # RowsPerStrip
    $main::dataBuf .= pack( "vvVV", 0x116, 4, 1, $main::heightPixels );

    # StripByteCounts
    $main::dataBuf .= pack( "vvVV", 0x117, 4, 1, $dataSize );

    # XResolution
    $main::dataBuf .= pack( "vvVV", 0x11a, 5, 1, $xresOffset );

    # YResolution
    $main::dataBuf .= pack( "vvVV", 0x11b, 5, 1, $yresOffset );

    # TbOptions
    $main::dataBuf .= pack( "vvVV", 0x125, 4, 1, 0 );

    # ResolutionUnit
    $main::dataBuf .= pack( "vvVvv", 0x128, 3, 1, 2, 0 );

    # Software
    $main::dataBuf .= pack( "vvVV", 0x131, 2, length( $main::softwareName ), 
       $softwareNameOffset );

    # DateTime
    $main::dataBuf .= pack( "vvVV", 0x132, 2, 20, $stampOffset );

    # end marker
    $main::dataBuf .= pack( "V", 0 );

} # AddTiffHeaders

#=========================================================================

sub RegisterWithScanner( $ )
# registers with scanner
# param 1 : a UDP socket to the printer
{
    my ( $sock ) = @_;

    my %packet = InitPacket( GetNormalPacketHeader() );

    AppendMessageToPacket( \%packet, 0x22, "std-scan-subscribe-user-name",
               0x0b, $main::clientName );
    if ( $main::model eq "1815dn" || $main::model eq "6110mfp" || $main::model eq "clx2160n"){
    # this is the MD5 digest of 0000
    AppendMessageToPacket( \%packet, 0x22, "std-scan-subscribe-pin",
                   0x0b, "4a7d1ed414474e4033ac29ccb8653d9b" );
    } elsif ( defined( $main::clientPin ) ){
    AppendMessageToPacket( \%packet, 0x22, "std-scan-subscribe-pin",
                   0x06, $main::clientPin );
    }
    AppendMessageToPacket( \%packet, 0x22, "std-scan-subscribe-ip-address",
               0x0a, $main::ipAddr );
    if ( $main::model eq "1815dn" || $main::model eq "6110mfp"){
    my $uid = $main::ipAddr . pack( "U", $main::instanceId );
    AppendMessageToPacket( \%packet, 0x22, "std-scan-subscribe-uid",
                   0x0b, $uid );
    }

    $sock->send( PackMessage( \%packet ) );

} # RegisterWithScanner

#=========================================================================

sub GetProfileNameData
# returns packed array of 930 bytes containing names of profiles for Dell 
# 1815dn and Xerox 6110mfp
{
    my @profdat = ();

    my @names = sort keys %main::profiles;

    for ( my $iProf = 0; $iProf < 30; $iProf++ ){

    my $profName;
    if ( defined( $names[ $iProf ] ) ){
        $profName = $names[ $iProf ];
        push @profdat, 0x30;
    } else {
        $profName = "";
        push @profdat, 0;
    }

    my @elems = unpack( "C*", $profName );
    for ( my $iEl = 0; $iEl < 30; $iEl++ ){
        push  @profdat, defined( $elems[ $iEl ] ) ?  $elems[ $iEl ] : 0;
    }
    }

    return pack( "C*", @profdat );

} # GetProfileNameData

#=========================================================================

# parse args
my %options;
my $bHelp = 0;

for ( my $iArg = 0; $iArg < @ARGV; ++$iArg ){

    my $thisArg = $ARGV[ $iArg ];

    if ( $thisArg eq "--help" or $thisArg eq "-h" ){
    $bHelp = 1;

    } elsif ( $thisArg eq "--find" ){
    $options{ "find" } = 1;

    } elsif ( $thisArg eq "--debug" ){
    $main::debug = 1;

    } elsif ( $thisArg eq "--1600n" ){
    $main::model = "1600n";

    } elsif ( $thisArg eq "--fx200" ){
    $main::model = "fx200";

    } elsif ( $thisArg eq "--1815dn" ){
    $main::model = "1815dn";

    } elsif ( $thisArg eq "--6110mfp" ){
    $main::model = "6110mfp";

    } elsif ( $thisArg eq "--clx2160n" ){
    $main::model = "clx2160n";

    } elsif ( $thisArg eq "--scx4720fn" ){
    $main::model = "scx4720fn";

    } elsif ( $thisArg eq "--single-session" or $thisArg eq "--single-doc" ){
    $main::singleSession = 1;

    } elsif ( $thisArg eq "--multi-session" or $thisArg eq "--multi-doc" ){
    $main::singleSession = 0;

    } elsif ( $thisArg eq "--force-pdf" ){
    $main::forceToPdf = 1;

    } elsif ( $thisArg eq "--listen" ){
    die "--listen requires a parameter" unless
        $options{ "listen" } = $ARGV[ ++$iArg ];

    } elsif ( $thisArg eq "--scan-dir" ){
    die "--scan-dir requires a parameter" unless
        $main::scanFileDir = $ARGV[ ++$iArg ];

    } elsif ( $thisArg eq "--email" ){
    die "--email requires a parameter" unless
        $main::emailAddr = $ARGV[ ++$iArg ];

    } elsif ( $thisArg eq "--scan-prefix" ){
    die "--scan-prefix requires a parameter" unless
        $main::scanFilePrefix = $ARGV[ ++$iArg ];

    } elsif ( $thisArg eq "--name" ){
    die "--name requires a parameter" unless
        $main::clientName = $ARGV[ ++$iArg ];

    } elsif ( $thisArg eq "--format" ){
    die "--format requires a parameter" unless
        my $fmt = lc $ARGV[ ++$iArg ];
        if ( $fmt eq "tiff" ){
            $main::preferredFileType = 0x02;
            $main::preferredFileCompression = 0x08;    
            $main::preferredFileComposition = 0x01;
    } elsif ( $fmt eq "pdf" ){
            $main::preferredFileType = 0x04;
            $main::preferredFileCompression = 0x08;
            $main::preferredFileComposition = 0x01;
    } elsif ( $fmt eq "jpeg" ){
            $main::preferredFileType = 0x08;
            $main::preferredFileCompression = 0x20;
            $main::preferredFileComposition = 0x40;
    } else {
        print "Ignoring unexpected format $fmt\n"
    }
    } elsif ( $thisArg eq "--resolution" ){
    die "--resolution requires a parameter" unless
        $main::preferredResolution = $ARGV[ ++$iArg ];

    } elsif ( $thisArg eq "--bind" ){
    die "--bind requires a parameter" unless
        $main::bindAddr = $ARGV[ ++$iArg ];

    } elsif ( $thisArg eq "--broadcast" ){
    die "--broadcast requires a parameter" unless
        $main::broadcastAddr = $ARGV[ ++$iArg ];

    } elsif ( $thisArg eq "--instance-id" ){
    die "--instance-id requires a parameter" unless
        $main::instanceId = $ARGV[ ++$iArg ];
    $main::instanceId += 0;

    } elsif ( $thisArg eq "--option" ){
    die "--option requires a parameter" unless
        $main::selectedOption = $ARGV[ ++$iArg ];

    if ( ! defined( $main::options{ $main::selectedOption } ) ){
        die  "Unknown option: $main::selectedOption"
    }

    } else {
    die "Unknown argument: $thisArg";

    } # if

} # for

# check usage

if ( $bHelp or ( ! %options ) ){

    print <<EOF
Usage: $0 <options>

Main Options:
--help            : Show this help
--find            : Discover Dell 1600n/1815dn using network broadcast
--listen <p>      : Register and listen for requests from Dell 1600n/1815dn <p>

Sub Options:
--1600n           : Use Dell 1600n-compatible protocol
--1815dn          : Use Dell 1815dn-compatible protocol
--fx200           : Use Ricoh FX200-compatible protocol
--6110mfp         : Use Xerox Phaser 6110MFP-compatible protocol
--clx2160n        : Use Samsung CLX-2160N-compatible protocol
--scx4720fn       : Use Samsung SCX-4720FN-compatible protocol
--scan-dir <d>    : Scanned images will be scanned to this directory
--scan-prefix <p> : Scan filenames will be prefixed with <p>
--debug           : Print lots of debug output
--email <a>       : Email files to address <a> (requires \$main::emailCmd to be set)
--name <n>        : Override client name (appears in scanner display)
--single-session  : Exit after first scan session
--multi-session   : Listen for scan documents until killed
--force-pdf       : Convert all scans to PDF (requires \$main::pdfConvertCmd to be set)
--bind <i>        : Bind to local IP address <i>
--broadcast <i>   : Broadcast address (default: 255.255.255.255) used by --find.

Dell 1600n-specific Options:
--format <f>      : Preferred scan format (tiff, pdf or jpeg)
--resolution <dpi>: Preferred resolution (100/200/300 for tiff/pdf, 200 for jpeg) 

Dell 1815dn-specific Options:
--instance-id <id>: Unique instance id (in case of uid clash)

Other Options:
--option <o>      : Select option <o>.  The following are available:

EOF
;
foreach my  $opt ( sort keys %main::options ){
    print "  $opt = ".$main::options{ $opt }{ "description" }."\n";
}

print <<EOF

$main::softwareName version $main::version ($main::cvsId)
$main::licence

EOF
;
    exit 1;
}

# scan for printers
if ( defined( $options{ "find" } ) ){ 
    BroadcastDiscover(); 
}

# register with scanner
if ( defined( $options{ "listen" } ) ){ 

    $main::printerAddr = $options{"listen" };

    my $sock = OpenUdpPort( $main::printerAddr );

    RegisterWithScanner( $sock );

    my $sel = new IO::Select( $sock );

    while (1) {

    my @ready = $sel->can_read( $main::scanWaitLoopTimeoutSec );

    if ( ! @ready ){
        # no input yet (we hit the timeout) so re-register
        if ( $main::debug ){
            my $now = ctime( time() );
            chop $now;
            print "$now Re-registering with scanner\n";
        }
        RegisterWithScanner( $sock );
        next;
    }

    my $data;
    if ( ! $sock->recv( $data, 1024 ) ){
        usleep( 100 );
        next;
    } 
    ProcessReceivedPacket( \$data, $sock, "udp" );

    } # while

} # if
