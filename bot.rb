require 'rest-client'
require 'dotenv'
require 'discordrb'
require 'yaml'

require_relative './helpers/tito'

Dotenv.load

CONFIG = YAML.load_file(ENV.fetch("BOUNCER_CONFIG", "bouncer.yml"))

CONFERENCE_NAME       = CONFIG.dig("conference", "name")
CODE_OF_CONDUCT_URL   = CONFIG.dig("conference", "code_of_conduct_url")
INSTRUCTIONS_CHANNEL  = CONFIG.dig("conference", "instructions_channel") || "instructions"

YEARS = (CONFIG["years"] || []).select { |y| y["active"] }

trip_channel_cooldowns = {}

bot = Discordrb::Bot.new(
  token: ENV["DISCORD_BOT_TOKEN"],
  client_id: ENV["DISCORD_CLIENT_ID"],
  intents: [:servers, :server_members, :server_messages, :server_message_content]
)

bot.ready do
  puts "Bot is starting up..."

  10.times do |i|
    if bot.servers.empty?
      puts "Waiting for servers to cache (attempt #{i + 1}/10)..."
      sleep 2
    else
      break
    end
  end

  puts "\nBot is ready! Running as: #{CONFERENCE_NAME}"
  puts "Active years: #{YEARS.map { |y| y["year"] }.join(", ")}"
end

# Register slash commands dynamically per active year
YEARS.each do |year_cfg|
  year = year_cfg["year"]

  bot.register_application_command(:"join_#{year}", "Join #{year} channels", server_id: ENV["DISCORD_GUILD_ID"]) do |cmd|
    cmd.string("ticket_purchase_email", "Your email address used to purchase the ticket", required: true)
    cmd.string("ticket_reference", "Your ticket reference number - format can be ABCD or ABCD-#", required: true)
  end

  next unless year_cfg["trips_enabled"]

  bot.register_application_command(:"make_trip_#{year}", "Create a trip or event channel for #{year}", server_id: ENV["DISCORD_GUILD_ID"]) do |cmd|
    cmd.string("type", "Trip or Event", required: true, choices: { Trip: "trip", Event: "event" })
    cmd.string("name", "Short name for the channel (e.g. millennium-park)", required: true)
    cmd.string("date_and_time", "When is it? (e.g. Sunday 4pm)", required: true)
    cmd.string("description", "What are you planning?", required: true)
  end
end

# Wire up handlers dynamically per active year
YEARS.each do |year_cfg|
  year = year_cfg["year"]
  roles = year_cfg["roles"] || {}

  bot.application_command(:"join_#{year}") do |event|
    email  = event.options["ticket_purchase_email"]
    ticket = event.options["ticket_reference"]

    event.defer(ephemeral: true)

    result = Tito.validate_ticket(email, ticket, year: year.to_s, config: CONFIG)

    unless result
      event.edit_response(content: "Invalid ticket. Please check your email and ticket reference.")
      next
    end

    member = event.user.on(event.server)

    role_id = result.type == :stream ? roles["stream"] : roles["attendee"]
    role = event.server.roles.find { |r| r.id.to_s == role_id.to_s }

    if role.nil?
      event.edit_response(content: "Role not found. Please contact an admin.")
      next
    end

    speaker_role = nil
    if result.is_speaker && roles["speaker"]
      speaker_role = event.server.roles.find { |r| r.id.to_s == roles["speaker"].to_s }
    end

    begin
      member.add_role(role)
      member.add_role(speaker_role) if speaker_role

      message = if result.type == :stream
        "Successfully joined #{CONFERENCE_NAME} #{year} Live Stream Supporter channels!"
      else
        "Successfully joined #{CONFERENCE_NAME} #{year} channels!"
      end
      message += " Welcome, speaker!" if speaker_role

      event.edit_response(content: message)
    rescue => e
      event.edit_response(content: "Error assigning role: #{e.message}")
    end
  end

  next unless year_cfg["trips_enabled"]

  bot.application_command(:"make_trip_#{year}") do |event|
    type        = event.options["type"]
    name        = event.options["name"]
    date_and_time = event.options["date_and_time"]
    description = event.options["description"]

    event.defer(ephemeral: true)

    member   = event.user.on(event.server)
    role_ids = member.roles.map { |r| r.id.to_s }

    has_role = role_ids.include?(roles["attendee"].to_s) ||
               role_ids.include?(roles["stream"].to_s)

    unless has_role
      event.edit_response(content: "You need to be a #{year} attendee to create trip channels. Use `/join_#{year}` first!")
      next
    end

    today = Date.today
    if trip_channel_cooldowns[event.user.id] == today
      event.edit_response(content: "You've already created a trip channel today. Try again tomorrow!")
      next
    end

    trips_category_id = year_cfg["trips_category_id"]
    category = event.server.categories.find { |c| c.id.to_s == trips_category_id.to_s }
    if category.nil?
      event.edit_response(content: "Trips category not found. Please contact an admin.")
      next
    end

    channel_name = "#{type}-#{name}"
      .downcase
      .gsub(/[^a-z0-9\s-]/, "")
      .gsub(/\s+/, "-")
      .gsub(/-+/, "-")
      .gsub(/^-|-$/, "")

    if channel_name.empty? || channel_name == type
      event.edit_response(content: "Please provide a valid name using letters or numbers.")
      next
    end

    if channel_name.length > 100
      event.edit_response(content: "That name is too long! Please keep it under #{100 - type.length - 1} characters.")
      next
    end

    begin
      new_channel = event.server.create_channel(channel_name, 0, parent: category)

      new_channel.send_message(
        "**🗺️ New #{type} created by #{event.user.mention}!**\n" \
        "**When:** #{date_and_time}\n" \
        "**Description:** #{description}"
      )

      trip_channel_cooldowns[event.user.id] = today

      event.edit_response(content: "Created <##{new_channel.id}>! Head over there to start planning.")
    rescue => e
      event.edit_response(content: "Error creating channel: #{e.message}")
    end
  end
end

# Auto-delete non-admin messages in the instructions channel
bot.message(in: INSTRUCTIONS_CHANNEL) do |event|
  next if event.author.bot_account?

  member = event.author.on(event.server)
  next if member.permission?(:administrator)

  begin
    event.message.delete
  rescue => e
    puts "Could not delete message in #{INSTRUCTIONS_CHANNEL}: #{e.message}"
  end
end

# Welcome DM on member join
bot.member_join do |event|
  user = event.user

  instructions_ch = event.server.text_channels.find { |c| c.name == INSTRUCTIONS_CHANNEL }
  instructions_mention = instructions_ch ? "<##{instructions_ch.id}>" : "##{INSTRUCTIONS_CHANNEL}"

  active_year = YEARS.first&.dig("year")
  join_cmd    = active_year ? "`/join_#{active_year}`" : "`/join`"

  welcome = "Welcome to #{CONFERENCE_NAME}! We're excited to have you!\n\n" \
            "To access the conference channels, head over to #{instructions_mention} and use the #{join_cmd} command with:\n" \
            "- The email you used to purchase your ticket\n" \
            "- Your ticket reference number (e.g., ABCD or ABCD-2)\n\n"

  welcome += "By joining, you agree to our Code of Conduct: #{CODE_OF_CONDUCT_URL}\n\n" if CODE_OF_CONDUCT_URL

  welcome += "See you inside!"

  begin
    user.dm(welcome)
    puts "Sent welcome DM to: #{user.username}"
  rescue Discordrb::Errors::NoPermission
    puts "Could not DM user (DMs disabled): #{user.username}"
  rescue => e
    puts "Error sending welcome DM: #{e.message}"
  end
end

bot.run
