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

	function json_response($success, $data){
		if(!isset($data)){
			$response = array('success' => $success);
			return json_encode($response);
		} else {
			$response = array('success' => $success, 'response' => $data);
			return json_encode($response);
		}
	}

	function invalid_request(){
		$response = array('error' => 'Invalid request.');
		$response_encoded = json_response(false, $response);
		die($response_encoded);
	}

	//--- Main Request Handler ---//

	function parse_request($rawRequest){
		// First of all, is the request a valid JSON object?
		$request = json_decode($rawRequest, true);

		if($request === null){
			// Invalid request, error out
			invalid_request();
		}

		// Decoding succeeded, continue
		if(isset($request['function'])){
			switch($request['function']){
				case 'get_scan_list':
					return get_scan_list($request);
					break;
				case 'get_list_hash':
					return get_list_hash($request);
					break;
				case 'delete_scan':
					return delete_scan($request);
					break;
				default:
					invalid_request();
					break;
			}
		} else {
			invalid_request();
		}
	}

	//--- Request-Specific Functions ---//

	function get_scan_list($request){
		// Get an array of the files in the scan directory
		$files = glob($GLOBALS['scan_dir'].'/*.tif');

		// Set up our response array
		$scanList = array();

		// Add them to our response array
		foreach ($files as $file) {
			// Extract base file name from full path
			$file_info = pathinfo($file);
			$filename = $file_info['filename'];

			// Get the (formatted) file timestamp
			$timestamp = date('n/j/Y g:i A', filemtime($file));
			
			// Build the response array
			$scanList[] = array('timestamp' => $timestamp, 'filename' => $filename);
		}

		// Build the response
		$response = array('scanList' => $scanList, 'hash' => get_list_hash($request));
		
		return $response;
	}

	function get_list_hash($request){
		// Get an array of the files in the scan directory
        $files = glob($GLOBALS['scan_dir'].'/*.tif');

		// Serialize, then hash the $files array
		$hash = sha1(serialize($files));

		// Set up and return the $response array
		$response = array('hash' => $hash);
		return $response;
	}

	function delete_scan($request){
		// Check to see if we were given a filename
		if(!isset($request['filename'])){
			invalid_request();
		}

		// Build path to the files
		$path_tiff = $GLOBALS['scan_dir'].'/'.$request['filename'].'.tif';
		$path_pdf =  $GLOBALS['scan_dir'].'/'.$request['filename'].'.pdf';

		// Check to see if the files exist, and, if so, delete them
		if(file_exists($path_tiff)){
			unlink($path_tiff);
		}

		if(file_exists($path_pdf)){
			unlink($path_pdf);
		}

		// Return success
		return true;
	}

	//--- Start Processing ---//

	// Make sure we have a POST request to work with
	if(!isset($_POST['request'])){
		invalid_request();
	}

	// Parse the request and get a response to send back
	$response = parse_request($_POST['request']);

	// Figure out what kind of response we're dealing with and handle it appropriately
	if(is_bool($response)){
		echo json_response(true, $response);
	} elseif(is_array($response)){
		echo json_response(true, $response);
	} else {
		echo json_response(false, array('error' => 'Internal error.'));
	}

?>
