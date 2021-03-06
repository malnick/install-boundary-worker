#/bin/bash
# Installs the boundary as a service for systemd on linux
# Inspired by https://github.com/robertpeteuil/terraform-installer/blob/master/terraform-install.sh

NAME=$1
BIND_ADDRESS=$2
CONTROLLER_ADDRESS=$3

scriptname=$(basename "$0")

# CHECK DEPENDENCIES
if ! unzip -h 2&> /dev/null; then
  echo "aborting - unzip not installed and required"
  exit 1
fi

if ! systemctl -h 2&> /dev/null; then
  echo "aborting - systemctl not installed and required"
  exit 1
fi

if curl -h 2&> /dev/null; then
  nettool="curl"
elif wget -h 2&> /dev/null; then
  nettool="wget"
else
  echo "aborting - wget or curl not installed and required"
  exit 1
fi

if jq --help 2&> /dev/null; then
  nettool="${nettool}jq"
fi

displayVer() {
  echo -e "${scriptname}"
}

usage() {
  [[ "$1" ]] && echo -e "Download and Install a Boundary worker - Latest Version unless '-i' specified\n"
  echo -e "usage: ${scriptname} [-i VERSION] [-a] [-c] [-h] [-v] [unique-name] [controller-ip] [worker-ip]"
  echo -e ""
  echo -e "example: ${scriptname} -i 0.7.1 my-worker 53.75.200.120 24.253.12.12"
  echo -e ""
  echo -e " Flags"
  echo -e "     -i VERSION\t: specify version to install in format '0.8.0' (OPTIONAL)"
  echo -e "     -a\t\t: automatically use sudo to install to /usr/local/bin"
  echo -e "     -c\t\t: leave binary in working directory (for CI/DevOps use)"
  echo -e "     -h\t\t: help"
  echo -e "     -v\t\t: display ${scriptname} version"
  echo -e ""
  echo -e " Arguments"
  echo -e "     unique-name\t: a unique name for your worker configuration"
  echo -e "     controller-ip\t: the IP address for your worker to reach your controller"
  echo -e "     worker-ip\t: the IP address for your clients to reach your worker"

}

getLatest() {
  # USE NET RETRIEVAL TOOL TO GET LATEST VERSION
  case "${nettool}" in
    # jq installed - parse version from hashicorp website
    wgetjq)
      LATEST_ARR=($(wget -q -O- https://releases.hashicorp.com/index.json 2>/dev/null | jq -r '.boundary.versions[].version' | sort -t. -k 1,1nr -k 2,2nr -k 3,3nr))
      ;;
    curljq)
      LATEST_ARR=($(curl -s https://releases.hashicorp.com/index.json 2>/dev/null | jq -r '.boundary.versions[].version' | sort -t. -k 1,1nr -k 2,2nr -k 3,3nr))
      ;;
    # parse version from github API
    wget)
      LATEST_ARR=($(wget -q -O- https://api.github.com/repos/hashicorp/boundary/releases 2> /dev/null | awk '/tag_name/ {print $2}' | cut -d '"' -f 2 | cut -d 'v' -f 2))
      ;;
    curl)
      LATEST_ARR=($(curl -s https://api.github.com/repos/hashicorp/boundary/releases 2> /dev/null | awk '/tag_name/ {print $2}' | cut -d '"' -f 2 | cut -d 'v' -f 2))
      ;;
  esac

	# make sure latest version isn't beta or rc
	for ver in "${LATEST_ARR[@]}"; do
		if [[ ! $ver =~ beta ]] && [[ ! $ver =~ rc ]] && [[ ! $ver =~ alpha ]]; then
			LATEST="$ver"
			break
		fi
	done
	echo -n "$LATEST"
}

while getopts ":i:achv" arg; do
  case "${arg}" in
    a)  sudoInstall=true;;
    c)  cwdInstall=true;;
    i)  VERSION=${OPTARG};;
    h)  usage x; exit;;
    v)  displayVer; exit;;
    \?) echo -e "Error - Invalid option: $OPTARG"; usage; exit;;
    :)  echo "Error - $OPTARG requires an argument"; usage; exit 1;;
  esac
done
shift $((OPTIND-1))

# POPULATE VARIABLES NEEDED TO CREATE DOWNLOAD URL AND FILENAME
if [[ -z "$VERSION" ]]; then
  VERSION=$(getLatest)
fi
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
if [[ "$OS" == "linux" ]]; then
  PROC=$(lscpu 2> /dev/null | awk '/Architecture/ {if($2 == "x86_64") {print "amd64"; exit} else if($2 ~ /arm/) {print "arm"; exit} else if($2 ~ /aarch64/) {print "arm"; exit} else {print "386"; exit}}')
  if [[ -z $PROC ]]; then
    PROC=$(cat /proc/cpuinfo | awk '/model\ name/ {if($0 ~ /ARM/) {print "arm"; exit}}')
  fi
  if [[ -z $PROC ]]; then
    PROC=$(cat /proc/cpuinfo | awk '/flags/ {if($0 ~ /lm/) {print "amd64"; exit} else {print "386"; exit}}')
  fi
else
  PROC="amd64"
fi
[[ $PROC =~ arm ]] && PROC="arm"  # boundary downloads use "arm" not full arm type

# CREATE FILENAME AND URL FROM GATHERED PARAMETERS
FILENAME="boundary_${VERSION}_${OS}_${PROC}.zip"
LINK="https://releases.hashicorp.com/boundary/${VERSION}/${FILENAME}"
SHALINK="https://releases.hashicorp.com/boundary/${VERSION}/boundary_${VERSION}_SHA256SUMS"

# TEST CALCULATED LINKS
case "${nettool}" in
  wget*)
    LINKVALID=$(wget --spider -S "$LINK" 2>&1 | grep "HTTP/" | awk '{print $2}')
    SHALINKVALID=$(wget --spider -S "$SHALINK" 2>&1 | grep "HTTP/" | awk '{print $2}')
    ;;
  curl*)
    LINKVALID=$(curl -o /dev/null --silent --head --write-out '%{http_code}\n' "$LINK")
    SHALINKVALID=$(curl -o /dev/null --silent --head --write-out '%{http_code}\n' "$SHALINK")
    ;;
esac

# VERIFY LINK VALIDITY
if [[ "$LINKVALID" != 200 ]]; then
  echo -e "Cannot Install - Download URL Invalid"
  echo -e "\nParameters:"
  echo -e "\tVER:\t$VERSION"
  echo -e "\tOS:\t$OS"
  echo -e "\tPROC:\t$PROC"
  echo -e "\tURL:\t$LINK"
  exit 1
fi

# VERIFY SHA LINK VALIDITY
if [[ "$SHALINKVALID" != 200 ]]; then
  echo -e "Cannot Install - URL for Checksum File Invalid"
  echo -e "\tURL:\t$SHALINK"
  exit 1
fi

# DETERMINE DESTINATION
if [[ "$cwdInstall" ]]; then
  BINDIR=$(pwd)
elif [[ -w "/usr/local/bin" ]]; then
  BINDIR="/usr/local/bin"
  CMDPREFIX=""
  STREAMLINED=true
elif [[ "$sudoInstall" ]]; then
  BINDIR="/usr/local/bin"
  CMDPREFIX="sudo "
  STREAMLINED=true
else
  echo -e "boundary Installer\n"
  echo "Specify install directory (a,b or c):"
  echo -en "\t(a) '~/bin'    (b) '/usr/local/bin' as root    (c) abort : "
  read -r -n 1 SELECTION
  echo
  if [ "${SELECTION}" == "a" ] || [ "${SELECTION}" == "A" ]; then
    BINDIR="${HOME}/bin"
    CMDPREFIX=""
  elif [ "${SELECTION}" == "b" ] || [ "${SELECTION}" == "B" ]; then
    BINDIR="/usr/local/bin"
    CMDPREFIX="sudo "
  else
    exit 0
  fi
fi

# CREATE TMPDIR FOR EXTRACTION
if [[ ! "$cwdInstall" ]]; then
  TMPDIR=${TMPDIR:-/tmp}
  UTILTMPDIR="boundary_${VERSION}"

  cd "$TMPDIR" || exit 1
  mkdir -p "$UTILTMPDIR"
  cd "$UTILTMPDIR" || exit 1
fi

# DOWNLOAD ZIP AND CHECKSUM FILES
case "${nettool}" in
  wget*)
    wget -q "$LINK" -O "$FILENAME"
    wget -q "$SHALINK" -O SHAFILE
    ;;
  curl*)
    curl -s -o "$FILENAME" "$LINK"
    curl -s -o SHAFILE "$SHALINK"
    ;;
esac

# VERIFY ZIP CHECKSUM
if shasum -h 2&> /dev/null; then
  expected_sha=$(cat SHAFILE | grep "$FILENAME" | awk '{print $1}')
  download_sha=$(shasum -a 256 "$FILENAME" | cut -d' ' -f1)
  if [ $expected_sha != $download_sha ]; then
    echo "Download Checksum Incorrect"
    echo "Expected: $expected_sha"
    echo "Actual: $download_sha"
    exit 1
  fi
fi

# EXTRACT ZIP
unzip -qq "$FILENAME" || exit 1

# COPY TO DESTINATION
if [[ ! "$cwdInstall" ]]; then
  mkdir -p "${BINDIR}" || exit 1
  ${CMDPREFIX} mv boundary "$BINDIR" || exit 1
  # CLEANUP AND EXIT
  cd "${TMPDIR}" || exit 1
  rm -rf "${UTILTMPDIR}"
  [[ ! "$STREAMLINED" ]] && echo
  echo "boundary Version ${VERSION} installed to ${BINDIR}"
else
  rm -f "$FILENAME" SHAFILE
  echo "boundary Version ${VERSION} downloaded"
fi

# INSTALL BOUNDARY CONFIG FILE 
sudo cat << EOF > /etc/boundary-worker.hcl
listener "tcp" {
	address       = "${BIND_ADDRESS}:9202"
	purpose       = "proxy"
	tls_disable   = false
	tls_cert_file = "${tls_cert_path}"  
	tls_key_file  = "${tls_key_path}"
}

worker {
	public_addr = "${BIND_ADDRESS}"
	name = "boundary-worker-${NAME}"
	description = "A Boundary worker for acme corp"
	controllers = [${CONTROLLER_ADDRESS}]
}

kms "privatekey" {
	purpose = "worker-auth"
	aead_type = "aes-gcm"
	key = "8fZBjCUfN0TzjEGLQldGY4+iE9AkOvCfjh7+p0GtRBQ="
	key_id = "self-managed-worker"
}
EOF

# INSTALL SYSTEMD UNIT
sudo cat << EOF > /etc/systemd/system/boundary-worker.service
[Unit]
Description=boundary worker

[Service]
ExecStart=/usr/local/bin/boundary server -config /etc/boundary-worker.hcl
User=boundary
Group=boundary
LimitMEMLOCK=infinity
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK

[Install]
WantedBy=multi-user.target
EOF

# Add the boundary system user and group to ensure we have a no-login
# user capable of owning and running Boundary
sudo adduser --system --no-create-home --group boundary || true
sudo chown boundary:boundary /etc/boundary-worker.hcl
sudo chown boundary:boundary /usr/local/bin/boundary

sudo chmod 664 /etc/systemd/system/boundary-worker.service
sudo systemctl daemon-reload
sudo systemctl enable boundary-worker
sudo systemctl start boundary-worker
