FROM ruby:3.2

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1
# the end2end image only needs the gems used by the generated code, not the wasm build / codec test tooling
RUN bundle config --global without 'wasm_build codec_test'

WORKDIR /usr/src/app

COPY Gemfile Gemfile.lock Rakefile ./
RUN bundle install

COPY examples examples
COPY tests tests

RUN apt-get update && apt-get install sqlite3