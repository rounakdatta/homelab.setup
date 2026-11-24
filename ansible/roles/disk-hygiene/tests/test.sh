#!/usr/bin/env bash
# Tests for files/homelab-disk-hygiene against a fake `k3s crictl` and content
# store: run `bash tests/test.sh` from the role (needs bash, jq, flock).
# The script's fixed paths are rewritten into a temporary directory; nothing
# outside it is read or written.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)/files/homelab-disk-hygiene
fail=0
T=
setup() {
  [ -n "$T" ] && rm -rf "$T"
  T=$(mktemp -d)
  BL="$T/root/var/lib/rancher/k3s/agent/containerd/io.containerd.content.v1.content/blobs/sha256"
  mkdir -p "$T/bin" "$BL" "$T/run" "$T/log"
  sed -e "s#/usr/local/bin/k3s#$T/bin/k3s#g" \
      -e "s#CONTAINERD=/var/lib/rancher#CONTAINERD=$T/root/var/lib/rancher#" \
      -e "s#^p=/\$#p=$T/root#" \
      -e "s#/var/log/homelab-disk-hygiene.log#$T/log/hdh.log#" \
      -e "s#/run/homelab-disk-hygiene#$T/run/hdh#g" \
      -e "s#/etc/default/homelab-disk-hygiene#$T/default#g" \
      -e "s#/proc/pressure/io#$T/pressure#" \
      -e 's#sleep 60#sleep 0#' \
      -e 's#\[ "$(id -u)" = 0 \]#true#' "$SRC" > "$T/hdh"
  chmod +x "$T/hdh"
  cat > "$T/bin/k3s" <<'K'
#!/usr/bin/env bash
D=$(dirname "$0")/..
shift # crictl
[ "$1" = --timeout ] && shift 2
case "$1" in
  ps) n=$(cat "$D/ps.count" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$D/ps.count"
      if [ -f "$D/ps.after" ] && [ "$n" -gt 1 ]; then cat "$D/ps.after"; else cat "$D/ps.json"; fi ;;
  images) cat "$D/images.json" ;;
  rmi) grep -qxF "$2" "$D/rmi.fail" 2>/dev/null && exit 1; echo "$2" >> "$D/rmi.log" ;;
esac
K
  chmod +x "$T/bin/k3s"
  : > "$T/rmi.log"
  printf 'DRY_RUN=0\nMIN_AGE_DAYS=3\nPAUSE_S=0\nMAX_PER_RUN=40\nIO_PRESSURE_MAX=25\n' > "$T/default"
}
conf() { sed -i "s/^$1=.*/$1=$2/" "$T/default"; }
blob() { touch -d "$2" "$BL/$1"; }
ctr() { printf '{"id":"c%s","imageRef":"%s","image":{"image":"%s"},"state":"%s"}' "$RANDOM" "$1" "${2-$1}" "${3:-CONTAINER_RUNNING}"; }
running5() { for _ in 1 2 3 4 5; do printf '%s,' "$(ctr sha256:aaaa)"; done; }
containers() { local IFS=,; echo "{\"containers\":[$*]}"; }
run() { rm -f "$T/ps.count"; out=$("$T/hdh" "$@" 2>&1); rc=$?; }
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; echo "$out" | sed 's/^/     | /'; fail=1; fi; }
removed() { [ "$(sort "$T/rmi.log" | tr '\n' ' ')" = "$*" ]; }

# --- a realistic mix
mix() {
  setup
  cat > "$T/images.json" <<'J'
{"images":[
 {"id":"sha256:aaaa","repoTags":["ghcr.io/x/used:1"],"repoDigests":[],"size":"1000","pinned":false},
 {"id":"sha256:bbbb","repoTags":["ghcr.io/x/old:1"],"repoDigests":["ghcr.io/x/old@sha256:d1"],"size":"2000","pinned":false},
 {"id":"sha256:cccc","repoTags":["ghcr.io/x/fresh:2"],"repoDigests":[],"size":"3000","pinned":false},
 {"id":"sha256:dddd","repoTags":["docker.io/rancher/mirrored-pause:3.6"],"repoDigests":[],"size":"10","pinned":false},
 {"id":"sha256:d0d0","repoTags":["ghcr.io/x/pinned:1"],"repoDigests":[],"size":"11","pinned":true},
 {"id":"sha256:ffff","repoTags":["ghcr.io/x/noblob:1"],"repoDigests":[],"size":"5000","pinned":false},
 {"id":"sha256:9999","repoTags":["docker.io/library/nginx:1.0"],"repoDigests":[],"size":"6000","pinned":false},
 {"id":"sha256:9898","repoTags":["ghcr.io/x/byref:1"],"repoDigests":[],"size":"6100","pinned":false},
 {"id":"sha256:8888","repoTags":[],"repoDigests":["ghcr.io/x/big@sha256:d2"],"size":"9000000000","pinned":false},
 {"id":"sha256:7777","repoTags":["ghcr.io/x/exited:1"],"repoDigests":[],"size":"7000","pinned":false},
 {"id":"sha256:6666","repoTags":["ghcr.io/x/race:1"],"repoDigests":[],"size":"8000","pinned":false},
 {"id":"sha256:5555","repoTags":["ghcr.io/x/oddsize:1"],"repoDigests":[],"size":"n/a","pinned":false}
]}
J
  for b in aaaa bbbb dddd d0d0 9999 9898 8888 7777 6666 5555; do blob $b "10 days ago"; done
  blob cccc "1 hour ago"
  # nginx is found by its tag in image.image only; byref by imageRef only.
  containers "$(running5)$(ctr '' docker.io/library/nginx:1.0)" "$(ctr sha256:9898 '')" "$(ctr sha256:7777 sha256:7777 CONTAINER_EXITED)" > "$T/ps.json"
}
mix; conf DRY_RUN 1; run
check "dry run: exits 0, removes nothing" '[ $rc = 0 ] && [ ! -s "$T/rmi.log" ]'
check "dry run: lists the 3 old unused images, biggest first" '[ "$(echo "$out" | grep -c "^  would remove")" = 3 ] && echo "$out" | grep "^  would remove" | head -1 | grep -q "x/big@" && echo "$out" | grep -q "would remove ghcr.io/x/old:1"'
check "keeps images used by id, by tag only, by imageRef only, by an exited container" '! echo "$out" | grep -qE "would remove (ghcr.io/x/used|docker.io/library/nginx|ghcr.io/x/byref|ghcr.io/x/exited)"'
check "keeps a pinned image, the pause image, a fresh pull, no blob, an odd size" '! echo "$out" | grep -qE "would remove (ghcr.io/x/pinned|.*pause|ghcr.io/x/fresh|ghcr.io/x/noblob|ghcr.io/x/oddsize)"'
check "summary counts" 'echo "$out" | grep -q "^summary: dry run: would remove 3 of 12 images.*kept 4 in use, 2 pinned, 1 pulled under 3 d ago, 2 of unknown age"'
check "summary is logged" 'grep -q "summary: dry run: would remove 3 of 12" "$T/log/hdh.log"'
run --dry-run
check "--dry-run wins over DRY_RUN=0 too" 'conf DRY_RUN 0; run --dry-run; [ $rc = 0 ] && [ ! -s "$T/rmi.log" ]'
# real run; after the first look a pod starts on x/race, which is also old
containers "$(running5)$(ctr '' docker.io/library/nginx:1.0)" "$(ctr sha256:9898 '')" "$(ctr sha256:7777 sha256:7777 CONTAINER_EXITED)" > "$T/ps.json"
containers "$(running5)$(ctr '' docker.io/library/nginx:1.0)" "$(ctr sha256:9898 '')" "$(ctr sha256:7777 sha256:7777 CONTAINER_EXITED)" "$(ctr sha256:6666)" > "$T/ps.after"
run
check "real run: removes big and old; keeps the image a pod just started on" '[ $rc = 0 ] && removed "sha256:8888 sha256:bbbb " && echo "$out" | grep -q "kept ghcr.io/x/race:1.*a container now uses it"'
check "real run: summary" 'echo "$out" | grep -q "^summary: removed 2 of 12 images.*0 failed"'

# --- limits
mix; conf MAX_PER_RUN 1; run
check "MAX_PER_RUN: only the biggest goes, the rest is left" '[ $rc = 0 ] && removed "sha256:8888 " && echo "$out" | grep -q "stopped (reached MAX_PER_RUN) with 2 left for the next run"'
mix; echo "some avg10=80.00 avg60=50.00 avg300=20.00 total=1" > "$T/pressure"; run
check "I/O pressure: waits, then stops without removing" '[ $rc = 0 ] && [ ! -s "$T/rmi.log" ] && echo "$out" | grep -q "stopped (I/O pressure stayed above 25%)"'
mix; echo "some avg10=3.10 avg60=5.00 avg300=2.00 total=1" > "$T/pressure"; run
check "low I/O pressure: goes ahead" '[ $rc = 0 ] && removed "sha256:6666 sha256:8888 sha256:bbbb "'
mix; echo "sha256:8888" > "$T/rmi.fail"; run
check "a failed removal: counted, the run exits 1" '[ $rc = 1 ] && removed "sha256:6666 sha256:bbbb " && echo "$out" | grep -q "1 failed"'
mix; printf 'sha256:8888\nsha256:6666\nsha256:bbbb\n' > "$T/rmi.fail"; run
check "3 failures in a row: stops" '[ $rc = 1 ] && echo "$out" | grep -q "3 failed; stopped (3 removals failed in a row)"'
mix; echo "full avg10=0.00 avg60=0.00 avg300=0.00 total=0" > "$T/pressure"; run
check "a pressure file without a some line: no brake, no noise" '[ $rc = 0 ] && removed "sha256:6666 sha256:8888 sha256:bbbb " && ! echo "$out" | grep -q "integer"'

# --- refusals: nothing removed, and the line says why
refused() { [ "$rc" = 1 ] && [ ! -s "$T/rmi.log" ] && echo "$out" | grep -q "^refused: $1"; }
mix; containers > "$T/ps.json"; run
check "no containers: refuses" 'refused "only 0 containers running"'
mix; containers "$(ctr sha256:aaaa)" "$(ctr sha256:aaaa)" > "$T/ps.json"; run
check "2 running: refuses" 'refused "only 2 containers running"'
mix; echo 'not json' > "$T/ps.json"; run
check "garbage from the runtime: refuses" 'refused "could not list"'
mix; sed 's/"imageRef"/"imgRef"/g; s/"image":{"image"/"img":{"image"/g' "$T/ps.json" > "$T/x" && mv "$T/x" "$T/ps.json"; run
check "renamed JSON keys: refuses instead of judging everything unused" 'refused "7 of 7 running containers have an image not among the images"'
mix; containers "$(running5)$(ctr sha256:abab)" "$(ctr '' docker.io/library/nginx:1.0)" "$(ctr sha256:9898 '')" > "$T/ps.json"; run
check "one running container whose image is gone: goes ahead, and says so" '[ $rc = 0 ] && removed "sha256:6666 sha256:7777 sha256:8888 sha256:bbbb " && echo "$out" | grep -q "1 running containers. images are not listed"'
mix; containers "$(running5)$(ctr sha256:abab)" "$(ctr sha256:abab)" > "$T/ps.json"; run
check "a third of running containers with unlisted images: refuses" 'refused "2 of 7 running containers have an image not among the images"'
mix; for v in 0 x 08 -1; do conf MIN_AGE_DAYS "$v"; run; refused "MIN_AGE_DAYS" || { echo "FAIL MIN_AGE_DAYS=$v accepted"; fail=1; }; done; echo "ok   MIN_AGE_DAYS 0, x, 08, -1: refused"
mix; conf MAX_PER_RUN 0; run
check "MAX_PER_RUN=0: refuses" 'refused "MAX_PER_RUN"'
mix; mv "$T/root/var/lib/rancher/k3s/agent/containerd" "$T/elsewhere"; ln -s "$T/elsewhere" "$T/root/var/lib/rancher/k3s/agent/containerd"; run
check "a symlinked containerd dir: refuses" 'refused ".*containerd is not a plain directory"'
mix; rm "$BL/bbbb" "$BL/8888"; ln -s /etc/hostname "$BL/bbbb"; run
check "a symlinked or missing blob: kept as unknown age" '[ $rc = 0 ] && removed "sha256:6666 " && echo "$out" | grep -q "4 of unknown age"'
mix; exec 8> "$T/run/hdh.lock"; flock -n 8; run; exec 8>&-
check "a second run at once: refuses" 'refused "another run is in progress"'
mix; run --dryrun
check "an unknown argument: usage, exit 2, nothing removed" '[ $rc = 2 ] && [ ! -s "$T/rmi.log" ] && echo "$out" | grep -q "^usage:"'
mix; run -v --dry-run
check "-v --dry-run: usage, nothing removed" '[ $rc = 2 ] && [ ! -s "$T/rmi.log" ]'
# --- an unexpected failure still leaves a line
mix; sed -i 's/^candidates=\$(wc -l/false; candidates=$(wc -l/' "$T/hdh"; run
check "an abort is logged" '[ $rc != 0 ] && [ ! -s "$T/rmi.log" ] && grep -q "aborted: exit 1 before a summary" "$T/log/hdh.log"'

rm -rf "$T"
[ "$fail" = 0 ] && echo "all passed" || echo "FAILED"
exit $fail
