#!/bin/sh
# Fixture worker for the native process launcher tests.
#
# It runs with an empty environment, so it names every program by its full
# path. The first argument selects the behaviour; frames on stdout use
# Content-Length framing with ASCII bodies.
#
#   echo         answer each frame with the same body until stdin ends
#   report       write the arguments, environment, working directory, its
#                files and open descriptors 3 to 9 to stderr, then echo
#   grandchild   start a grandchild, answer {"grandchild":PID}, then echo
#   orphan       start a grandchild that keeps stdout open, answer
#                {"grandchild":PID}, then exit 0 at once
#   stubborn     ignore SIGTERM, SIGHUP, SIGINT and the end of stdin, start
#                a grandchild, answer {"grandchild":PID}, and never exit
#   flood        write 10 MiB and then TAIL-END to stderr, then echo
#   junk         write text that is not a frame to stdout, then wait
#   eof          answer {"ready":true}, wait for the end of stdin, write
#                "eof" to stderr, exit 0
#   exit CODE    exit with CODE at once

reply() {
  printf 'Content-Length: %s\r\n\r\n%s' "${#1}" "$1"
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

echo_frames() {
  while read_frame; do
    reply "$body"
  done
}

mode=$1
[ $# -gt 0 ] && shift

case $mode in
  echo)
    echo_frames
    ;;
  report)
    for argument in "$@"; do printf '[%s]' "$argument" >&2; done
    # The shell itself sets PWD, SHLVL and _; anything else came from the host.
    printf '\nenv:%s|\n' "$(/usr/bin/env | /usr/bin/grep -v -E '^(PWD|SHLVL|_)=')" >&2
    printf 'cwd:%s\n' "$(pwd)" >&2
    printf 'files:%s|\n' "$(/bin/ls -A)" >&2
    open=
    for fd in 3 4 5 6 7 8 9; do
      # A subshell: dash exits when a redirection of a special builtin fails.
      if ( : <&"$fd" ) 2>/dev/null || ( : >&"$fd" ) 2>/dev/null; then
        open="$open $fd"
      fi
    done
    printf 'fds:%s|\n' "$open" >&2
    echo_frames
    ;;
  grandchild)
    /bin/sleep 300 &
    reply "{\"grandchild\":$!}"
    echo_frames
    ;;
  orphan)
    /bin/sleep 300 &
    reply "{\"grandchild\":$!}"
    exit 0
    ;;
  stubborn)
    trap '' TERM HUP INT
    /bin/sleep 300 &
    reply "{\"grandchild\":$!}"
    while :; do /bin/sleep 1; done
    ;;
  flood)
    /usr/bin/head -c 10485760 /dev/zero | /usr/bin/tr '\0' 'x' >&2
    printf 'TAIL-END' >&2
    echo_frames
    ;;
  junk)
    printf 'not a frame\r\n\r\n'
    while :; do /bin/sleep 1; done
    ;;
  eof)
    reply '{"ready":true}'
    /bin/cat >/dev/null
    printf 'eof\n' >&2
    ;;
  exit)
    exit "$1"
    ;;
  *)
    printf 'unknown mode: %s\n' "$mode" >&2
    exit 64
    ;;
esac
