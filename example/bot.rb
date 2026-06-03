require 'bouncer'

bouncer = Bouncer.new

# Add your custom commands here using the discordrb API.
# bouncer.bot is the raw Discordrb::Bot instance.
#
# Example: a /make_trip_2027 command that creates a channel
#
# TRIPS_CATEGORY_ID = ENV.fetch("DISCORD_TRIPS_CATEGORY_ID_2027")
#
# bouncer.bot.register_application_command(
#   :make_trip_2027,
#   "Create a trip or event channel for 2027",
#   server_id: ENV.fetch("DISCORD_GUILD_ID")
# ) do |cmd|
#   cmd.string("type", "Trip or Event", required: true, choices: { Trip: "trip", Event: "event" })
#   cmd.string("name", "Short channel name (e.g. millennium-park)", required: true)
#   cmd.string("date_and_time", "When is it? (e.g. Sunday 4pm)", required: true)
#   cmd.string("description", "What are you planning?", required: true)
# end
#
# bouncer.bot.application_command(:make_trip_2027) do |event|
#   event.defer(ephemeral: true)
#
#   type        = event.options["type"]
#   name        = event.options["name"].downcase.gsub(/[^a-z0-9-]/, "-").squeeze("-")
#   date        = event.options["date_and_time"]
#   description = event.options["description"]
#
#   category = event.server.channels.find { |c| c.id.to_s == TRIPS_CATEGORY_ID }
#   unless category
#     event.edit_response(content: "Trips category not found. Contact an admin.")
#     next
#   end
#
#   channel = event.server.create_channel(
#     "#{type}-#{name}",
#     0,
#     topic: "#{date} — #{description}",
#     parent_id: category.id
#   )
#
#   event.edit_response(content: "Created <##{channel.id}>!")
# end

bouncer.run
