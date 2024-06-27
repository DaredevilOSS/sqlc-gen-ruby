#!/usr/bin/env bash

set -e

doc_file=$1

examples_cnt=$(yq ".sql | length" sqlc.ci.yaml)
examples_doc="# Examples"

for ((i = 0 ; i < "${examples_cnt}" ; i++ )); do 
    engine_name=$(yq ".sql[${i}].engine" sqlc.ci.yaml)
    schema_file=$(yq ".sql[${i}].schema" sqlc.ci.yaml)
    query_files=$(yq ".sql[${i}].queries" sqlc.ci.yaml)
    driver=$(yq ".sql[${i}].codegen[0].options.driver" sqlc.ci.yaml)
    test_file="end2end_${driver}.rb"
    
    examples_doc+="
## Engine \`${engine_name}\`: [examples/${driver}](../examples/${driver})

### [Schema](../${schema_file}) | [Queries](../${query_files}) | [End2End Test](../tests/${test_file})

### Config
\`\`\`yaml
$(yq ".sql[${i}].codegen[${0}].options" sqlc.ci.yaml)
\`\`\`
"
done

echo "${examples_doc}" > "${doc_file}"