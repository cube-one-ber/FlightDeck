.pragma library

// "T-02:14:09", "T-3d 04:12", or "T+00:01:12" once T-0 has passed.
// Mirrors text::countdown in the daemon.
function format(t0Ms, nowMs) {
  var secs = Math.floor((t0Ms - nowMs) / 1000)
  var sign = secs >= 0 ? "-" : "+"
  var s = Math.abs(secs)
  var d = Math.floor(s / 86400), h = Math.floor(s / 3600) % 24, m = Math.floor(s / 60) % 60
  function two(n) { return n < 10 ? "0" + n : "" + n }
  if (d > 0) return "T" + sign + d + "d " + two(h) + ":" + two(m)
  return "T" + sign + two(h) + ":" + two(m) + ":" + two(s % 60)
}

// "4m ago", "2h ago" for freshness tooltips.
function ago(iso, nowMs) {
  if (!iso) return "never"
  var mins = Math.max(0, Math.round((nowMs - Date.parse(iso)) / 60000))
  if (mins < 60) return mins + "m ago"
  if (mins < 2880) return Math.round(mins / 60) + "h ago"
  return Math.round(mins / 1440) + "d ago"
}

// True once a `stale_after` deadline has passed, or when there is none (never fetched).
function stale(staleAfter, nowMs) {
    return !staleAfter || Date.parse(staleAfter) < nowMs
}

// Coarse countdown for lists: "T-45m", "T-3h 20m", "T-2d 4h", "T+12m".
function short(t0Ms, nowMs) {
    var mins = Math.round((t0Ms - nowMs) / 60000)
    var sign = mins >= 0 ? "-" : "+"
    var m = Math.abs(mins), d = Math.floor(m / 1440), h = Math.floor(m / 60) % 24
    if (d > 0) return "T" + sign + d + "d" + (h ? " " + h + "h" : "")
    if (m >= 60) return "T" + sign + Math.floor(m / 60) + "h" + (m % 60 ? " " + (m % 60) + "m" : "")
    return "T" + sign + m + "m"
}
