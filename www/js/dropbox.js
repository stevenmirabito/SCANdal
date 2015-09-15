/**
 * CSH Scanner Dropbox
 * Main JavaScript Functions
 *
 * @author	Steven Mirabito smirabito@csh.rit.edu
 * @version	0.1 alpha
 */

var listHash;

function handleQueryString(queryString){
	if(queryString['e'] !== undefined){
		// HTTP error, show the alert
		$('#httpError').slideDown();
		
		// Then hide it after 5 seconds
		setTimeout(function(){
			$('#httpError').slideUp();
		}, 5000);
	}
}

function refreshScanList(){
	// Hide the table and show the spinner with fancy jQuery animations
	$('#scanTableContainer').slideUp('slow', function(){
		$('.spinner').fadeIn('slow');
	
		// Create a request to send to the server
		var request = {'function': 'get_scan_list'};
		var json_request = JSON.stringify(request);
	
		// Do the AJAX request	
		$.ajax({
			url: 'ajax.php',
			method: 'POST',
			data: { request: json_request },
			dataType: 'json'
		}).success(function(response){
			if(response.success === false){
				alert('Server was unable to fetch the latest data. Please try again later. The server said: ' + response.response.error);
			} else {
				// Empty out the scan list before we repopulate it
				$('#scanList').empty();
				
				// See if there weren't any scans returned
				if(response.response.length === 0){
					$("#scanTable").hide();
					$("#noScansAlert").show();
				} else {
					// Add each scan returned to the table
					$.each(response.response, function(index, scan){
						$('#scanList').append('<tr><td>' + scan.timestamp + '</td><td>' + scan.filename + '</td><td><a href="#" class="actionDownload" data-filename="' + scan.filename + '" data-format="tiff"><span class="glyphicon glyphicon-picture"></span> TIFF</a> <a href="#" class="actionDownload" data-filename="' + scan.filename + '" data-format="pdf"><span class="glyphicon glyphicon-file"></span> PDF</a></td><td><a href="#" data-toggle="modal" data-target="#deleteModal" data-filename="' + scan.filename + '"><span class="glyphicon glyphicon-trash"></span></a></td></tr>');
					});

					// Bind action links in the table
					bindActionLinks();
				}
			}

			// Hide the spinner and show the refreshed table with fancy jQuery animations
			$('.spinner').fadeOut('slow', function(){
				$('#scanTableContainer').slideDown('slow');
			});
		}).fail(function(){
        	        alert('Unable to perform Ajax request. Please refresh this page.');
       		});
	});
}

function bindActionLinks(){
	// Bind to download links
        $('.actionDownload').click(function(){
                // Redirect to a PHP script that will force a file download (browser shouldn't actually navigate away from this page)
                window.location.href = 'download.php?f=' + $(this).data('filename') + '&t=' + $(this).data('format');
        });
}

function checkForUpdates(){
	// TODO: Do some kind of Ajax request here
	
		// if (data.hash !== listHash){
		// 		refreshScanList();
		// }
}

$(document).ready(function() {
        // Read the query string
	var queryString = [], hash;
        var q = document.URL.split('?')[1];
        if(q !== undefined){
                q = q.split('&');
                for(var i = 0; i < q.length; i++){
                        hash = q[i].split('=');
                        queryString.push(hash[1]);
                        queryString[hash[0]] = hash[1];
                }
        }

	// Handle anything that needs to happen as a result of a query string parameter
	handleQueryString(queryString);

	// Bind the refresh button to the refresh function
	$('#refresh-btn').click(function(){
		// Call the refresh function
		refreshScanList();
	});
	
	// Set up and handle the delete confirmation modal
	$('#deleteModal').on('show.bs.modal', function(e){
		var filename = $(e.relatedTarget).data('filename');
		var modal = $(this);
		modal.find('#filename').text(filename);
		
		// Bind to the confirm delete button
		// Have to do it here so we know which file to delete
		$('#btnConfirmDelete').click(function(){
			// Create a request to send to the server
		        var request = {'function': 'delete_scan', 'filename': filename};
		        var json_request = JSON.stringify(request);

			// Do the AJAX request to delete the file
			$.ajax({
				url: 'ajax.php',
				method: 'POST',
				data: { request: json_request },
				dataType: 'json'
			}).success(function(response){
				if (response.success === false){
					alert('Server was unable to delete the selected file. The server said: ' + response.response.error);
				} else {
					// File deleted, refresh the scan list
					refreshScanList();
				}
			}).fail(function(){
				alert('Unable to perform Ajax request. Please refresh this page.');
			});
		});
	});
	
	// Invoke the refresh function to load the initial scan list
	refreshScanList();

	// Check for new scans every 10 seconds (refreshes the list if a change occurs)
	setInterval(checkForUpdates, 10000);
});
