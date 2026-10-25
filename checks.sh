#!/bin/bash
# Daily morning checks for live apps.
# Writes morningchecks/<app>/<date>.md and morningchecks/<date>.md, then pushes.
set -uo pipefail
cd "$(dirname "$0")" || exit 1

DATE=$(date +%Y-%m-%d)
STAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
OK=0
BAD=0
ROWS=""

tls_days() {
  local host end epoch
  host="$1"
  end=$(echo | openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  if [ -z "$end" ]; then echo "n/a"; return; fi
  epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$end" +%s 2>/dev/null)
  if [ -z "$epoch" ]; then echo "n/a"; return; fi
  echo $(( (epoch - $(date +%s)) / 86400 ))
}

check() {
  local app url mode code t days host
  app="$1"; url="$2"; mode="$3"
  mkdir -p "morningchecks/$app"
  if [ "$mode" = "disabled" ]; then
    printf '# %s - %s\n\nStatus: **disabled by request**\n\nChecked: %s\n' "$app" "$DATE" "$STAMP" > "morningchecks/$app/$DATE.md"
    ROWS="$ROWS| $app | disabled | - | - |"$'\n'
    return
  fi
  host=$(printf '%s' "$url" | sed 's|https://||; s|/.*||')
  read -r code t < <(curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time 15 "$url")
  days=$(tls_days "$host")
  {
    printf '# %s - %s\n\n' "$app" "$DATE"
    printf '| check | result |\n|---|---|\n'
    printf '| URL | %s |\n' "$url"
    printf '| HTTP status | %s |\n' "$code"
    printf '| Response time | %ss |\n' "$t"
    printf '| TLS days remaining | %s |\n' "$days"
    printf '| Checked at | %s |\n' "$STAMP"
  } > "morningchecks/$app/$DATE.md"
  if [ "$code" = "200" ]; then OK=$((OK+1)); else BAD=$((BAD+1)); fi
  ROWS="$ROWS| $app | $code | $t s | $days |"$'\n'
}

check "fx-scalper"     "https://www.fx-scalper.com/"                  live
check "healthhive"     "https://healthhive.fx-scalper.com/api/health" live
check "kushconnect"    "https://kushconnect.fx-scalper.com/"          live
check "influencersync" "https://influencersync.fx-scalper.com/"       live
check "quality-drive"  "https://quality-drive.fx-scalper.com/"        live
check "aerodoc"        "https://aerodoc.fx-scalper.com/"              disabled
check "eduapply"       "https://eduapply.fx-scalper.com/"             disabled

{
  printf '# Morning checks - %s\n\n' "$DATE"
  printf 'Run at %s - %s ok, %s failing\n\n' "$STAMP" "$OK" "$BAD"
  printf '| app | status | time | tls_days |\n|---|---|---|---|\n'
  printf '%s' "$ROWS"
} > "morningchecks/$DATE.md"

git add -A
git -c user.name="PhemeloDev" -c user.email="32327692+PhemeloDev@users.noreply.github.com" commit -q -m "chore(checks): morning status $DATE" || echo "no changes"
git push origin main >/dev/null 2>&1 && echo "pushed $DATE ($OK ok, $BAD failing)" || echo "push failed"
