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

function appEmoji(name) {
  if (!name) return "📱";
  var n = name.toLowerCase();

  // Browsers
  if (n.indexOf("zen") !== -1 || n.indexOf("firefox") !== -1 || n.indexOf("chrome") !== -1 ||
      n.indexOf("chromium") !== -1 || n.indexOf("brave") !== -1 || n.indexOf("edge") !== -1) {
    return "🌐";
  }

  // VPN & Proxies
  if (n.indexOf("v2ray") !== -1 || n.indexOf("clash") !== -1 || n.indexOf("sing-box") !== -1 ||
      n.indexOf("vpn") !== -1 || n.indexOf("wireguard") !== -1 || n.indexOf("tailscale") !== -1) {
    return "⚡";
  }

  // AI & Agents
  if (n.indexOf("antigravity") !== -1 || n.indexOf("codex") !== -1 || n.indexOf("ollama") !== -1 ||
      n.indexOf("claude") !== -1 || n.indexOf("agent") !== -1 || n.indexOf("gemini") !== -1) {
    return "🤖";
  }

  // Development
  if (n.indexOf("code") !== -1 || n.indexOf("nvim") !== -1 || n.indexOf("vim") !== -1 ||
      n.indexOf("language_server") !== -1 || n.indexOf("node") !== -1 || n.indexOf("python") !== -1 ||
      n.indexOf("cargo") !== -1 || n.indexOf("rust") !== -1 || n.indexOf("git") !== -1) {
    return "💻";
  }

  // Package & Download tools
  if (n.indexOf("pacman") !== -1 || n.indexOf("yay") !== -1 || n.indexOf("paru") !== -1 ||
      n.indexOf("curl") !== -1 || n.indexOf("wget") !== -1 || n.indexOf("rclone") !== -1 ||
      n.indexOf("torrent") !== -1 || n.indexOf("npm") !== -1) {
    return "📦";
  }

  // Chat & Communication
  if (n.indexOf("telegram") !== -1 || n.indexOf("discord") !== -1 || n.indexOf("slack") !== -1 ||
      n.indexOf("signal") !== -1 || n.indexOf("element") !== -1 || n.indexOf("whatsapp") !== -1) {
    return "💬";
  }

  // Audio / Media / Voice
  if (n.indexOf("superwhisper") !== -1 || n.indexOf("spotify") !== -1 || n.indexOf("mpv") !== -1 ||
      n.indexOf("vlc") !== -1 || n.indexOf("music") !== -1 || n.indexOf("pipewire") !== -1) {
    return "🎵";
  }

  // System daemons
  if (n.indexOf("systemd") !== -1 || n.indexOf("networkmanager") !== -1 || n.indexOf("avahi") !== -1 ||
      n.indexOf("resolved") !== -1 || n.indexOf("dbus") !== -1) {
    return "⚙️";
  }

  return "🚀";
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
