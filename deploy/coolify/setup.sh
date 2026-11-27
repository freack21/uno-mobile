#!/usr/bin/env bash
# Last Card (uno-mobile) - Coolify deploy helper. Run on the server as root.
#
# Usage: sudo bash setup.sh <command> [options]
#   check     Read-only server report (OS, resources, ports, Coolify)
#   install   Run check, then install Coolify with the official script
#   deploy    Create or update the app in Coolify and deploy it
# Options for deploy:
#   --domain <host>    Public domain (default: uno.refandi.my.id)
#   --branch <name>    Git branch to deploy (default: main)
#   --project <name>   Coolify project (default: DIGISION-DEV)
#   --mirror           Pull base images from mirror.gcr.io (Docker Hub 429)
#   --reset            Forget the saved token and domain and ask again
#   --yes              Don't ask for confirmation
set -euo pipefail

GITHUB_REPO="freack21/uno-mobile"
APP_NAME="uno-mobile"
CONFIG="/etc/uno-mobile/coolify.env"
DEFAULT_DOMAIN="uno.refandi.my.id"
BRANCH="main"
PROJECT="DIGISION-DEV"
COOLIFY_LOCAL="http://127.0.0.1:8000"
NODE_IMAGE="node:22-alpine"
NODE_MIRROR="mirror.gcr.io/library/node:22-alpine"
# Flutter needs room for the SDK and a build.
MIN_DISK_GB=6
MIN_RAM_MB=2000

DOMAIN=""
MIRROR=0
RESET=0
YES=0
WORKDIR=""

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
ok() { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
die() {
  printf '\n\033[31mERROR:\033[0m %s\n' "$*" >&2
  exit 1
}
usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; }

confirm() {
  [[ $YES == 1 ]] && return 0
  local answer
  read -r -p "  $1 [y/N] " answer
  [[ $answer =~ ^[Yy]$ ]]
}

cleanup() {
  if [[ -n $WORKDIR && -d $WORKDIR ]]; then rm -rf "$WORKDIR"; fi
}
trap cleanup EXIT

port_owner() {
  local port=$1
  if command -v ss >/dev/null 2>&1; then
    ss -Hltnp "sport = :$port" 2>/dev/null | sed -n 's/.*users:((\("[^"]*"\).*/\1/p' | head -n1
  elif (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    echo "(in use)"
  fi
}

cmd_check() {
  bold "Server check"
  local os arch cpus ram_mb disk_gb
  # shellcheck source=/dev/null
  os="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
  arch="$(uname -m)"
  cpus="$(nproc 2>/dev/null || echo '?')"
  ram_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
  disk_gb="$(df -Pk / | awk 'NR==2 {print int($4/1024/1024)}')"
  info "OS: ${os:-unknown} ($arch), CPUs: $cpus"
  case $arch in x86_64 | aarch64 | arm64) ok "Architecture $arch is supported" ;; *) warn "Untested architecture $arch" ;; esac
  if ((ram_mb >= MIN_RAM_MB)); then ok "RAM ${ram_mb} MB"; else warn "RAM ${ram_mb} MB: the Flutter build wants ${MIN_RAM_MB} MB+ (add swap)"; fi
  if ((disk_gb >= MIN_DISK_GB)); then ok "Free disk ${disk_gb} GB"; else warn "Free disk ${disk_gb} GB: the Flutter build wants ${MIN_DISK_GB} GB+"; fi

  local port owner
  for port in 80 443 8000 6001 6002; do
    owner="$(port_owner "$port")"
    if [[ -z $owner ]]; then
      info "Port $port: free"
    else
      info "Port $port: $owner"
    fi
  done

  if command -v docker >/dev/null 2>&1; then
    ok "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '(daemon not reachable)')"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx coolify; then
      ok "Coolify is running"
    else
      warn "Coolify container is not running (use: setup.sh install)"
    fi
  else
    warn "Docker is not installed (Coolify's installer adds it)"
  fi
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    info "ufw is active: make sure 80/443 are allowed (not changed by this script)"
  fi
}

cmd_install() {
  cmd_check
  echo
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx coolify; then
    ok "Coolify is already installed. Nothing to do."
    return
  fi
  confirm "Install Coolify with the official script now?" || die "Cancelled."
  curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
}

check_dns() {
  local domain=$1 resolved server_ips headers
  resolved="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ')"
  if [[ -z $resolved ]]; then
    warn "$domain does not resolve yet. Add an A record (proxied) pointing to this server."
    confirm "Continue anyway?" || die "Cancelled."
    return
  fi
  server_ips="$(hostname -I 2>/dev/null) $(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  for ip in $resolved; do
    if [[ " $server_ips " == *" $ip "* ]]; then
      ok "$domain resolves to this server ($ip)"
      return
    fi
  done
  # No -f: Cloudflare answers 5xx while the origin is not ready (P16).
  headers="$(curl -sSI --max-time 10 "https://$domain" 2>/dev/null || true)"
  if grep -qi '^server: cloudflare' <<<"$headers"; then
    ok "$domain is proxied by Cloudflare ($resolved). Make sure the record points to this server."
    return
  fi
  warn "$domain resolves to $resolved, which is not this server."
  confirm "Continue anyway?" || die "Cancelled."
}

cmd_deploy() {
  command -v docker >/dev/null 2>&1 || die "Docker is not installed."
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qx coolify || die "Coolify is not running on this server."

  local saved_token="" saved_domain=""
  if [[ $RESET == 0 && -r $CONFIG ]]; then
    # shellcheck source=/dev/null
    saved_token="$(. "$CONFIG" && echo "${COOLIFY_TOKEN:-}")"
    # shellcheck source=/dev/null
    saved_domain="$(. "$CONFIG" && echo "${APP_DOMAIN:-}")"
  fi

  if [[ -n $saved_token ]]; then
    COOLIFY_TOKEN="$saved_token"
    info "Using the token saved in $CONFIG (--reset to change it)."
  else
    read -r -s -p "  Coolify API token (root permission, input hidden): " COOLIFY_TOKEN
    echo
    [[ -n $COOLIFY_TOKEN ]] || die "A token is required."
  fi
  if [[ -z $DOMAIN ]]; then
    DOMAIN="${saved_domain:-}"
    if [[ -z $DOMAIN ]]; then
      read -r -p "  Domain [$DEFAULT_DOMAIN]: " DOMAIN
      DOMAIN="${DOMAIN:-$DEFAULT_DOMAIN}"
    fi
  fi
  bold "Deploying $GITHUB_REPO ($BRANCH) to https://$DOMAIN in project $PROJECT"
  check_dns "$DOMAIN"

  # Download the provisioner by commit SHA: branch URLs on raw.githubusercontent.com are cached (P3).
  local sha
  sha="$(curl -fsSL -H 'Accept: application/vnd.github.sha' "https://api.github.com/repos/$GITHUB_REPO/commits/$BRANCH")" ||
    die "Branch $BRANCH not found in $GITHUB_REPO."
  WORKDIR="$(mktemp -d)"
  curl -fsSL "https://raw.githubusercontent.com/$GITHUB_REPO/$sha/deploy/coolify/provision.mjs" -o "$WORKDIR/provision.mjs" ||
    die "Could not download provision.mjs for $sha."
  chmod 755 "$WORKDIR"
  chmod 644 "$WORKDIR/provision.mjs"
  info "Provisioner from commit ${sha:0:12}"

  local image=$NODE_IMAGE
  if [[ $MIRROR == 1 ]]; then
    image=$NODE_MIRROR
    export DEBIAN_IMAGE="mirror.gcr.io/library/debian:bookworm-slim"
    export NGINX_IMAGE="mirror.gcr.io/library/nginx:stable-alpine"
  fi
  if ! docker image inspect "$image" >/dev/null 2>&1 && ! docker pull -q "$image" >/dev/null 2>&1; then
    warn "Could not pull $image, trying $NODE_MIRROR"
    image=$NODE_MIRROR
    docker pull -q "$image" >/dev/null || die "Could not pull a Node image."
  fi

  local subnet
  subnet="$(docker network inspect coolify --format '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || true)"
  export COOLIFY_TOKEN COOLIFY_URL="$COOLIFY_LOCAL" APP_DOMAIN="$DOMAIN" GIT_BRANCH="$BRANCH" \
    PROJECT_NAME="$PROJECT" APP_NAME COOLIFY_SOURCE_HINT="$subnet"
  # Values are passed by name so the token never shows up in `ps`.
  docker run --rm --network host -v "$WORKDIR:/w:ro" \
    -e COOLIFY_TOKEN -e COOLIFY_URL -e APP_DOMAIN -e GIT_BRANCH -e PROJECT_NAME -e APP_NAME \
    -e COOLIFY_SOURCE_HINT -e DEBIAN_IMAGE -e NGINX_IMAGE \
    "$image" node /w/provision.mjs || die "Provisioning failed (see the message above). Nothing was saved; the next run asks again."

  (
    umask 077
    mkdir -p "$(dirname "$CONFIG")"
    printf 'COOLIFY_TOKEN=%q\nAPP_DOMAIN=%q\n' "$COOLIFY_TOKEN" "$DOMAIN" >"$CONFIG"
  )
  echo
  ok "Done. Token and domain saved to $CONFIG (root only)."
  info "Next: add the webhook above as COOLIFY_DEPLOY_WEBHOOK in GitHub Actions secrets,"
  info "plus a deploy-only token as COOLIFY_TOKEN, and turn off Coolify's own auto-deploy."
}

main() {
  local cmd=${1:-help}
  shift || true
  while [[ $# -gt 0 ]]; do
    case $1 in
      --domain) DOMAIN=${2:?--domain needs a value}; shift 2 ;;
      --branch) BRANCH=${2:?--branch needs a value}; shift 2 ;;
      --project) PROJECT=${2:?--project needs a value}; shift 2 ;;
      --mirror) MIRROR=1; shift ;;
      --reset) RESET=1; shift ;;
      --yes | -y) YES=1; shift ;;
      -h | --help) cmd=help; shift ;;
      *) die "Unknown option $1 (see: setup.sh help)" ;;
    esac
  done
  case $cmd in
    check) cmd_check ;;
    install | deploy)
      [[ $EUID -eq 0 ]] || die "Run as root: sudo bash setup.sh $cmd"
      "cmd_$cmd"
      ;;
    help | -h | --help) usage ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
