# Filter hostnames and URLs by target scope and blocklist.
# Variables: scope_root, blockfile, mode ("host" or "url")

BEGIN {
  scope_root = tolower(scope_root)
  mode = (mode == "" ? "host" : mode)
  while ((getline bl < blockfile) > 0) {
    sub(/#.*/, "", bl)
    gsub(/^[ \t]+|[ \t]+$/, "", bl)
    if (bl == "") continue
    deny[tolower(bl)] = 1
  }
  close(blockfile)
}

function strip_host(name,    p) {
  sub(/^[ \t]+|[ \t]+$/, "", name)
  sub(/^https?:\/\//, "", name)
  p = index(name, "/")
  if (p > 0) name = substr(name, 1, p - 1)
  p = index(name, ":")
  if (p > 0) name = substr(name, 1, p - 1)
  p = index(name, "?")
  if (p > 0) name = substr(name, 1, p - 1)
  return name
}

function url_host(url) {
  return strip_host(url)
}

function is_blocked(h,    n, d, suffix) {
  n = tolower(h)
  if (n in deny) return 1
  for (d in deny) {
    suffix = "." d
    if (length(n) > length(suffix) && substr(n, length(n) - length(suffix) + 1) == suffix)
      return 1
  }
  return 0
}

function in_scope(h,    n, suffix) {
  n = tolower(h)
  if (n == scope_root) return 1
  suffix = "." scope_root
  if (length(n) > length(suffix) && substr(n, length(n) - length(suffix) + 1) == suffix)
    return 1
  return 0
}

function keep(h) {
  return in_scope(h) && !is_blocked(h)
}

{
  line = $0
  gsub(/\r$/, "", line)
  if (line ~ /^[[:space:]]*$/ || line ~ /^[[:space:]]*#/) next

  if (mode == "url") {
    host = url_host(line)
  } else {
    host = strip_host(line)
  }

  if (host == "" || !keep(host)) next
  print line
}
