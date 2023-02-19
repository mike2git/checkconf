#!/usr/bin/ksh
#
#
# Script: checkconf.ksh [-help|-h] [-write|-w] <directory_or_file>
#
#  For <directory_or_file> argument is a file (*.asc, *.fcv, ...)
#       Make a diff between :
#		- information from database 
#		and
#		- information from file		
#		Work for *.asc and *.fcv
#  For <directory_or_file> argument is a directory
#       Make a array (fileskeys.csv file) of all files (*.asc, *.fcv, ...) from the directory with all keys.
#       Add information about key changes from database and keys double in the directory
#       fileskeys.csv in indirectory : ${BasePath}/Repport
#       Fields of fileskeys.csv :
#       Path | File | Key | Key_chg | File_key_nb | File_chg | Key_dbl | File_dbl
#       A backup (tar gz) of the original directory is also made and stored in ${DataPathRepport}/directory.tar.gz
#  For -write or -w option (to use with <directory_or_file> argument is a directory AND *.asc files)
#       Rewrite keys from tbtoasc of file or all files in directory
#       All new files created are in : ${DataPathRepport}/Write
#       A line of comment is added in each file : "!  $(stamp)	:  checkconf  :  rewrite of key values ​​by tbtoasc - $fileName "
#
#  This script uses compare_stdtbl, stdcomp and colordiff.
#
#   History
#     10-11-2019   MSR   Initial creation
#     22-11-2019   MSR   Add directory argument
#     11-02-2020   MSR   Add -write option
#
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

function error
{
   # - dispay text on stderr and exit
   print 1>&2 "${*}"
   exit
}

function stamp {
   # Display time-stamp and specified text
   # date "+%Y-%m-%d %H:%M:%S ${*}"
   date "+%d-%m-%Y ${*}"
   
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
# --- Parse arguments
#

USAGE="Usage: $(basename ${0}) [-help|-h] [-write|-w] <directory_or_file>"

if [ ${#} -eq 0 ]; then Die "${USAGE}"; fi

directoryOrFile=""
Option_Help="false"
Option_Write="false"


while [ ${#} -ge 1 ]
do
   case "${1}" in
      -h|-help) Option_Help="true" ;;
       -w|-write) Option_Write="true" ;;
             *) if [ -z "${directoryOrFile}" ]
                   then directoryOrFile="${1}"
                   else Die "${USAGE}"
                fi
                ;;
   esac
   shift
done

if ${Option_Help}
then
   echo "Usage: $(basename ${0}) [-help|-h] [-write|-w] <directory_or_file>"
   echo "     -help			display this help screen"
   echo "     -write			write keys from tbtoasc in ./Repport/Write and make a tar gz of <directory_or_file> in ./Repport/directory.tar.gz"
   echo "     <directory_or_file>	directory or file to check"
   exit
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
# --- Initialisation
#

if ! tty -s; then . ~/.profile > /dev/null 2>&1; fi


# initialisation of BasePath = ~x_xxx/ab/scripts/checkconf/
BasePath="$( cd $(dirname "$(readlink -f ${0})") ; pwd )"

DataPath="${BasePath}/Files"
commentHeader="${DataPath}/commentHeader.txt"
keys="${DataPath}/keys.txt"
fileFromTbtoasc="${DataPath}/fileFromTbtoasc.asc"
compareMessage="${DataPath}/compareMessage.txt"
compareError="${DataPath}/compareError.txt"
fileFromTxtfile_fcv="${DataPath}/fileFromTxtfile.fcv"
fileFromTbtoasc_fcv="${DataPath}/fileFromTbtoasc.fcv"

# initialisation of DataPathReport
DataPathRepport="${BasePath}/Repport"
DataPathRepportTmp="${DataPathRepport}/Files"
DataPathRepportWrite="${DataPathRepport}/Write"
keys_file_Error="${DataPathRepportTmp}/keys_File_Error.txt"
keys_file="${DataPathRepportTmp}/keys_file.txt"
keys_empty_file="${DataPathRepportTmp}/keys_empty_file.txt"
stdtbl_1key_asc="${DataPathRepportTmp}/stdtbl_1key.asc"
file_1key_asc="${DataPathRepportTmp}/file_1key.asc"
temp_file_1key_asc="${DataPathRepportTmp}/temp_file_1key.asc"
temp_stdtbl_1key_asc="${DataPathRepportTmp}/temp_stdtbl_1key.asc"
temp_dir_tbtoasc_fcv="${DataPathRepportTmp}/temp_dir_tbtoasc.fcv"
temp_dir_tbtoasc_error_fcv="${DataPathRepportTmp}/temp_dir_tbtoasc_error.fcv"
temp_dir_fcv="${DataPathRepportTmp}/temp_dir.fcv"
temp_csv="${DataPathRepportTmp}/temp.csv"
temp_targz="${DataPathRepport}/directory.tar.gz"
fileskeys_csv="${DataPathRepport}/fileskeys.csv"

export CMPSTDTBL_DIFF=colordiff

if [ ! -e "${DataPath}" ]; then mkdir ${DataPath}; fi
if [ ! -e "${DataPathRepport}" ]; then mkdir ${DataPathRepport}; fi
if [ ! -e "${DataPathRepportTmp}" ]; then mkdir ${DataPathRepportTmp}; fi

for utility in gzip asctotb tbtoasc compare_stdtbl colordiff
do
   if [ -z "$( which ${utility} 2>&1 | grep -v "no ${utility} in" )" ]; then
      error "Unable to find required utility '${utility}'"
   fi
done


# get filename, extension (fcv or asc) and path 
fileName="$(echo ${directoryOrFile} | awk ' { n=split($0,rep,"/"); print rep[n] }')"
fileExt="$(echo ${directoryOrFile} | awk ' { n=split($0,rep,"."); print rep[n] }')"
filePath="$( dirname "$(readlink -f "${directoryOrFile}")" )"

# Absolute path in directoryOrFile variable
directoryOrFile="$(readlink -f ${directoryOrFile})"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
# Argument ${directoryOrFile} is a *.asc file
#
if [[ $fileExt = "asc" ]];
	then 
	# find key in asc file and remove [ and ] in the keys.txt file
	cat ${directoryOrFile} | awk '!/^[[:space:]]+.*/ {print}' | awk 'match($1,/^\[(.*)\]$/,output) {print output[1]}' 2>/dev/null > ${keys}
	
	# Build comment header
	cat ${directoryOrFile} | awk '{if ($0 ~ /^[!]/) {print $0} else end}' 2>/dev/null > ${commentHeader}
	cat ${commentHeader} > ${fileFromTbtoasc}
	echo "!" >> ${fileFromTbtoasc}
	echo "!  $(stamp)	:  checkconf  :  rewrite of key values ​​by tbtoasc - $fileName " >> ${fileFromTbtoasc}
	echo "!" >> ${fileFromTbtoasc}


	# Build temp.asc file
	for line in $(cat ${keys})
	do
			tbtoasc -e "$line" 2>/dev/null >> ${fileFromTbtoasc}
	done

	#
	# Compare tables
	#

	compare_stdtbl ${fileFromTbtoasc} ${directoryOrFile} > ${compareMessage} 2> ${compareError} 
	
	if [ -s $compareError ];
	then
		print ""
		print " ======================= "
		print " ===> ERROR Compare <=== "
		print " ======================= "
		print ""
		cat ${compareError}
		print ""
		print " For more details :"
		print " ---> See "${fileFromTbtoasc}
		print " ---> See "${keys}
		print ""
		exit 1
	fi
	if [ -s $compareMessage ];
	then 
		print ""
		print " =============================== "
		print " ===> The file is DIFFERENT <=== "
		print " =============================== "
		print ${directoryOrFile}" is not same from tbtoasc."
		
		print ""
		more ${compareMessage}
		print ""
		print " For more details :"
		print " ---> See "${fileFromTbtoasc}
		print " ---> See "${keys}
		print ""
	else
		print ""
		print " ======================== "
		print " ===> The file is OK <=== "
		print " ======================== "
		print ${directoryOrFile}" is same as from tbtoasc."
		print ""
		print " For more details :"
		print " ---> See "${fileFromTbtoasc}
		print " ---> See "${keys}
		print ""
	fi
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
# Argument ${directoryOrFile} is a *.fcv file
#
if [[ $fileExt = "fcv" ]];
then		
	cd ${filePath}
	# StdComp -A to obtain asctotb format
	stdcomp -A ${fileName} | grep -v "?compiled" | grep -v "SVN iden" | grep -v "SCCS ident" > ${fileFromTxtfile_fcv}
	# Create key from fcv file name	
	echo ${fileName} | awk '{ if (match($0,/((([A-Z])+_)*FCV_.*$)/,m)) print m[0] }' |awk '{gsub("_", "#"); print $0}' | awk '{ gsub(".fcv",""); print $0 }' 2>/dev/null > ${keys}

	# Remove fileFromTbtoasc_fcv when exit
	#trap "rm -f ${fileFromTbtoasc_fcv}" EXIT
	echo "" > ${fileFromTbtoasc_fcv}

	# Build temp.fcv file
	for line in $(cat ${keys})
	do
		tbtoasc -e "$line" | grep -v "?compiled" | grep -v "SVN iden" | grep -v "SCCS ident" 2>/dev/null >> ${fileFromTbtoasc_fcv}
	done

	#
	# Compare tables
	#

	compare_stdtbl ${fileFromTbtoasc_fcv} ${fileFromTxtfile_fcv} > ${compareMessage} 2> ${compareError}
	
	if [ -s $compareError ];
	then
		print ""
		print " ======================= "
		print " ===> ERROR Compare <=== "
		print " ======================= "
		print ""
		cat ${compareError}
		print ""
		print " For more details :"
		print " ---> See "${fileFromTbtoasc_fcv}
		print " ---> See "${fileFromTxtfile_fcv}
		print ""
		exit 1
	fi
	if [ -s $compareMessage ];
	then 
		print ""
		print " =============================== "
		print " ===> The file is DIFFERENT <=== "
		print " =============================== "
		print ${directoryOrFile}" is not same from tbtoasc."
		
		print ""
		more ${compareMessage}
		print ""
		print " For more details :"
		print " ---> See "${fileFromTbtoasc_fcv}
		print " ---> See "${fileFromTxtfile_fcv}
		print ""
	else
		print ""
		print " ======================== "
		print " ===> The file is OK <=== "
		print " ======================== "
		print ${directoryOrFile}" is same as from tbtoasc."
		print ""
		print " For more details :"
		print " ---> See "${fileFromTbtoasc_fcv}
		print " ---> See "${fileFromTxtfile_fcv}
		print ""
	fi
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
# ${directoryOrFile} argument is a directory
#
if [ -d ${directoryOrFile} ];
then
	
	cd ${directoryOrFile}
	PathFile="$(pwd)"
	echo > ${keys_file}
	# backup directory
	print " Tar gz directory processing ... "
	tar -vczf ${temp_targz} ${directoryOrFile}
	print ""
	print " Tar gz directory process finished "
	print ""
	
	#Initialization of the result file
	echo "Path;File;Key;Key_chg;File_key_nb;File_chg;Key_dbl;File_dbl" > ${fileskeys_csv}
			
	#
	# case *.asc in ${directoryOrFile} directory
	#
	nb_tot_file=$(ls ${directoryOrFile}/*.asc 2>/dev/null | wc -l)
	if [ ${nb_tot_file} -ge 1 ] ;
	then 
		if [ ! -e "${DataPathRepportWrite}" ]; 
			then mkdir ${DataPathRepportWrite};
			else rm -Rf ${DataPathRepportWrite} && mkdir ${DataPathRepportWrite};
		fi
		for file in $(ls -a *.asc)
		do
			let num_file++
			print "File processing "$num_file"/"$nb_tot_file" : "$file

			fileName="$(echo ${file} | awk ' { n=split($0,rep,"/"); print rep[n] }')"
			fileExt="$(echo ${file} | awk ' { n=split($0,rep,"."); print rep[n] }')"

			# find keys in asc file and remove [ and ] in the keys_file.txt file
			 cat ${file} | awk '!/^[[:space:]]+.*/ {print}' | awk 'match($1,/^\[(.*)\]$/,output) {print output[1]}' 2>/dev/null > ${keys_file}
			# find keys empty
			cat ${file} | awk '{ if (lines > 0 && $1 ~ /^\\\\$/) { print key } } { if (match($1,/^\[(.*)\]$/,output)) { key = output[1]; lines = 1 } else {--lines}}' 2>/dev/null > ${keys_empty_file}
			fileWrite="${DataPathRepportWrite}/${fileName}"


			if [ ${Option_Write} ] ;
			then
				# Build comment header
				cat ${file} | awk '{if ($0 ~ /^[!]/) {print $0} else exit}' 2>/dev/null > ${commentHeader}
				cat ${commentHeader} > ${fileWrite}
				echo "!" >> ${fileWrite}
				echo "!  $(stamp)	:  checkconf  :  rewrite of key values ​​by tbtoasc - $fileName " >> ${fileWrite}
				echo "!" >> ${fileWrite}

				

				for line in $(cat ${keys_file})
				do
					tbtoasc -e "$line" 2>${keys_file_Error} >> ${fileWrite}
					if [ -s ${keys_file_Error} ];
					then
						while read keyEmpty
						do
							if [ ${keyEmpty} == ${line} ];
							then
								echo "[${line}]" >> ${fileWrite}
								echo "\\" >> ${fileWrite}
							fi
						done < ${keys_empty_file}
					fi
				done
			fi
			# Build fileskeys.csv file
			for line in $(cat ${keys_file})
			do
				# create file_1key_asc
				 cat ${file} | awk 'BEGIN {currentkey =""} {if($1 == "['${line}']" && currentkey ==""){currentkey=$1; print $1} 
																else if (/^\\\\$/ && currentkey != ""){currentkey =""; print $0} 
																	else if (currentkey !="") {print $0}
															} ' > ${file_1key_asc}
				# create stdtbl_1key_asc
				tbtoasc -e "$line" 2>${stdtbl_1key_asc} 1> ${stdtbl_1key_asc}
				# Empty key processing
				if [[ $(cat ${stdtbl_1key_asc} | awk '/^Error\s/ {print $0}') ]];
				then 
					flagEmpty="False"
					while read keyEmpty
					do
						if [ $keyEmpty == $line ];
						then
							echo "${PathFile};${file};${line};KEY_UNCHANGED" >> ${fileskeys_csv}
							flagEmpty="True"
						fi
					done < $keys_empty_file
					if [ ! $flagEmpty ];
					then
							echo "${PathFile};${file};${line};KEY_ERROR" >> ${fileskeys_csv}
					fi
				else
					# treatment of false duplicates starting with \champ= 
					set -A FieldsNoValue_Stdtbl $(cat ${stdtbl_1key_asc} | awk 'match($1,/(^\\\S+=)$/,output) {print "\\"output[1]}')
					set -A FieldsNoValue_File $(cat ${file_1key_asc} | awk 'match($1,/(^\\\S+=)$/,output) {print "\\"output[1]}')
					
					if [[ ${FieldsNoValue_Stdtbl[0]} ]];
					then
						for (( i=0; i<${#FieldsNoValue_Stdtbl[*]}; i++ )) ; do
							cat ${file_1key_asc} | awk -v field="${FieldsNoValue_Stdtbl[$i]}" '{if ($0 !~ /=$/) {{ if ($0 ~ field) { match($1,/(^\\\S+=)(\S+$)/,output); print output[1] "\n" output[2] } else {print $0}}} else {print $0} }' 2>/dev/null > ${temp_file_1key_asc} && mv ${temp_file_1key_asc} ${file_1key_asc}
						done
					fi
					if [[ ${FieldsNoValue_File[0]} ]];
					then
						for (( i=0; i<${#FieldsNoValue_File[*]}; i++ )) ; do
							cat ${file_1key_asc} | awk -v field="${FieldsNoValue_File[$i]}" '{if ($0 !~ /=$/) {{ if ($0 ~ field) { match($1,/(^\\\S+=)(\S+$)/,output); print output[1] "\n" output[2] } else {print $0}}} else {print $0} }' 2>/dev/null > ${temp_stdtbl_1key_asc} && mv ${temp_stdtbl_1key_asc} ${stdtbl_1key_asc}
						done
					fi

				# Compare tables
				compare_stdtbl -unchanged ${stdtbl_1key_asc} ${file_1key_asc} | awk ' /-----\sUNCHANGED\sKEY/ {print "'${PathFile}';'${file}';'${line}';KEY_UNCHANGED"} /-----\sUPDATED\sKEY/ {print "'${PathFile}';'${file}';'${line}';KEY_UPDATED"}' >> ${fileskeys_csv}
				fi
			 done
		done
		if ${Option_Write} ;
		then
			print ""
			print " ---> See file(s) created with write option in "${DataPathRepportWrite}
			print ""
		fi
	fi
	#
	# case *.fcv in ${directoryOrFile} directory
	#
	nb_tot_file=$(ls ${directoryOrFile}/*.fcv 2>/dev/null | wc -l )
	if [ ${nb_tot_file} -ge 1 ] ;
	then
		cd ${directoryOrFile}	
		for file in $(ls -a *.fcv)
		do
			let num_file++
			print "File processing "$num_file"/"$nb_tot_file" : "$file

			fileName="$(echo ${file} | awk ' { n=split($0,rep,"/"); print rep[n] }')"
			fileExt="$(echo ${file} | awk ' { n=split($0,rep,"."); print rep[n] }')"

			# StdComp -A to obtain asctotb format
			stdcomp -A ${file} 2>/dev/null | grep -v "?compiled" | grep -v "SVN iden" | grep -v "SCCS ident" > ${temp_dir_fcv}

			echo ${file} | awk '{ if (match($0,/((([A-Z])+_)*FCV_.*$)/,m)) print m[0] }' |awk '{gsub("_", "#"); print $0}' | awk '{ gsub(".fcv",""); print $0 }' 2>/dev/null > ${keys_file}

			# Build temp.fcv file
			for line in $(cat ${keys_file})
			do
					tbtoasc -e "$line" 2>${temp_dir_tbtoasc_error_fcv} | grep -v "?compiled" | grep -v "SVN iden" | grep -v "SCCS ident" > ${temp_dir_tbtoasc_fcv}
			done
			#
			# Compare tables
			#
			if [[ $(cat ${temp_dir_tbtoasc_error_fcv} | awk '/^Error\s/ {print $0}') ]];
			then
				echo "${PathFile};${file};${line};KEY_ERROR" >> ${fileskeys_csv}
			else
				compare_stdtbl -unchanged ${temp_dir_tbtoasc_fcv} ${temp_dir_fcv} | awk ' /-----\sUNCHANGED\sKEY/ {print "'${PathFile}';'${file}';'${line}';KEY_UNCHANGED"} /-----\sUPDATED\sKEY/ {print "'${PathFile}';'${file}';'${line}';KEY_UPDATED"}' >> ${fileskeys_csv}
			fi
		done
	fi

	# Adding statistical columns in fileskeys_csv
	cat ${fileskeys_csv}| awk -F ";" '{ if (NR>1)
											{allfields[NR]=$0;
											field2[NR]=$2;
											field3[NR]=$3;
											doublefield3[$3]++;
											doublefield2[$2]++; 
											doublefield23[$2"-"$3]++;
											doublefield24[$2"-"$4]++;
											listdoublefield2[$3]= $2" | "listdoublefield2[$3]}
										else
											{print $0}} 
									END { for (numline=2 ; numline<= NR; numline++) 
											{print allfields[numline]";"doublefield2[field2[numline]]";",
											(doublefield2[field2[numline]]==doublefield24[field2[numline]"-KEY_UNCHANGED"])?"FILE_UNCHANGED;":"FILE_UPDATED;", 
											doublefield3[field3[numline]]";"listdoublefield2[field3[numline]]}}' > ${temp_csv} && mv ${temp_csv} ${fileskeys_csv}
	print ""
	print " ---> See the array result : 		"$fileskeys_csv
	print " ---> And the backup directory : 	"${temp_targz}
	print ""
fi	