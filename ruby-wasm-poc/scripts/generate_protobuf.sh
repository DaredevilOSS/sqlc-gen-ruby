#!/usr/bin/env bash

set -ex

replace_in_file () {
  text_to_replace=$1
  replace_with=$2
  filename=$3
  
  if [[ "$(uname -s)" == "Linux" ]]; then
    sed -i "s!${text_to_replace}!${replace_with}!g" "${filename}"
  else 
    sed -i '' "s!${text_to_replace}!${replace_with}!g" "${filename}"
  fi 
}

if wget -q --spider http://google.com; then
  buf generate --template buf.gen.yaml buf.build/sqlc/sqlc --path plugin/
  
  # File is a builtin class library in Ruby, and it's a bad practice to name a class as a builtin class.
  # Since we have limited direct control on the generated protobuf code, we fix it post-generate.
  replace_in_file 'File[[:blank:]]' 'OutputFile ' lib/gen/plugin/codegen_pb.rb
else
  echo "No internet connection - using pre-existing protobuf files.."
fi