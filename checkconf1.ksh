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
  base_path="$(cd "$(dirname "$(readlink -f "$0")")"; pwd)"
  files_directory_path="${base_path}/files"
  report_directory_path="${base_path}/repport"
  report_files_directory_path="${report_directory_path}/files"
  rewritten_asc_fcv_dir_path="${report_directory_path}/rewritten_asc_fcv_dir"

  mkdir -p "$files_directory_path" "$report_directory_path" "$report_files_directory_path" "$rewritten_asc_fcv_dir_path"
}

# Verify the availability of required utilities
check_utilities() {
  for utility in gzip asctotb tbtoasc compare_stdtbl colordiff; do
    if ! command -v "$utility" >/dev/null 2>&1; then
      die "Required utility '$utility' not found."
    fi
  done
  # Use color to compare
  export CMPSTDTBL_DIFF=colordiff
}

####################################################
#                 ASC FILE                         #
####################################################

# Process to compare an ASC file
process_asc_file() {
  typeset input_file="$1"

  # Validate input file
  if [[ ! -f "$input_file" ]]; then
    echo "Error: File '$input_file' not found." >&2
    return 1
  fi

  # Prepare data paths
  typeset txt_file="$files_directory_path/fileFromTxtfile.asc"
  typeset keys_file="$files_directory_path/keys.txt"
  typeset header_file="$files_directory_path/commentHeader.txt"
  typeset tbtoasc_file="$files_directory_path/fileFromTbtoasc.asc"
  typeset tbtoasc_error_file="$files_directory_path/fileFromTbtoascError.asc"

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

	# delete carriage return after '=' when there is data except comment lines
	sed -ri '/^\!.*=$/ s/=//g' $txt_file
	sed -ri ':a;N;$!ba;s/=\n([^\\])/=\1/g' $txt_file
	sed -ri ':a;N;$!ba;s/=\n([^\\])/=\1/g' $tbtoasc_file

  # Compare the tbtoasc and txt files
  compare_files "$tbtoasc_file" "$txt_file"
}

####################################################
#                 FCV FILE                         #
####################################################

# Process to compare an FCV file
process_fcv_file() {
  # Check if the input file exists
  typeset input_file="$1"
  if [[ ! -f "$input_file" ]]; then
    echo "Error: The file '$input_file' does not exist."
    return 1
  fi
  
  # Initialize variables
  typeset txt_file="$files_directory_path/fileFromTxtfile.fcv"
  typeset stdcomp_file="$files_directory_path/fileFromStdcomp.fcv"
  typeset keys_file="$files_directory_path/keys.txt"
  
  # Clear or create the output files to avoid appending to old data
  > "$txt_file"
  > "$stdcomp_file"
  > "$keys_file"

  cd $(dirname "$input_file")

  # Generate the fileFromTxtfile.fcv using stdcomp and filter out unnecessary lines
  # stdcomp -A : Emit preprocessed data suitable for asctotb
  stdcomp -A "$(basename "$input_file")" | grep -Ev "?compiled|SVN iden|SCCS ident" > "$txt_file"

    # Create a list of keys from the file name, replacing underscores with hashes
  echo "$(basename "$input_file" .fcv)" | awk '{ if (match($0,/((([A-Z])+_)*FCV_.*$)/,m)) print m[0] }' | awk '{gsub("_", "#"); print $0}' | awk '{ gsub(".fcv",""); print $0 }' 2>/dev/null > "$keys_file"

  # Process each key and append the result to the stdcomp_file, filtering out unnecessary lines
  while read -r key; do
    tbtoasc -e "$key" | grep -Ev "?compiled|SVN iden|SCCS ident" >> "$stdcomp_file"
  done < "$keys_file"

  # Display fcv.i files
  print ""
  print "fcv.i file(s) : \n $(cat "$txt_file" | grep -E "?line" | grep -E "fcv.i" | awk -F'"' '{print $2}')"

  # Compare the stdcomp_file with the original file to validate the changes
  compare_files "$stdcomp_file" "$txt_file"

  # Display fcv.i files
  print "fcv.i file(s) : \n $(cat "$txt_file" | grep -E "?line" | grep -E "fcv.i" | awk -F'"' '{print $2}')"
  print ""
}
####################################################
#              DIRECTORY ASC/FCV                   #
####################################################

# Process a directory of ASC or FCV files
process_directory() {
  typeset dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "Error: The file '$dir' is not a directory."
    return 1
  fi

  cd $dir
  
  # Prepare data path
  typeset tar_path="${report_directory_path}/directory.tar.gz"
  typeset keys_file="${report_files_directory_path}/keys.txt"
  typeset fileskeys_csv="${report_directory_path}/fileskeys.csv"

  # Ensure no confirmation is needed for overwrites and clear previous files
  echo > ${keys_file}

  # backup directory
  print " Tar gz directory processing ... "
  tar -vczf "$tar_path" -C "$(dirname "$dir")" "$(basename "$dir")"
  print ""
  print " Tar gz directory process finished "
  print ""
   
  # for file in "$dir"/*.asc "$dir"/*.fcv; do
  #   [ -f "$file" ] || continue
  #   [ "${file##*.}" = "asc" ] && process_asc_file "$file" || process_fcv_file "$file"
  # done   

  #Initialization of the result file
  echo "Path;File;Key;Key_chg;File_key_nb;File_chg;Key_dbl;File_dbl" > ${fileskeys_csv}
      
  #
  # case *.asc or *.fcv in $dir directory
  #
  total_file_count=$(find "$dir" -maxdepth 1 -type f \( -name '*.asc' -o -name '*.fcv' \) 2>/dev/null | wc -l | awk '{print $1}')

  if [ ${total_file_count} -ge 1 ] ; then 
    if [ ! -e "${rewritten_asc_fcv_dir_path}" ]; then
        mkdir -p "${rewritten_asc_fcv_dir_path}"
    else
        rm -rf "${rewritten_asc_fcv_dir_path}" && mkdir -p "${rewritten_asc_fcv_dir_path}"
    fi
   
    for file in "$dir"/*.asc "$dir"/*.fcv; do
      [ -f "$file" ] || continue
      let file_count++
      print "File processing "$file_count"/"$total_file_count" : "$file
      [ "${file##*.}" = "asc" ] && process_asc_dir "$file" || process_fcv_dir "$file" 
    done
  fi 
  # add statistical
  add_statistical "$fileskeys_csv"
}  
process_asc_dir() { 
  typeset input_file="$1"
  # Validate input file
  if [[ ! -f "$input_file" ]]; then
    echo "Error: File '$input_file' not found." >&2
    return 1
  fi

  # Prepare data path
  typeset file_1key_asc="${report_files_directory_path}/file_1key_asc"
  typeset keys_empty_file="${report_files_directory_path}/keys_empty_file"
  typeset keys_file_Error="${report_files_directory_path}/keys_file_Error"
  typeset stdtbl_error_log="${report_files_directory_path}/stdtbl_error_log"
  typeset stdtbl_1key_asc="${report_files_directory_path}/stdtbl_1key.asc"
  typeset header_file="${report_files_directory_path}/commentHeader.txt"

  fileName=$(basename "${input_file}")
  fileExt="${input_file##*.}"

  # find keys in asc file and remove [ and ] in the keys_file.txt file
  awk '
    !/^[[:space:]]/ &&
    match($1, /^\[(.*)\]$/, output) {
        print output[1]
    }
  ' "${input_file}" 2>/dev/null > "${keys_file}"
  # find empty keys and write them to the keys_empty_file
  awk '{
    if ($1 ~ /^\[.*\]$/) { 
      state = "key_detected";					
      current_key = substr($1, 2, length($1) - 2);
    } 
    else if (state == "key_detected" && $1 ~ /^\\\\$/) { 
      state = "empty_key_detected";
      print current_key; 
    } 
    else { 
      state = "key_not_detected"; 
    }
  }' "${input_file}" 2>/dev/null > "${keys_empty_file}"

  rewritten_file="${rewritten_asc_fcv_dir_path}/${fileName}"

  # Check if the write option is enabled (Option_Write is set)
  if [ -n "${Option_Write}" ]; then
    # Build comment header
    awk '/^[!]/ {print} /[^!]/ {exit}' "${input_file}" 2>/dev/null > "${header_file}"

    # Write comment header to the output file
    {
      cat "${header_file}"
      echo "!"
      echo "!  $(stamp) : checkconf : rewrite of key values by tbtoasc - ${fileName}"
      echo "!"
    } >> "${rewritten_file}"

    # Process each line in the keys_file
    while read -r line; do
      tbtoasc -e "$line" 2>"${keys_file_Error}" >> "${rewritten_file}"
      
      # Check if the keys_file_Error is not empty, indicating errors
      if [ -s "${keys_file_Error}" ]; then
        while read -r keyEmpty; do
          # If the key is found in the empty keys file, append it to the rewritten file
          if [ "${keyEmpty}" == "${line}" ]; then
            echo "[${line}]" >> "${rewritten_file}"
            echo "\\" >> "${rewritten_file}"
          fi
        done < "${keys_empty_file}"
      fi
    done < "${keys_file}"
  fi

  
  # Build fileskeys.csv file
  while read -r line; do
    # Create file_1key_asc by extracting the content of a specific key block from the input file
    awk -v target_key="['${line}']" '
      BEGIN { current_key = "" }
      {
        if ($1 == target_key && current_key == "") {
          current_key = $1
          print $1
        } else if (/^\\\\$/ && current_key != "") {
          current_key = ""
          print $0
        } else if (current_key != "") {
          print $0
        }
      }
    ' "${input_file}" > "${file_1key_asc}"
    echo "cat ${file_1key_asc}"
    cat "${file_1key_asc}"
    # create stdtbl_1key_asc
    tbtoasc -e "$line" >"${stdtbl_1key_asc}" 2>"${stdtbl_error_log}"
    # Empty key processing
    if awk '/^Error\s/' "${stdtbl_error_log}" &>/dev/null; then
      is_key_empty=false
      while read -r key_empty; do
        if [[ "$key_empty" == "$line" ]]; then
          echo "${dir};${input_file};${line};KEY_UNCHANGED" >> "${fileskeys_csv}"
          is_key_empty=true
        fi
      done < "${keys_empty_file}"

      # If the key is not empty but there was an error
      if [[ $is_key_empty == false ]]; then
        echo "${dir};${input_file};${line};KEY_ERROR" >> "${fileskeys_csv}"
      fi
    else
      # # treatment of false duplicates starting with \champ= 
      # set -A FieldsNoValue_Stdtbl $(awk 'match($1, /(^\\\S+=)$/, output) {print "\\"output[1]}' "$stdtbl_1key_asc")
      # set -A FieldsNoValue_File $(awk 'match($1, /(^\\\S+=)$/, output) {print "\\"output[1]}' "$file_1key_asc")
      
      # if [[ ${FieldsNoValue_Stdtbl[0]} ]]; then
      #   for (( i=0; i<${#FieldsNoValue_Stdtbl[*]}; i++ )) ; do
      #     cat ${file_1key_asc} | awk -v field="${FieldsNoValue_Stdtbl[$i]}" '{if ($0 !~ /=$/) {{ if ($0 ~ field) { match($1,/(^\\\S+=)(\S+$)/,output); print output[1] "\n" output[2] } else {print $0}}} else {print $0} }' 2>/dev/null > ${temp_file_1key_asc} && mv ${temp_file_1key_asc} ${file_1key_asc}
      #   done
      # fi
      # if [[ ${FieldsNoValue_File[0]} ]]; then
      #   for (( i=0; i<${#FieldsNoValue_File[*]}; i++ )) ; do
      #     cat ${file_1key_asc} | awk -v field="${FieldsNoValue_File[$i]}" '{if ($0 !~ /=$/) {{ if ($0 ~ field) { match($1,/(^\\\S+=)(\S+$)/,output); print output[1] "\n" output[2] } else {print $0}}} else {print $0} }' 2>/dev/null > ${temp_stdtbl_1key_asc} && mv ${temp_stdtbl_1key_asc} ${stdtbl_1key_asc}
      #   done
      # fi
    
      # delete carriage return after '=' when there is data
      sed -ri ':a;N;$!ba;s/=\n([^\\])/=\1/g' ${stdtbl_1key_asc}
      sed -ri ':a;N;$!ba;s/=\n([^\\])/=\1/g' ${file_1key_asc}
      
      # Compare tables
      compare_stdtbl -unchanged ${stdtbl_1key_asc} ${file_1key_asc} | awk ' /-----\sUNCHANGED\sKEY/ {print "'${dir}';'${input_file}';'${line}';KEY_UNCHANGED"} /-----\sUPDATED\sKEY/ {print "'${dir}';'${input_file}';'${line}';KEY_UPDATED"}' >> ${fileskeys_csv}
    fi
  done < "${keys_file}"

  if ${Option_Write} ; then
    print ""
    print " ---> See file(s) created with write option in "${rewritten_asc_fcv_dir_path}
    print ""
  fi
}
process_fcv_dir() {
  #
  # case *.fcv in $dir directory
  #

  # Prepare data path
  typeset temp_dir_tbtoasc_error_fcv="${report_files_directory_path}/temp_dir_tbtoasc_error_fcv"  # Temporary file for storing errors during tbtoasc conversion
  typeset temp_dir_tbtoasc_fcv="${report_files_directory_path}/temp_dir_tbtoasc_fcv"        # Temporary file for storing tbtoasc conversion result
  typeset temp_dir_fcv="${report_files_directory_path}/temp_dir_fcv"

  # StdComp -A to obtain asctotb format
  stdcomp -A ${file} 2>/dev/null | grep -v "?compiled" | grep -v "SVN iden" | grep -v "SCCS ident" > ${temp_dir_fcv}

  echo ${file} | awk '{ if (match($0,/((([A-Z])+_)*FCV_.*$)/,m)) print m[0] }' |awk '{gsub("_", "#"); print $0}' | awk '{ gsub(".fcv",""); print $0 }' 2>/dev/null > ${keys_file}

  # Build temp.fcv file
  for line in $(cat ${keys_file}) ; do
      tbtoasc -e "$line" 2>${temp_dir_tbtoasc_error_fcv} | grep -v "?compiled" | grep -v "SVN iden" | grep -v "SCCS ident" > ${temp_dir_tbtoasc_fcv}
  done
  #
  # Compare tables
  #
  if [[ $(cat ${temp_dir_tbtoasc_error_fcv} | awk '/^Error\s/ {print $0}') ]]; then
    echo "${dir};${file};${line};KEY_ERROR" >> ${fileskeys_csv}
  else
    compare_stdtbl -unchanged ${temp_dir_tbtoasc_fcv} ${temp_dir_fcv} | awk ' /-----\sUNCHANGED\sKEY/ {print "'${dir}';'${file}';'${line}';KEY_UNCHANGED"} /-----\sUPDATED\sKEY/ {print "'${dir}';'${file}';'${line}';KEY_UPDATED"}' >> ${fileskeys_csv}
  fi

}

add_statistical() {
  # Define a temporary output file
  temp_output_file="${fileskeys_csv}.tmp"
  
  # Add statistical columns to fileskeys_csv
  awk -F ";" '
    NR == 1 {
      print $0; next
    }
    {
      allfields[NR] = $0
      field2[NR] = $2
      field3[NR] = $3

      doublefield2[$2]++
      doublefield3[$3]++
      doublefield23[$2"-"$3]++
      doublefield24[$2"-"$4]++
      
      if (!listdoublefield2[$3]) {
        listdoublefield2[$3] = $2
      } else {
        listdoublefield2[$3] = $2" | "listdoublefield2[$3]
      }
    }
    END {
      for (numline = 2; numline <= NR; numline++) {
        print allfields[numline] ";" doublefield2[field2[numline]] ";",
          (doublefield2[field2[numline]] == doublefield24[field2[numline]"-KEY_UNCHANGED"] ? "FILE_UNCHANGED;" : "FILE_UPDATED;"),
          doublefield3[field3[numline]] ";" listdoublefield2[field3[numline]]
      }
    }
  ' "$fileskeys_csv" > "$temp_output_file" && mv "$temp_output_file" "$fileskeys_csv"

  print ""
  print " ---> See the array result:       $fileskeys_csv"
  print " ---> And the backup directory:   $tar_path"
  print ""
}
# Compare two files and display results
compare_files() {
  typeset file1="$1"
  typeset file2="$2"

  compare_stdtbl "$file1" "$file2" > "$files_directory_path/compareMessage.txt" 2> "$files_directory_path/compareError.txt"

  if [ -s "$files_directory_path/compareError.txt" ]; then
    die "Error during comparison. Check $files_directory_path/compareError.txt for details."
  elif [ -s "$files_directory_path/compareMessage.txt" ]; then
    print ""
    print "File 1: $file1"
    print "File 2: $input_file"
    print ""
    print "================================================="
    print "\033[31m /!\ Files Comparison Result: Differences Found!\033[0m"
    print "================================================="
    print ""
    print "Press Ctrl+C to exit or wait to see the details."
    read -t 5
    more ${files_directory_path}/compareMessage.txt
    print ""
    print "To see the comparison again, run 'more $files_directory_path/compareMessage.txt'"
    print ""
    print "File 1: $file1"
    print "File 2: $input_file"
    print ""
  else
    print ""
    print "File 1: $file1"
    print "File 2: $input_file"
    print ""
    print "=============================================="
    print "\033[32m OK! Files Comparison Result: No Differences!\033[0m"
    print "============================================="

    print ""
  fi
}

# Function to convert a relative path to an absolute path
get_absolute_path() {
  relative_path="$1"

  # Get the absolute directory
  if [[ "$relative_path" != /* ]]; then
    relative_path="$(pwd)/$relative_path"
  fi

  # Use a subshell with cd to resolve the absolute path fully
  absolute_path=$(cd "$(dirname "$relative_path")" && pwd)/$(basename "$relative_path")

  echo "$absolute_path"
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
      *) directoryOrFile=$(get_absolute_path $1) ;;
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
