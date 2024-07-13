FROM ruby:3.2

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

WORKDIR /usr/src/app

COPY Gemfile Gemfile.lock Rakefile ./
RUN bundle install

COPY examples examples
COPY tests tests

RUN apt-get update && apt-get install sqlite3