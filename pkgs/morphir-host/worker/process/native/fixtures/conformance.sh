#!/bin/sh
# Fixture worker for the process launcher conformance suite on Linux and
# macOS. It follows the protocol in worker/process/conformance/README.md, like
# the Node fixture worker/process/node/fixtures/worker.mjs.
#
# It runs with an empty environment, so it names every program by its full
# path. Without LANG the shell counts bytes, which Content-Length needs. The
# suite builds each request as {"jsonrpc","id","method","params"}, in that
# order, so `params` is the last member.

grandchild=null
ignore_exit=false
ignore_stdin=false
flood_on_exit=false
while [ $# -gt 0 ]; do
  case $1 in
    --grandchild)
      /bin/sleep 100000 &
      grandchild=$!
      shift
      ;;
    --ignore-exit)
      ignore_exit=true
      shift
      ;;
    --ignore-stdin)
      ignore_stdin=true
      shift
      ;;
    --flood-on-exit)
      flood_on_exit=true
      shift
      ;;
    *) break ;;
  esac
done

reply() {
  printf 'Content-Length: %s\r\n\r\n%s' "${#1}" "$1"
}

result() {
  reply "{\"jsonrpc\":\"2.0\",\"id\":$1,\"result\":$2}"
}

json_string() {
  printf '"%s"' "$(printf '%s' "$1" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g')"
}

json_lines() {
  list=
  while IFS= read -r item; do
    list="$list${list:+,}$(json_string "$item")"
  done
  printf '[%s]' "$list"
}

read_frame() {
  length=
  cr=$(printf '\r')
  while IFS= read -r line; do
    line=${line%"$cr"}
    [ -z "$line" ] && break
    case $line in
      Content-Length:*) length=${line#Content-Length:}; length=${length# } ;;
    esac
  done
  [ -n "$length" ] || return 1
  body=$(/bin/dd bs=1 count="$length" 2>/dev/null)
}

stay() {
  while :; do /bin/sleep 1; done
}

# The status of a file as "device:inode", or nothing.
identity() {
  case $(/usr/bin/uname) in
    Darwin) /usr/bin/stat -L -f '%d:%i' "$1" 2>/dev/null ;;
    *) /usr/bin/stat -L -c '%d:%i' "$1" 2>/dev/null ;;
  esac
}

finish() {
  if [ "$flood_on_exit" = true ]; then
    /usr/bin/head -c 1048576 /dev/zero | /usr/bin/tr '\0' x
    exit 0
  fi
  if [ "$ignore_exit" = true ]; then
    stay
  fi
  exit 0
}

if [ "$ignore_stdin" = true ]; then
  stay
fi

while read_frame; do
  method=$(printf '%s' "$body" | /usr/bin/sed -n 's/.*"method":"\([a-z]*\)".*/\1/p')
  id=$(printf '%s' "$body" | /usr/bin/sed -n 's/.*"id":\([0-9]*\).*/\1/p')
  params=$(printf '%s' "$body" | /usr/bin/sed -n 's/.*"params":\(.*\)}$/\1/p')
  if [ -z "$id" ]; then
    [ "$method" = exit ] && finish
    continue
  fi
  case $method in
    echo)
      result "$id" "${params:-null}"
      ;;
    argv)
      list=
      for argument in "$@"; do
        list="$list${list:+,}$(json_string "$argument")"
      done
      result "$id" "{\"args\":[$list]}"
      ;;
    env)
      # The shell sets PWD, SHLVL and _ itself; every other name came from
      # the host.
      names=$(/usr/bin/env | /usr/bin/sed -n 's/=.*//p' |
        /usr/bin/grep -v -E '^(PWD|SHLVL|_)$' | /usr/bin/sort | json_lines)
      result "$id" "{\"names\":$names}"
      ;;
    cwd)
      entries=$(/bin/ls -A | /usr/bin/wc -l | /usr/bin/tr -d ' ')
      case $(/usr/bin/uname) in
        Darwin) status=$(/usr/bin/stat -f '%Lp %u' .) ;;
        *) status=$(/usr/bin/stat -c '%a %u' .) ;;
      esac
      perm=${status% *}
      owner=${status#* }
      owned=false
      [ "$owner" = "$(/usr/bin/id -u)" ] && owned=true
      result "$id" "{\"entries\":$entries,\"mode\":$((0$perm)),\"ownedByWorker\":$owned}"
      ;;
    fds)
      # The shell lists its own descriptors; each `stat` child inherits them.
      list=
      for path in /dev/fd/*; do
        fd=${path##*/}
        list="$list${list:+,}{\"fd\":$fd,\"id\":\"$(identity "$path")\"}"
      done
      result "$id" "{\"descriptors\":[$list]}"
      ;;
    console)
      printf 'x\n'
      ;;
    pids)
      result "$id" "{\"worker\":$$,\"grandchild\":$grandchild}"
      ;;
    hang)
      ;;
    stderr)
      bytes=$(printf '%s' "$params" | /usr/bin/sed -n 's/.*"bytes":\([0-9]*\).*/\1/p')
      /usr/bin/head -c "$bytes" /dev/zero | /usr/bin/tr '\0' e >&2
      printf '\nstderr end\n' >&2
      result "$id" "{\"written\":$bytes}"
      ;;
    log)
      printf 'worker log line\r\n\r\n'
      ;;
    oversized)
      printf 'Content-Length: 16777217\r\n\r\n'
      ;;
    crash)
      exit 3
      ;;
  esac
done
finish
