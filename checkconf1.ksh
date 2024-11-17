#!/usr/bin/ksh
#
# Script : checkconf.ksh
# Compare database configuration keys with file keys (asc/fcv)
# Usage  : checkconf.ksh [-help|-h] [-write|-w] <directory_or_file>
#

# Exit with an error message
die() {
  print >&2 "$*"
  exit 1
}

# Print a timestamp with a message
stamp() {
  date "+%d-%m-%Y %H:%M:%S ${*}"
}

# Display usage information
show_usage() {
  cat <<EOF
Usage: $(basename $0) [-help|-h] [-write|-w] <directory_or_file>
  -help                      Display this help screen
  -write                     Rewrite keys from tbtoasc in ./Repport/Write
  <directory_or_file>        Directory or file to check
EOF
  exit 0
}

# Initialize necessary paths and directories
initialize_paths() {
  BasePath="$(cd "$(dirname "$(readlink -f "$0")")"; pwd)"
  DataPath="${BasePath}/Files"
  DataPathRepport="${BasePath}/Repport"
  DataPathRepportTmp="${DataPathRepport}/Files"
  DataPathRepportWrite="${DataPathRepport}/Write"
  fileskeys_csv="${DataPathRepport}/fileskeys.csv"

  mkdir -p "$DataPath" "$DataPathRepport" "$DataPathRepportTmp" "$DataPathRepportWrite"
}

# Verify the availability of required utilities
check_utilities() {
  for utility in gzip asctotb tbtoasc compare_stdtbl colordiff; do
    if ! command -v "$utility" >/dev/null 2>&1; then
      die "Required utility '$utility' not found."
    fi
  done
}

# Process to compare an ASC file
process_asc_file() {
  typeset input_file="$1"

  # Validate input file
  if [[ ! -f "$input_file" ]]; then
    echo "Error: File '$input_file' not found." >&2
    return 1
  fi

  # Prepare data paths
  typeset txt_file="$DataPath/fileFromTxtfile.asc"
  typeset keys_file="$DataPath/keys.txt"
  typeset header_file="$DataPath/commentHeader.txt"
  typeset tbtoasc_file="$DataPath/fileFromTbtoasc.asc"
  typeset tbtoasc_error_file="$DataPath/fileFromTbtoascError.asc"

  # Ensure no confirmation is needed for overwrites and clear previous files
  > "$txt_file"
  > "$keys_file"
  > "$header_file"
  > "$tbtoasc_file"
  > "$tbtoasc_error_file"

  # Copy the input file to the working directory
  cp -f "$input_file" "$txt_file"

  # Extract keys from the input file
  awk '!/^[[:space:]]+.*/ {print}' "$txt_file" | \
    awk 'match($1,/^\[(.*)\]$/,output) {print output[1]}' > "$keys_file"

  # Generate and add a comment header to the tbtoasc_file
  # The header includes a timestamp, a description of the process, and the source file's name
  awk '/^!/' "$txt_file" > "$header_file"
  {
    cat "$header_file"
    echo "!"
    echo "!  $(stamp)  :  checkconf  :  rewrite of key values by tbtoasc - $(basename "$txt_file")"
    echo "!"
  } > "$tbtoasc_file"

  # Rewrite and validate keys
  while read -r key; do
    tbtoasc -e "$key" >> "$tbtoasc_file" 2>>"$tbtoasc_error_file"

    # If an error is detected, remove the key and its associated content block
    if grep -q '^Error' "$tbtoasc_error_file"; then
      sed -i "/$key/,/\\\\/d" "$txt_file"
    fi
  done < "$keys_file"

  # Compare the tbtoasc and txt files
  compare_files "$tbtoasc_file" "$txt_file"
}

# Process to compare an FCV file
process_fcv_file() {
  # Check if the input file exists
  typeset file="$1"
  if [[ ! -f "$file" ]]; then
    echo "Error: The file '$file' does not exist."
    return 1
  fi
  
  # Initialize variables
  typeset txt_file="$DataPath/fileFromTxtfile.fcv"
  typeset stdcomp_file="$DataPath/fileFromStdcomp.fcv"
  typeset keys_file="$DataPath/keys.txt"
  typeset header_file="$DataPath/commentHeader.txt"
  
  # Clear or create the output files to avoid appending to old data
  > "$txt_file"
  > "$stdcomp_file"
  > "$keys_file"
  > "$header_file"

  # Generate the fileFromTxtfile.fcv using stdcomp and filter out unnecessary lines
  stdcomp -A "$file" | grep -Ev "?compiled|SVN iden|SCCS ident" > "$txt_file"
  
  # Create a list of keys from the file name, replacing underscores with hashes
  echo "$(basename "$file" .fcv)" | tr '_' '#' > "$keys_file"

  # Process each key and append the result to the stdcomp_file, filtering out unnecessary lines
  while read -r key; do
    tbtoasc -e "$key" | grep -Ev "?compiled|SVN iden|SCCS ident" >> "$stdcomp_file"
  done < "$keys_file"

  # Compare the stdcomp_file with the original file to validate the changes
  compare_files "$stdcomp_file" "$txt_file"
}
# Process a directory of ASC or FCV files
process_directory() {
  typeset dir="$1"
  typeset temp_tar="${DataPathRepport}/directory.tar.gz"
  
  tar -czf "$temp_tar" -C "$(dirname "$dir")" "$(basename "$dir")"
  for file in "$dir"/*.asc "$dir"/*.fcv; do
    [ -f "$file" ] || continue
    [ "${file##*.}" = "asc" ] && process_asc_file "$file" || process_fcv_file "$file"
  done
}

# Compare two files and display results
compare_files() {
  typeset file1="$1"
  typeset file2="$2"

  compare_stdtbl "$file1" "$file2" > "$DataPath/compareMessage.txt" 2> "$DataPath/compareError.txt"

  if [ -s "$DataPath/compareError.txt" ]; then
    die "Error during comparison. Check $DataPath/compareError.txt for details."
  elif [ -s "$DataPath/compareMessage.txt" ]; then
    print "Files differ. Check $DataPath/compareMessage.txt for details."
    print ""
    print " =============================== "
    print " ===> The file is DIFFERENT <=== "
    print " =============================== "
    print ${directoryOrFile}" is not same from tbtoasc."
    print ""
    more ${compareMessage}
    print ""
    print " For more details :"
    print " ---> See "${fileFromTbtoasc_asc}
    print " ---> See "${keys}
    print ""
  else
    print "Files match."
    print ""
    print " ======================== "
    print " ===> The file is OK <=== "
    print " ======================== "
    print ${directoryOrFile}" is same as from tbtoasc."
    print ""
    print " For more details :"
    print " ---> See "${fileFromTbtoasc_asc}
    print " ---> See "${keys}
    print ""
  fi
}

# Main script logic
main() {
  typeset directoryOrFile=""
  typeset Option_Help=false
  typeset Option_Write=false

  # Parse arguments
  while [ $# -ge 1 ]; do
    case "$1" in
      -h|-help) Option_Help=true ;;
      -w|-write) Option_Write=true ;;
      *) directoryOrFile="$1" ;;
    esac
    shift
  done

  $Option_Help && show_usage
  [ -z "$directoryOrFile" ] && die "$USAGE"

  initialize_paths
  check_utilities

  # Determine the type of input and process accordingly
  if [ -f "$directoryOrFile" ]; then
    case "${directoryOrFile##*.}" in
      asc) process_asc_file "$directoryOrFile" ;;
      fcv) process_fcv_file "$directoryOrFile" ;;
      *) die "Unsupported file type: $directoryOrFile" ;;
    esac
  elif [ -d "$directoryOrFile" ]; then
    process_directory "$directoryOrFile"
  else
    die "Invalid input: $directoryOrFile is neither a file nor a directory."
  fi
}

main "$@"
