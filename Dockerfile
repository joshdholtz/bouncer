FROM ruby:3.3-slim

RUN apt-get update -qq && apt-get install -y build-essential libssl-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

COPY . .

CMD ["ruby", "bot.rb"]
