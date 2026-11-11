function formatBytes(bytes) {
  var b = Number(bytes) || 0;
  if (b <= 0) return "0 B";
  var units = ["B", "KB", "MB", "GB", "TB"];
  var i = 0;
  while (b >= 1024 && i < units.length - 1) {
    b /= 1024.0;
    i++;
  }
  return (i === 0 ? b.toFixed(0) : b.toFixed(b < 10 ? 1 : 0)) + " " + units[i];
}

function formatSpeed(bytesPerSec) {
  var b = Number(bytesPerSec) || 0;
  if (b <= 0) return "0 B/s";
  var units = ["B/s", "KB/s", "MB/s", "GB/s"];
  var i = 0;
  while (b >= 1024 && i < units.length - 1) {
    b /= 1024.0;
    i++;
  }
  return (i === 0 ? b.toFixed(0) : b.toFixed(b < 10 ? 1 : 0)) + " " + units[i];
}

function formatDate(dateStr, isToday) {
  if (isToday) return "Today";
  if (!dateStr) return "";
  var parts = dateStr.split("-");
  if (parts.length === 3) {
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    var m = parseInt(parts[1], 10) - 1;
    var d = parseInt(parts[2], 10);
    if (m >= 0 && m < 12) {
      return months[m] + " " + d;
    }
  }
  return dateStr;
}
