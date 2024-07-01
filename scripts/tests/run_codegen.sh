#!/usr/bin/env bash

set -e
source .env

mapfile -t examples < <(find examples -name "*.rb" -exec dirname {} +)

config_file=$1
ruby_version=$2
generate_types=$3
generate_gemfile=$4

generated_files_cleanup() {
  for example_dir in "${examples[@]}"
  do
    echo "Deleting .rb & .rbs files in ${example_dir}"
    find "${example_dir}/" -type f -name "*.rb" -exec rm -f {} \;
    find "${example_dir}/" -type f -name "*.rbs" -exec rm -f {} \;
    if [ "${generate_gemfile}" = "true" ]; then
      echo "Deleting Gemfile file" && rm "${example_dir}/Gemfile"
    fi
  done
}

change_config() {
  for ((i=0; i<${#examples[@]}; i++)); do
    echo "Changing configuration for project ${example_dir}" 
    yq -i "
      .sql[${i}].codegen[0].options.rubyVersion = \"${ruby_version}\" |
      .sql[${i}].codegen[0].options.generateTypes = ${generate_types} |
      .sql[${i}].codegen[0].options.generateGemfile = ${generate_gemfile}
    " "${config_file}"
    echo "${examples[i]} codegen config:" && yq ".sql[${i}].codegen[0]" "${config_file}"
  done
}

#check_gemfile() {
#  for example_dir in "${examples[@]}"
#  do
#    echo "Checking Gemfile generated"
#    if [ ! -f "${example_dir}/Gemfile" ]; then
#      echo "Assertion failed: A Gemfile is not present in the directory ${example_dir}."
#      return 1
#    fi
#  done
#}

#check_project_compiles() {
#  if [ "${generate_csproj}" = "true" ]; then
#    for example_dir in "${examples[@]}"
#    do
#      echo "Checking ${example_dir} project compiles"
#      dotnet build "${example_dir}/"
#    done
#  fi
#}

generated_files_cleanup && change_config
sqlc -f "${config_file}" generate

#test_functions=("check_csproj_file" "check_project_compiles")
#for test_function in "${test_functions[@]}"; do
#  ${test_function}
#  status_code=$?
#  if [ ${status_code} -ne 0 ]; then
#    echo "Function ${test_function} failed with status code ${status_code}"
#    exit "${status_code}"
#  fi
#  echo "Test ${test_function} passed"
#done