# bouncer

Config-driven Discord bot for conference attendee verification. Distributed as a Ruby gem.

## Run (standalone)

```sh
bundle install
ruby bot.rb   # root bot.rb is just: require 'bouncer'; Bouncer.new.run
```

Requires a `.env` file (or exported env vars) and a `bouncer.yml` config. See `.env.example` and `bouncer.example.yml`.

## Architecture

```
lib/
  bouncer.rb                  Module entry point — loads dotenv, requires everything
  bouncer/
    version.rb                Bouncer::VERSION
    bot.rb                    Bouncer::Bot — config loader, discordrb setup, event handlers
    providers/
      tito.rb                 Bouncer::Providers::Tito — Tito API ticket verification

bouncer.gemspec               Gem spec
bot.rb                        Standalone entry point: Bouncer.new.run
example/bot.rb                Fork template showing how to add custom commands
bouncer.example.yml           Config template with placeholder values
```

## Boot sequence

1. `Bouncer.new(config_path)` loads `bouncer.yml` and calls `Bouncer::Bot.new`
2. `Bot#initialize` validates required env vars, instantiates `Discordrb::Bot`, calls four setup methods
3. `setup_join_commands` iterates `config["commands"]` — registers one slash command and handler per entry
4. `setup_message_guard` auto-deletes non-admin messages in the instructions channel
5. `setup_welcome_dm` DMs new members with instructions on join
6. `bouncer.run` calls `@bot.run` — starts the discordrb event loop

## Slash command handler flow

```
/join_YYYY email + reference
       │
       ├── defer (ephemeral)
       │
       ├── Bouncer::Providers::Tito.verify(email, reference, config: verify_cfg)
       │       │
       │       ├── nil → "Invalid ticket" response
       │       └── Result(type:, extra: { is_speaker: }) →
       │
       ├── Look up primary role ID from roles_cfg[result.type] || roles_cfg["default"]
       ├── Look up optional speaker role if result.extra[:is_speaker] && roles_cfg["speaker"]
       └── member.add_role(role) + member.add_role(speaker_role) if present
```

## Key conventions

- **`Bouncer.new` is the public API** — returns a `Bot` instance with `#bot` (raw discordrb) and `#run`
- **Config is the interface** — no years, slugs, or role IDs are hardcoded anywhere in the gem
- **Provider dispatch** — `verify_cfg["provider"]` selects the backend; new providers go in `lib/bouncer/providers/<name>.rb`
- **Result type** — `Providers::Tito::Result` is a Struct with `:type` (Symbol) and `:extra` (Hash). `:type` maps to a role key; `:extra[:is_speaker]` triggers the additive speaker role
- **Speaker is additive** — the `speaker` release_type sets `is_speaker: true`, not a primary type. The attendee gets both their primary role and the speaker role
- **Reference normalization** — if the ticket reference has no `-N` suffix, `-1` is appended before the Tito lookup
- **`BOUNCER_CONFIG` env var** — overrides the config file path (default: `bouncer.yml`)

## Adding a new provider

1. Create `lib/bouncer/providers/<name>.rb` with module `Bouncer::Providers::<Name>`
2. Implement `self.verify(email, reference, config:)` — return a `Result`-like struct or `nil`
3. Add `require_relative 'bouncer/providers/<name>'` to `lib/bouncer.rb`
4. Add a `when "<name>"` branch in `Bot#setup_join_commands`
5. Document the `verify:` config fields in `bouncer.example.yml`

## Using bouncer as a gem (fork pattern)

```ruby
# Gemfile
gem 'bouncer', github: 'joshdholtz/bouncer'  # or RubyGems once published

# bot.rb
require 'bouncer'

bouncer = Bouncer.new  # loads .env + bouncer.yml, sets up all join commands

# Add conference-specific commands via the raw discordrb bot
bouncer.bot.register_application_command(:make_trip_2027, "Create a trip channel",
  server_id: ENV.fetch("DISCORD_GUILD_ID")) do |cmd|
  cmd.string("name", "Channel name", required: true)
end

bouncer.bot.application_command(:make_trip_2027) do |event|
  event.defer(ephemeral: true)
  # your logic here
end

bouncer.run
```

See `example/bot.rb` for a full commented template and [deep-dish-discord-bot](https://github.com/joshdholtz/deep-dish-discord-bot) for a real fork.
