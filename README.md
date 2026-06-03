# bouncer 🚪

A config-driven Discord bot for conference attendee verification. Verify tickets via [Tito](https://ti.to), assign Discord roles, and let attendees create trip/event channels — all driven by a single YAML config file.

Built for multi-year conferences. Adding a new year means adding a YAML block, not writing code.

## How it works

1. Attendee joins your Discord server and receives a welcome DM with instructions
2. They run `/join_YYYY` in your instructions channel with their ticket email and reference
3. Bouncer validates the ticket against Tito and assigns the appropriate Discord role
4. Attendees with a trip-enabled year can run `/make_trip_YYYY` to create community trip/event channels

## Setup

### 1. Create a Discord bot

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications)
2. Create a new application and add a bot
3. Enable these **Privileged Gateway Intents**: Server Members, Message Content
4. Invite the bot to your server with `bot` and `applications.commands` scopes and `Manage Roles`, `Manage Channels`, `Send Messages` permissions

### 2. Configure bouncer

Copy the example config and fill in your values:

```bash
cp bouncer.example.yml bouncer.yml
```

```yaml
conference:
  name: "My Conference"
  code_of_conduct_url: "https://myconference.com/code-of-conduct"
  instructions_channel: "instructions"

ticketing:
  provider: tito
  tito_slug: "my-conference"        # your Tito account/event slug
  release_types:
    speaker: "Speaker"              # substring match in release title
    stream: "Live Streaming"        # substring match in release title

years:
  - year: 2027
    active: true                    # registers /join_2027 slash command
    trips_enabled: true             # also registers /make_trip_2027
    roles:
      attendee: "111222333444555"
      stream: "222333444555666"
      speaker: "333444555666777"
    trips_category_id: "444555666777888"

  - year: 2026
    active: true
    trips_enabled: false
    roles:
      attendee: "..."
      stream: "..."
      speaker: "..."
```

`bouncer.yml` is gitignored — keep your Discord IDs out of version control.

### 3. Set environment variables

Copy `.env.example` to `.env` and fill in your values:

```
DISCORD_BOT_TOKEN=your_bot_token
DISCORD_CLIENT_ID=your_client_id
DISCORD_GUILD_ID=your_guild_id
TITO_SECRET=your_tito_api_token
```

### 4. Run the bot

```bash
bundle install
ruby bot.rb
```

## Deploying to Fly.io

```bash
fly launch
fly secrets set DISCORD_BOT_TOKEN=xxx DISCORD_CLIENT_ID=xxx DISCORD_GUILD_ID=xxx TITO_SECRET=xxx
```

Since `bouncer.yml` is gitignored, set it as a secret or mount it as a file on your Fly machine.

## Slash commands

| Command | Description |
|---------|-------------|
| `/join_YYYY` | Verify a Tito ticket and get your role for that year |
| `/make_trip_YYYY` | Create a community trip or event channel (if `trips_enabled: true`) |

## Adding a new year

Just add a block to `bouncer.yml`:

```yaml
years:
  - year: 2028
    active: true
    trips_enabled: true
    roles:
      attendee: "..."
      stream: "..."
      speaker: "..."
    trips_category_id: "..."
```

Restart the bot and the `/join_2028` and `/make_trip_2028` commands are registered automatically.

## Real-world example

[Deep Dish Swift](https://deepdishswift.com) uses bouncer for their annual iOS conference Discord. Check out [deep-dish-discord-bot](https://github.com/joshdholtz/deep-dish-discord-bot) to see a fully configured fork.
