FROM ruby:3.2

WORKDIR /app

COPY Gemfile* ./
RUN bundle install

COPY . .

CMD ["ruby", "bot.rb"]

ENV RACK_ENV=production
ENV NO_RACK=true
