/**
 * CSH Scanner Dropbox
 * Main JavaScript Functions
 *
 * @author	Steven Mirabito smirabito@csh.rit.edu
 * @version	0.1 alpha
 */

var listHash;

function refreshScanList(){
	// Hide the table and show the spinner with fancy jQuery animations
	$('#scanTable').slideUp('slow', function(){
		$('.spinner').fadeIn('slow');
	});
	
	// TODO: Do some kind of Ajax request here (simulate some time passing in the meantime)
	window.setTimeout(function(){
		// TODO: Load ajax results into the table here
		//$('#scanList').append('<tr><td>' + data.timestamp + '</td><td>' + data.filename + '</td><td><a href="#" class="actionDownload" data-filename="' + data.filename + '" data-format="tiff"><span class="glyphicon glyphicon-picture"></span> TIFF</a> <a href="#" class="actionDownload" data-filename="' + data.filename + '" data-format="pdf"><span class="glyphicon glyphicon-file"></span> PDF</a></td><td><a href="#" data-toggle="modal" data-target="#deleteModal" data-filename="' + data.filename + '"><span class="glyphicon glyphicon-trash"></span></a></td></tr>');
		
		// Hide the spinner and show the refreshed table with fancy jQuery animations
		$('.spinner').fadeOut('slow', function(){
			$('#scanTable').slideDown('slow');
		});
	}, 2000);
}

function checkForUpdates(){
	// TODO: Do some kind of Ajax request here
	
		// if (data.hash !== listHash){
		// 		refreshScanList();
		// }
}

$(document).ready(function() {
	// Bind the refresh button to the refresh function
	$('#refresh-btn').click(function(){
		// Call the refresh function
		refreshScanList();
	});
	
	// Bind to download links
	$('.actionDownload').click(function(){
		// Redirect to a PHP script that will force a file download (browser should't actually navigate away from this page)
		location.replace('download.php?f=' + $(this).data('filename') + '&t=' + $(this).data('format'));
	});
	
	// Set up and handle the delete confirmation modal
	$('#deleteModal').on('show.bs.modal', function(e){
		var filename = $(e.relatedTarget).data('filename');
		var modal = $(this);
		modal.find('#filename').text(filename);
		
		// Bind to the confirm delete button
		// Have to do it here so we know which file to delete
		$('#btnConfirmDelete').click(function(){
			// TODO: Do some kind of Ajax request here
			console.log(filename);
			
				refreshScanList();
		});
	});
	
	// Invoke the refresh function to load the initial scan list
	refreshScanList();
	
	// Check for new scans every 10 seconds (refreshes the list if a change occurs)
	setInterval(checkForUpdates, 10000);
});