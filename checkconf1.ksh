#!/usr/bin/ksh
#
# Script : checkconf.ksh - Compare database configuration keys with file keys (asc/fcv)
# Usage  : checkconf.ksh [-help|-h] [-write|-w] <directory_or_file>
#

die() {
  print >&2 "$*"
  exit 1
}

stamp() {
  date "+%d-%m-%Y %H:%M:%S ${*}"
}

USAGE="Usage: $(basename ${0}) [-help|-h] [-write|-w] <directory_or_file>"

if [ $# -eq 0 ]; then
  die "${USAGE}"
fi

directoryOrFile=""
Option_Help=false
Option_Write=false

# Parse command-line arguments
while [ $# -ge 1 ]; do
  case "$1" in
    -h|-help) Option_Help=true ;;
    -w|-write) Option_Write=true ;;
    *) 
      if [ -z "$directoryOrFile" ]; then
        directoryOrFile="$1"
      else
        die "${USAGE}"
      fi
      ;;
  esac
  shift
done

if $Option_Help; then
  cat <<EOF
Usage: $(basename ${0}) [-help|-h] [-write|-w] <directory_or_file>
  -help                      Display this help screen
  -write                     Rewrite keys from tbtoasc in ./Repport/Write
  <directory_or_file>        Directory or file to check
EOF
  exit 0
fi

# Initialization of paths
BasePath="$(cd "$(dirname "$(readlink -f "$0")")"; pwd)"
DataPath="${BasePath}/Files"
DataPathRepport="${BasePath}/Repport"
DataPathRepportTmp="${DataPathRepport}/Files"
DataPathRepportWrite="${DataPathRepport}/Write"
fileskeys_csv="${DataPathRepport}/fileskeys.csv"

# Ensure necessary directories exist
mkdir -p "$DataPath" "$DataPathRepport" "$DataPathRepportTmp" "$DataPathRepportWrite"

# Check required utilities
for utility in gzip asctotb tbtoasc compare_stdtbl colordiff; do
  if ! command -v "$utility" >/dev/null 2>&1; then
    die "Required utility '$utility' not found."
  fi
done

# Resolve absolute path
directoryOrFile="$(readlink -f "$directoryOrFile")"

# Processing file based on extension
fileName="$(basename "$directoryOrFile")"
fileExt="${fileName##*.}"
filePath="$(dirname "$directoryOrFile")"

# Process ASC file
if [[ "$fileExt" = "asc" ]]; then
  # Extract keys
  awk '!/^[[:space:]]+.*/ {print}' "$directoryOrFile" | \
    awk 'match($1,/^\[(.*)\]$/,output) {print output[1]}' > "$DataPath/keys.txt"

  # Create a header for the rewritten file
  awk '/^!/' "$directoryOrFile" > "$DataPath/commentHeader.txt"
  {
    cat "$DataPath/commentHeader.txt"
    echo "!"
    echo "!  $(stamp)  :  checkconf  :  rewrite of key values by tbtoasc - $fileName"
    echo "!"
  } > "$DataPath/fileFromTbtoasc.asc"

  # Compare and validate keys
  echo "$(wc -l < "$DataPath/keys.txt") keys ... processing"
  while read -r key; do
    tbtoasc -e "$key" >> "$DataPath/fileFromTbtoasc.asc" 2>>"$DataPath/fileFromTbtoascTemp.asc"
    if grep -q '^Error' "$DataPath/fileFromTbtoascTemp.asc"; then
      sed -i "/$key/,/\\/d" "$directoryOrFile"
    fi
  done < "$DataPath/keys.txt"

  # Compare the original and rewritten files
  compare_stdtbl "$DataPath/fileFromTbtoasc.asc" "$directoryOrFile" > "$DataPath/compareMessage.txt" 2> "$DataPath/compareError.txt"

  if [ -s "$DataPath/compareError.txt" ]; then
    die "Error during comparison. Check '$DataPath/compareError.txt' for details."
  elif [ -s "$DataPath/compareMessage.txt" ]; then
    print "File differs from database values. Details in $DataPath/compareMessage.txt"
  else
    print "File matches the database values."
  fi
fi

# Handle FCV and directories similarly...
