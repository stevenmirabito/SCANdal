<?php
	/**
	 * CSH Scanner Dropbox
	 * Ajax Handler
	 *
	 * @author	Steven Mirabito smirabito@csh.rit.edu
	 * @version	0.1 alpha
	 */

	//--- Configuration ---//
	$scan_dir = '/tmp/scans'; // Where scans are stored

	//--- Helper Functions ---//
	function handle_query_string($qs){
		// Set up some variables
		$filename = $qs['f'];
		$format = $qs['t'];

		 // Build path to requested file
                if($format === 'tiff'){
                        $path = $GLOBALS['scan_dir'].'/'.$filename.'.tiff';
                } elseif($format === 'pdf'){
                        $path =  $GLOBALS['scan_dir'].'/'.$filename.'.pdf';
                } else {
                        die('Invalid request.');
                }

		// Check to make sure the file exists
		if(file_exists($path)){
			return $path;
		} else {
			return false;
		}
	}

	function process_download($path){
		// Set up the headers
		header('Content-Type: application/octet-stream');
		header('Content-Transfer-Encoding: Binary');
		header('Content-disposition: attachment; filename="' . basename($path) . '"');

		// Start the download
		readfile($path);
	}

	//--- Main ---//

	// Make sure we have a valid GET request to work with
	$is_f = isset($_GET['f']);
	$is_t = isset($_GET['t']);

	if(!$is_f || !$is_t){
		die('Invalid request.');
	} else {
		$path = handle_query_string($_GET);
		
		if($path !== false){
			process_download($path);
		} else {
			die('File not found.');
		}
	}
?>
