# bouncer

Config-driven Discord bot for conference attendee verification. Written in Ruby using discordrb.

## Run

```sh
bundle install
ruby bot.rb
```

Requires a `.env` file (or exported env vars) and a `bouncer.yml` config. See `.env.example` and `bouncer.example.yml`.

## Architecture

```
bot.rb              Entry point — loads config, registers slash commands, starts the bot
helpers/tito.rb     Providers::Tito — verifies tickets against the Tito API
bouncer.yml         Live config (gitignored — contains Discord role IDs)
bouncer.example.yml Template config with placeholder values
```

### Boot sequence

1. Load `bouncer.yml` into `CONFIG`
2. For each entry in `CONFIG["commands"]`, call `bot.register_application_command` to register a slash command with Discord
3. For each command, attach a handler that verifies the ticket and assigns roles
4. Register a `bot.message` handler to auto-delete non-admin messages in the instructions channel
5. Register a `bot.member_join` handler to DM new members with instructions
6. `bot.run` starts the event loop

### Slash command handler flow

```
/join_YYYY email + reference
       │
       ├── defer (ephemeral)
       │
       ├── Providers::Tito.verify(email, reference, config: verify_cfg)
       │       │
       │       ├── nil → "Invalid ticket" response
       │       └── Result(type:, extra: { is_speaker: }) →
       │
       ├── Look up primary role ID from roles_cfg[result.type] || roles_cfg["default"]
       ├── Look up optional speaker role if result.extra[:is_speaker] && roles_cfg["speaker"]
       └── member.add_role(role) + member.add_role(speaker_role) if present
```

## Key conventions

- **Config is the interface** — `bot.rb` never hardcodes years, slugs, or role IDs. Everything comes from `bouncer.yml`.
- **Commands array drives everything** — each entry in `commands` becomes exactly one slash command. Adding a command = adding a YAML block.
- **Provider dispatch** — `verify_cfg["provider"]` selects the backend. Currently only `"tito"`. New providers go in `helpers/<name>.rb` as `Providers::<Name>.verify(email, reference, config:)`.
- **Result type** — `Providers::Tito::Result` is a Struct with `:type` (Symbol) and `:extra` (Hash). `:type` maps to a role key; `:extra[:is_speaker]` triggers the bonus speaker role.
- **Speaker is additive** — the speaker `release_type` key does not set the primary type; it only sets `is_speaker: true`. The attendee gets both their primary role and the speaker role.
- **Reference normalization** — if the ticket reference has no `-N` suffix, `-1` is appended before the Tito lookup.
- **`BOUNCER_CONFIG` env var** — lets you point at a different config file without changing code. Useful for running multiple conferences from one bot instance or in tests.

## Adding a new provider

1. Create `helpers/<name>.rb` with a module `Providers::<Name>`
2. Implement `self.verify(email, reference, config:)` — return a `Result`-like struct or `nil`
3. Add `require_relative './helpers/<name>'` to `bot.rb`
4. Add a `when "<name>"` branch in the provider dispatch in `bot.rb`
5. Document the `verify:` config fields in `bouncer.example.yml`

## Config shape

```yaml
conference:
  name: "My Conference"
  code_of_conduct_url: "https://..."   # optional; included in welcome DM
  instructions_channel: "instructions" # channel name to auto-guard

commands:
  - name: join_2027                    # becomes /join_2027
    description: "..."
    verify:
      provider: tito
      slug: "my-conference"
      year: "2027"
      release_types:
        stream: "Live Streaming"       # release title substring → :stream type
        speaker: "Speaker"             # release title substring → is_speaker: true
    roles:
      default: "ROLE_ID"              # assigned to all verified attendees
      stream: "ROLE_ID"               # assigned when type == :stream
      speaker: "ROLE_ID"              # assigned in addition when is_speaker
```

## Forking

bouncer is a base. Conference-specific features (trip channel creation, custom slash commands, year-specific logic) belong in the fork, not here. Keep `bot.rb` and `helpers/` generic.

See [deep-dish-discord-bot](https://github.com/joshdholtz/deep-dish-discord-bot) for a real fork.

### Adding commands in a fork

The `COMMANDS.each` loop in `bot.rb` handles all config-driven `/join_*` commands. To add a custom command (e.g. `/make_trip_2027`), add `register_application_command` + `application_command` blocks anywhere before `bot.run`:

```ruby
# fork's bot.rb — after bouncer's COMMANDS.each block

bot.register_application_command(:make_trip_2027, "Create a trip channel", server_id: ENV.fetch("DISCORD_GUILD_ID")) do |cmd|
  cmd.string("name", "Channel name", required: true)
end

bot.application_command(:make_trip_2027) do |event|
  event.defer(ephemeral: true)
  # your logic here
end
```

Custom commands sit alongside bouncer's generated commands — Discord sees them all as slash commands on the same bot.
