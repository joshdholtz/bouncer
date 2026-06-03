# If BOUNCER_YML_B64 is set, decode it to bouncer.yml before starting.
# Set it with: heroku config:set BOUNCER_YML_B64="$(base64 < bouncer.yml)"
worker: sh -c 'if [ -n "$BOUNCER_YML_B64" ]; then echo "$BOUNCER_YML_B64" | base64 -d > bouncer.yml; fi && bundle exec ruby bot.rb'
