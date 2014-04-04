$(document).ready(function(){
$(function(){
$("#sortable").tablesorter();
});
});

$('#server-status').hide();

function checkhealth() {
  $.ajax({
    type: 'GET',
      url: '/health',
      dataType: 'json',
      success: function(data, textStatus, XMLHttpRequest) {
        if (data.length > 0) {
          message = "Health check failed for " + data.join(', ');
          $('#server-status-message').text(message)
          $('#server-status').show();
        } else {
          $('#server-status').hide();
        }
      },
      error: function(XMLHttpRequest, textStatus, errorThrown) {
        console.log('Failure getting health check');
      }
  });
}

checkhealth();
window.setInterval(checkhealth, 10000);
