require 'rest-client'
require 'dotenv'
require 'discordrb'
require 'yaml'

require_relative './helpers/tito'

Dotenv.load

CONFIG = YAML.load_file(ENV.fetch("BOUNCER_CONFIG", "bouncer.yml"))

CONFERENCE_NAME      = CONFIG.dig("conference", "name")
CODE_OF_CONDUCT_URL  = CONFIG.dig("conference", "code_of_conduct_url")
INSTRUCTIONS_CHANNEL = CONFIG.dig("conference", "instructions_channel") || "instructions"
COMMANDS             = CONFIG["commands"] || []

%w[DISCORD_BOT_TOKEN DISCORD_CLIENT_ID DISCORD_GUILD_ID].each do |var|
  abort "Missing required environment variable: #{var}" unless ENV[var]
end

bot = Discordrb::Bot.new(
  token: ENV.fetch("DISCORD_BOT_TOKEN"),
  client_id: ENV.fetch("DISCORD_CLIENT_ID"),
  intents: [:servers, :server_members, :server_messages, :server_message_content]
)

bot.ready do |event|
  puts "Bot is ready! Running as: #{CONFERENCE_NAME}"
  puts "Commands: #{COMMANDS.map { |c| "/#{c["name"]}" }.join(", ")}"

  server = event.bot.servers[ENV.fetch("DISCORD_GUILD_ID").to_i]
  if server
    COMMANDS.each do |cmd_cfg|
      (cmd_cfg["roles"] || {}).each do |type, role_id|
        next if role_id.nil? || role_id.to_s.start_with?("ROLE_ID", "ATTENDEE", "STREAM", "SPEAKER")
        unless server.roles.any? { |r| r.id.to_s == role_id.to_s }
          puts "WARNING: Role ID '#{role_id}' (#{type}) from command '#{cmd_cfg["name"]}' not found on server"
        end
      end
    end
  end
end

# Register and handle one slash command per config entry
COMMANDS.each do |cmd_cfg|
  cmd_name = cmd_cfg["name"].to_sym
  cmd_desc = cmd_cfg["description"] || "Verify your ticket"
  roles_cfg = cmd_cfg["roles"] || {}
  verify_cfg = cmd_cfg["verify"] || {}

  bot.register_application_command(cmd_name, cmd_desc, server_id: ENV["DISCORD_GUILD_ID"]) do |cmd|
    cmd.string("ticket_purchase_email", "Your email address used to purchase the ticket", required: true)
    cmd.string("ticket_reference", "Your ticket reference number (e.g. ABCD or ABCD-2)", required: true)
  end

  bot.application_command(cmd_name) do |event|
    email     = event.options["ticket_purchase_email"]
    reference = event.options["ticket_reference"]

    event.defer(ephemeral: true)

    provider = verify_cfg["provider"]
    result = case provider
    when "tito"
      Providers::Tito.verify(email, reference, config: verify_cfg)
    else
      event.edit_response(content: "Unknown verification provider: #{provider}")
      next
    end

    unless result
      event.edit_response(content: "Invalid ticket. Please check your email and ticket reference.")
      next
    end

    member = event.user.on(event.server)

    # Assign primary role based on ticket type
    role_id = roles_cfg[result.type.to_s] || roles_cfg["default"]
    role = event.server.roles.find { |r| r.id.to_s == role_id.to_s }

    if role.nil?
      event.edit_response(content: "Role not found. Please contact an admin.")
      next
    end

    # Assign optional speaker role
    speaker_role = nil
    if result.extra[:is_speaker] && roles_cfg["speaker"]
      speaker_role = event.server.roles.find { |r| r.id.to_s == roles_cfg["speaker"].to_s }
    end

    begin
      member.add_role(role)
      member.add_role(speaker_role) if speaker_role

      message = "Successfully joined #{CONFERENCE_NAME} channels!"
      message += " Welcome, speaker!" if speaker_role
      event.edit_response(content: message)
    rescue => e
      event.edit_response(content: "Error assigning role: #{e.message}")
    end
  end
end

# Auto-delete non-admin messages in the instructions channel
bot.message(in: INSTRUCTIONS_CHANNEL) do |event|
  next if event.author.bot_account?
  next if event.author.on(event.server).permission?(:administrator)

  begin
    event.message.delete
  rescue => e
    puts "Could not delete message: #{e.message}"
  end
end

# Welcome DM on member join
bot.member_join do |event|
  instructions_ch = event.server.text_channels.find { |c| c.name == INSTRUCTIONS_CHANNEL }
  instructions_mention = instructions_ch ? "<##{instructions_ch.id}>" : "##{INSTRUCTIONS_CHANNEL}"

  first_cmd = COMMANDS.first&.dig("name")
  join_cmd  = first_cmd ? "`/#{first_cmd}`" : "`/join`"

  welcome = "Welcome to #{CONFERENCE_NAME}! We're excited to have you!\n\n" \
            "To access the conference channels, head over to #{instructions_mention} and use the #{join_cmd} command with:\n" \
            "- The email you used to purchase your ticket\n" \
            "- Your ticket reference number (e.g., ABCD or ABCD-2)\n\n"

  welcome += "By joining, you agree to our Code of Conduct: #{CODE_OF_CONDUCT_URL}\n\n" if CODE_OF_CONDUCT_URL
  welcome += "See you inside!"

  begin
    event.user.dm(welcome)
  rescue Discordrb::Errors::NoPermission
    puts "Could not DM #{event.user.username} (DMs disabled)"
  rescue => e
    puts "Error sending welcome DM: #{e.message}"
  end
end

bot.run
