require 'discordrb'
require 'yaml'

module Bouncer
  class Bot
    attr_reader :bot

    def initialize(config_path = nil)
      config_path ||= ENV.fetch("BOUNCER_CONFIG", "bouncer.yml")
      config = YAML.load_file(config_path)

      @conference_name      = config.dig("conference", "name")
      @code_of_conduct_url  = config.dig("conference", "code_of_conduct_url")
      @instructions_channel = config.dig("conference", "instructions_channel") || "instructions"
      @commands             = config["commands"] || []

      %w[DISCORD_BOT_TOKEN DISCORD_CLIENT_ID DISCORD_GUILD_ID].each do |var|
        abort "Missing required environment variable: #{var}" unless ENV[var]
      end

      @bot = Discordrb::Bot.new(
        token:    ENV.fetch("DISCORD_BOT_TOKEN"),
        client_id: ENV.fetch("DISCORD_CLIENT_ID"),
        intents:  [:servers, :server_members, :server_messages, :server_message_content]
      )

      setup_ready
      setup_join_commands
      setup_message_guard
      setup_welcome_dm
    end

    def run
      @bot.run
    end

    private

    def setup_ready
      conference_name = @conference_name
      commands        = @commands

      @bot.ready do |event|
        puts "Bouncer is ready! Running as: #{conference_name}"
        puts "Commands: #{commands.map { |c| "/#{c["name"]}" }.join(", ")}"

        server = event.bot.servers[ENV.fetch("DISCORD_GUILD_ID").to_i]
        if server
          commands.each do |cmd_cfg|
            (cmd_cfg["roles"] || {}).each do |type, role_id|
              next if role_id.nil?
              unless server.roles.any? { |r| r.id.to_s == role_id.to_s }
                puts "WARNING: Role ID '#{role_id}' (#{type}) for command '/#{cmd_cfg["name"]}' not found on server"
              end
            end
          end
        end
      end
    end

    def setup_join_commands
      @commands.each do |cmd_cfg|
        cmd_name   = cmd_cfg["name"].to_sym
        cmd_desc   = cmd_cfg["description"] || "Verify your ticket"
        roles_cfg  = cmd_cfg["roles"] || {}
        verify_cfg = cmd_cfg["verify"] || {}
        conference_name = @conference_name

        @bot.register_application_command(cmd_name, cmd_desc, server_id: ENV["DISCORD_GUILD_ID"]) do |cmd|
          cmd.string("ticket_purchase_email", "Your email address used to purchase the ticket", required: true)
          cmd.string("ticket_reference", "Your ticket reference number (e.g. ABCD or ABCD-2)", required: true)
        end

        @bot.application_command(cmd_name) do |event|
          email     = event.options["ticket_purchase_email"]
          reference = event.options["ticket_reference"]

          event.defer(ephemeral: true)

          provider = verify_cfg["provider"]
          result = case provider
          when "tito"
            Bouncer::Providers::Tito.verify(email, reference, config: verify_cfg)
          else
            event.edit_response(content: "Unknown verification provider: #{provider}")
            next
          end

          unless result
            event.edit_response(content: "Invalid ticket. Please check your email and ticket reference.")
            next
          end

          member  = event.user.on(event.server)
          role_id = roles_cfg[result.type.to_s] || roles_cfg["default"]
          role    = event.server.roles.find { |r| r.id.to_s == role_id.to_s }

          if role.nil?
            event.edit_response(content: "Role not found. Please contact an admin.")
            next
          end

          speaker_role = nil
          if result.extra[:is_speaker] && roles_cfg["speaker"]
            speaker_role = event.server.roles.find { |r| r.id.to_s == roles_cfg["speaker"].to_s }
          end

          begin
            member.add_role(role)
            member.add_role(speaker_role) if speaker_role

            message = "Successfully joined #{conference_name} channels!"
            message += " Welcome, speaker!" if speaker_role
            event.edit_response(content: message)
          rescue => e
            event.edit_response(content: "Error assigning role: #{e.message}")
          end
        end
      end
    end

    def setup_message_guard
      instructions_channel = @instructions_channel

      @bot.message(in: instructions_channel) do |event|
        next if event.author.bot_account?
        next if event.author.on(event.server).permission?(:administrator)

        begin
          event.message.delete
        rescue => e
          puts "Could not delete message: #{e.message}"
        end
      end
    end

    def setup_welcome_dm
      conference_name      = @conference_name
      code_of_conduct_url  = @code_of_conduct_url
      instructions_channel = @instructions_channel
      commands             = @commands

      @bot.member_join do |event|
        instructions_ch      = event.server.text_channels.find { |c| c.name == instructions_channel }
        instructions_mention = instructions_ch ? "<##{instructions_ch.id}>" : "##{instructions_channel}"
        first_cmd            = commands.first&.dig("name")
        join_cmd             = first_cmd ? "`/#{first_cmd}`" : "`/join`"

        welcome  = "Welcome to #{conference_name}! We're excited to have you!\n\n"
        welcome += "To access the conference channels, head over to #{instructions_mention} and use the #{join_cmd} command with:\n"
        welcome += "- The email you used to purchase your ticket\n"
        welcome += "- Your ticket reference number (e.g., ABCD or ABCD-2)\n\n"
        welcome += "By joining, you agree to our Code of Conduct: #{code_of_conduct_url}\n\n" if code_of_conduct_url
        welcome += "See you inside!"

        begin
          event.user.dm(welcome)
        rescue Discordrb::Errors::NoPermission
          puts "Could not DM #{event.user.username} (DMs disabled)"
        rescue => e
          puts "Error sending welcome DM: #{e.message}"
        end
      end
    end
  end
end
