#!/usr/bin/ksh
#
# Script : checkconf.ksh
# Compare database configuration keys with file keys (asc or fcv files)
# Usage  : checkconf.ksh [-help|-h] [-write|-w] [-backup|-b] <directory_or_file>
#
# Author : Mickaël Seror
# Date   : November 2024
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
Usage: $(basename $0) [-help|-h] [-write|-w] [-backup|-b] <directory_or_file>
  -help                      Display this help screen
  -write                     Process all files in the specified directory. Rewrites files using 'tbtoasc' and saves them in './rewritten_asc_fcv_dir'.
  -backup                    Creates a compressed backup of the specified directory. The archive is saved as './backup/<directory_name>.tar.gz'.
  <directory_or_file>        Specifies the directory or file to process.
                             - If a directory is provided, a 'report.csv' will be generated.
                             - If a file is provided, it will be processed individually.
EOF
  exit 0
}

# Initialize necessary paths and directories
initialize_paths() {
  base_path="$(cd "$(dirname "$(readlink -f "$0")")"; pwd)"
  fcv_file_path="${base_path}/fcv_file"
  asc_file_path="${base_path}/asc_file"
  compare_path="${base_path}/compare"
  report_path="${base_path}/report"
  fcv_dir_path="${base_path}/fcv_dir"
  asc_dir_path="${base_path}/asc_dir"
  rewritten_asc_fcv_dir_path="${base_path}/rewritten_asc_fcv_dir"
  backup_path="${base_path}/backup"

  # List of directories
  dir_list=("$fcv_file_path" "$asc_file_path" "$compare_path" "$report_path" "$fcv_dir_path" "$asc_dir_path" "$rewritten_asc_fcv_dir_path" "$backup_path")

  # Reset each directory
  for dir in "${dir_list[@]}"; do
      [ -d "$dir" ] && rm -rf "$dir"  # Remove if exists
      mkdir -p "$dir"  # Create directory
  done
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
#             process ASC FILE                     #
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
  typeset txt_file="$asc_file_path/fileFromTxtfile.asc"
  typeset keys_file="$asc_file_path/keys.txt"
  typeset header_file="$asc_file_path/commentHeader.txt"
  typeset tbtoasc_file="$asc_file_path/fileFromTbtoasc.asc"
  typeset tbtoasc_error_file="$asc_file_path/fileFromTbtoascError.asc"

  # Ensure no confirmation is needed for overwrites and clear previous files
  > "$txt_file"
  > "$keys_file"
  > "$header_file"
  > "$tbtoasc_file"
  > "$tbtoasc_error_file"

  # Copy the input file to the working directory
  cp -f "$input_file" "$txt_file"

  # Extract keys from the input file
  awk 'match($0,/^\[(.*)\]$/,output) {print output[1]}' "$txt_file" 2>/dev/null > "$keys_file"

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
    tbtoasc -w 9999 -e "$key" >> "$tbtoasc_file" 2>"$tbtoasc_error_file"
    # If an error is detected, add the umpty key to the tbtoasc_file
    if grep -q '^Error' "$tbtoasc_error_file"; then
      echo "[$key]" >> "$tbtoasc_file"
      echo "\\\\" >> "$tbtoasc_file"
    fi
  done < "$keys_file"

	# delete carriage return after '=' when there is data except comment lines
	sed -ri '/^\!.*=$/ s/=//g' $txt_file
	sed -ri ':a;N;$!ba;s/=\n([^\\])/=\1/g' $txt_file
	sed -ri ':a;N;$!ba;s/=\n([^\\])/=\1/g' $tbtoasc_file

  # Compare the tbtoasc and txt files
  #clean_duplicate "$tbtoasc_file" "$txt_file"
  compare_files "$tbtoasc_file" "$txt_file"
}

####################################################
#             process FCV FILE                     #
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
  typeset txt_file="$fcv_file_path/fileFromTxtfile.fcv"
  typeset tbtoasc_file="$fcv_file_path/fileFromTbtoasc.fcv"
  typeset keys_file="$fcv_file_path/keys.txt"
  
  # Clear or create the output files to avoid appending to old data
  > "$txt_file"
  > "$tbtoasc_file"
  > "$keys_file"

  cd $(dirname "$input_file")

  # Generate the fileFromTxtfile.fcv using stdcomp and filter out unnecessary lines
  # stdcomp -A : Emit preprocessed data suitable for asctotb
  stdcomp -A "$(basename "$input_file")" | grep -Eav "\?compiled|SVN iden|SCCS ident" > "$txt_file"

    # Create a list of keys from the file name, replacing underscores with hashes
  echo "$(basename "$input_file" .fcv)" | awk '{ if (match($0,/((([A-Z])+_)*FCV_.*$)/,m)) print m[0] }' | awk '{gsub("_", "#"); print $0}' | awk '{ gsub(".fcv",""); print $0 }' 2>/dev/null > "$keys_file"

  # Process each key and append the result to the tbtoasc_file, filtering out unnecessary lines
  while read -r key; do
    tbtoasc -w 9999 -e "$key" | grep -Eav "\?compiled|SVN iden|SCCS ident" >> "$tbtoasc_file"
  done < "$keys_file"

  # Display fcv.i files
  print ""
  print "fcv.i file(s) : \n $(cat "$txt_file" | grep -aE "\?line" | grep -aE "fcv.i" | awk -F'"' '{print $2}' | uniq)"


  # Compare the tbtoasc_file with the original file to validate the changes
  compare_files "$tbtoasc_file" "$txt_file"

  # Display fcv file from stdcomp
  print "File 2 from stdcomp -A : $txt_file"
  # Display fcv.i files
  print ""
  print "fcv.i file(s) : \n $(cat "$txt_file" | grep -aE "\?line" | grep -aE "fcv.i" | awk -F'"' '{print $2}' | uniq)"
  print ""
}

####################################################
#             process DIRECTORY                    #
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
  typeset tar_path="${backup_path}/directory.tar.gz"
  typeset keys_file="${asc_dir_path}/keys.txt"
  typeset report_csv="${report_path}/report.csv"

  # Ensure no confirmation is needed for overwrites and clear previous files
  echo > ${keys_file}

  # backup directory
  # Check if the backup option is enabled (Option_Backup is set)
  if [ "${Option_Backup}" = "true" ]; then
    print " Tar gz directory processing ... "
    tar -vczf "$tar_path" -C "$(dirname "$dir")" "$(basename "$dir")"
    print ""
    print " Tar gz directory process finished "
    print ""
  fi 

  # Initialization of the result file
  echo "Path;File;Key;Key_chg;File_key_nb;File_chg;Key_dbl;File_dbl" > ${report_csv}

  # Count total number of *.asc and *.fcv files in the directory
  total_file_count=$(find "$dir" -maxdepth 1 -type f \( -name '*.asc' -o -name '*.fcv' \) | wc -l)

  # Process files in $dir directory
  file_count=0
  find "$dir" -maxdepth 1 -type f \( -name '*.asc' -o -name '*.fcv' \) | while read -r file; do
      [ -f "$file" ] || continue
      file_count=$((file_count + 1))
      print "File processing $file_count/$total_file_count : $file"

      # Determine the processing function based on file extension
      case "${file##*.}" in
          asc) process_asc_dir "$file" ;;
          fcv) process_fcv_dir "$file" ;;
      esac
  done

  # Add statistical data
  add_statistical "$report_csv"

  if [ "${Option_Write}" = "true" ]; then
    print " ---> See file(s) created with write option in "${rewritten_asc_fcv_dir_path}
    print ""
  fi
}

####################################################
#             process ASC DIR                      #
####################################################

process_asc_dir() { 
  typeset input_file="$1"
  # Validate input file
  if [[ ! -f "$input_file" ]]; then
    echo "Error: File '$input_file' not found." >&2
    return 1
  fi

  # Prepare data path
  typeset tbtoasc_error_log_rewritten="${asc_dir_path}/tbtoasc_error_log_rewritten"
  typeset tbtoasc_error_log="${asc_dir_path}/tbtoasc_error_log"
  typeset file_1key_asc="${asc_dir_path}/file_1key_asc"
  typeset tbtoasc_1key_asc="${asc_dir_path}/tbtoasc_1key_asc"
  typeset header_file="${asc_dir_path}/commentHeader.txt"

    # Clear or create the output files to avoid appending to old data
  > "$tbtoasc_error_log_rewritten"
  > "$tbtoasc_error_log"
  > "$file_1key_asc"
  > "$tbtoasc_1key_asc"
  > "$header_file"

  fileName=$(basename "${input_file}")
  fileExt="${input_file##*.}"

  # Build keys_file.txt file 
  # find keys in asc file and remove [ and ] in the keys_file.txt file
  awk 'match($0,/^\[(.*)\]$/,output) {print output[1]}' "${input_file}" 2>/dev/null > "${keys_file}"
  
  # Build fileskeys.csv file
  while read -r line; do
    # Build file_1key_asc file by extracting the content of a specific key block from the input file
    awk -v target_key="[${line}]" '
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
  
    # Build tbtoasc_1key_asc file
    tbtoasc -w 9999 -e "$line" >"${tbtoasc_1key_asc}" 2>"${tbtoasc_error_log}"
      
    # delete carriage return after '=' when there is data
    sed -ri ':a;N;$!ba;s/=\n([^\\])/=\1/g' ${tbtoasc_1key_asc}
    sed -ri ':a;N;$!ba;s/=\n([^\\])/=\1/g' ${file_1key_asc}
  
    # Compare tbtoasc_1key_asc vs file_1key_asc
    if [[ $(cat ${tbtoasc_error_log} | awk '/^Error\s/ {print $0}') ]]; then
      echo "${dir};${fileName};${line};KEY_ERROR" >> ${report_csv}
    else
      #clean_duplicate ${tbtoasc_1key_asc} ${file_1key_asc}
      compare_stdtbl -unchanged ${tbtoasc_1key_asc} ${file_1key_asc} | awk ' /-----\sUNCHANGED\sKEY/ {print "'${dir}';'${fileName}';'${line}';KEY_UNCHANGED"} /-----\sUPDATED\sKEY/ {print "'${dir}';'${fileName}';'${line}';KEY_UPDATED"}' >> ${report_csv}
    fi
  done < "${keys_file}"
  
  # Check if the write option is enabled (Option_Write is set)
  if [ "${Option_Write}" = "true" ]; then
    rewritten_file="${rewritten_asc_fcv_dir_path}/${fileName}"
    # Build comment header
    # awk '/^[!]/ {print} /[^!]/ {exit}' "${input_file}" 2>/dev/null > "${header_file}"
    awk '/^!/' "$input_file" > "${header_file}"

    # Write comment header to the output file
    {
      cat "${header_file}"
      echo "!"
      echo "!  $(stamp) : checkconf : rewrite of key values by tbtoasc - ${fileName}"
      echo "!"
    } > "${rewritten_file}"

    # Process each line in the keys_file
    while read -r line; do
      tbtoasc -w 9999 -e "$line" 2>"${tbtoasc_error_log_rewritten}" >> "${rewritten_file}"
      
      # Check if the tbtoasc_error_log_rewritten is not empty, indicating errors
      if [ -s "${tbtoasc_error_log_rewritten}" ]; then
        echo "[${line}]" >> "${rewritten_file}"
        echo "\\\\" >> "${rewritten_file}"
      fi
      # delete carriage return after '=' when there is data except comment lines
	    # sed -ri '/^\!.*=$/ s/=//g' "${rewritten_file}"
	    # sed -ri ':a;N;$!ba;s/=\n([^\\])/=\1/g' "${rewritten_file}"
    done < "${keys_file}"
  fi
}

clean_duplicate(){
  # treatment of false duplicates starting with \champ= 
  typeset file1="$1"
  typeset file2="$2"

  # Prepare data path
  typeset temp_file1="${asc_dir_path}/temp_file1"
  typeset temp_file2="${asc_dir_path}/temp_file2"
  
  set -A FieldsNoValue_tbtoasc $(cat ${file1} | awk 'match($1,/(^\\\S+=)$/,output) {print "\\"output[1]}')
  set -A FieldsNoValue_File $(cat ${file2} | awk 'match($1,/(^\\\S+=)$/,output) {print "\\"output[1]}')
  
  if [[ ${FieldsNoValue_tbtoasc[0]} ]];
  then
    for (( i=0; i<${#FieldsNoValue_tbtoasc[*]}; i++ )) ; do
      cat ${file2} | awk -v field="${FieldsNoValue_tbtoasc[$i]}" '{if ($0 !~ /=$/) {{ if ($0 ~ field) { match($1,/(^\\\S+=)(\S+$)/,output); print output[1] "\n" output[2] } else {print $0}}} else {print $0} }' 2>/dev/null > ${temp_file2} && mv ${temp_file2} ${file2}
    done
  fi
  if [[ ${FieldsNoValue_File[0]} ]];
  then
    for (( i=0; i<${#FieldsNoValue_File[*]}; i++ )) ; do
      cat ${file2} | awk -v field="${FieldsNoValue_File[$i]}" '{if ($0 !~ /=$/) {{ if ($0 ~ field) { match($1,/(^\\\S+=)(\S+$)/,output); print output[1] "\n" output[2] } else {print $0}}} else {print $0} }' 2>/dev/null > ${temp_file1} && mv ${temp_file1} ${file1}
    done
  fi
}

####################################################
#             process FCV DIR                      #
####################################################

process_fcv_dir() {
  typeset input_file="$1"
  # Validate input file
  if [[ ! -f "$input_file" ]]; then
    echo "Error: File '$input_file' not found." >&2
    return 1
  fi

  # Prepare data path
  typeset stdcomp_error_log="${fcv_dir_path}/stdcomp_error_log"  # Temporary file for storing errors during tbtoasc conversion
  typeset stdcomp_fcv_dir="${fcv_dir_path}/stdcomp_fcv_dir.asc"        # Temporary file for storing tbtoasc conversion result
  typeset file_fcv_dir="${fcv_dir_path}/file_fcv_dir.asc"

  # Ensure no confirmation is needed for overwrites and clear previous files
  > "$stdcomp_error_log"
  > "$stdcomp_fcv_dir"
  > "$file_fcv_dir"

  fileName=$(basename "${input_file}")
  fileExt="${input_file##*.}"

  # Build file_fcv_dir file
  # StdComp -A to obtain asctotb format
  stdcomp -A ${file} 2>/dev/null | grep -Eav "\?compiled|SVN iden|SCCS ident" > ${file_fcv_dir}

  # Build keys_file.txt file 
  # find keys in the fileName of fcv file (begin by FCV and replace _ by #)
  echo ${fileName} | awk '{ if (match($0,/((([A-Z])+_)*FCV_.*$)/,m)) print m[0] }' |awk '{gsub("_", "#"); print $0}' | awk '{ gsub(".fcv",""); print $0 }' 2>/dev/null > ${keys_file}

  # Build stdcomp_fcv_dir file
  typeset key="$(cat ${keys_file})"
  tbtoasc -w 9999 -e "${key}" 2>${stdcomp_error_log} | grep -Eav "\?compiled|SVN iden|SCCS ident" > ${stdcomp_fcv_dir}

  # Compare stdcomp_fcv_dir vs file_fcv_dir
  if [[ $(cat ${stdcomp_error_log} | awk '/^Error\s/ {print $0}') ]]; then
    echo "${dir};${file};${key};KEY_ERROR" >> ${report_csv}
  else
    compare_stdtbl -unchanged ${stdcomp_fcv_dir} ${file_fcv_dir} | awk ' /-----\sUNCHANGED\sKEY/ {print "'${dir}';'${fileName}';'${key}';KEY_UNCHANGED"} /-----\sUPDATED\sKEY/ {print "'${dir}';'${fileName}';'${key}';KEY_UPDATED"}' >> ${report_csv}
  fi

}

####################################################
#             add statistical                      #
####################################################

add_statistical() {
  # Define a temporary output file
  report_csv_tmp="${report_csv}.tmp"
  
  # Add statistical columns to report_csv
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
        print allfields[numline]";"doublefield2[field2[numline]]";",
        (doublefield2[field2[numline]]==doublefield24[field2[numline]"-KEY_UNCHANGED"])?"FILE_UNCHANGED;":"FILE_UPDATED;", 
        doublefield3[field3[numline]]";"listdoublefield2[field3[numline]]
      }
    }
  ' "$report_csv" > "$report_csv_tmp" && mv "$report_csv_tmp" "$report_csv"

  print ""
  print " ---> See the array result:       $report_csv"
  if [ "${Option_Backup}" = "true" ]; then
    print " ---> And the backup directory:   $tar_path"
  fi
  print ""
}

####################################################
#             compare file                         #
####################################################

# Compare two files and display results
compare_files() {
  typeset file1="$1"
  typeset file2="$2"

  compare_stdtbl "$file1" "$file2" > "$compare_path/compareMessage.txt" 2> "$compare_path/compareError.txt"

  if [ -s "$compare_path/compareError.txt" ]; then
    die "Error during comparison. Check $compare_path/compareError.txt for details."
  elif [ -s "$compare_path/compareMessage.txt" ]; then
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
    more ${compare_path}/compareMessage.txt
    print ""
    print "To see the comparison again, run 'more $compare_path/compareMessage.txt'"
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
  typeset Option_Backup=false

  # Parse arguments
  while [ $# -ge 1 ]; do
    case "$1" in
      -h|-help) Option_Help=true ;;
      -w|-write) Option_Write=true ;;
      -b|-backup) Option_Backup=true ;;
      *) directoryOrFile=$(get_absolute_path $1) ;;
    esac
    shift
  done

  $Option_Help && show_usage
  [ -z "$directoryOrFile" ] && die "Error: Missing directory or file argument."

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
