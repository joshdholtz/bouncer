<div align="center">

# bouncer 🚪

**Config-driven Discord bot for conference attendee verification.**

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/joshdholtz/bouncer)
[![Deploy to Heroku](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy?template=https://github.com/joshdholtz/bouncer)

</div>

bouncer reads a YAML config file to register slash commands, verify tickets against a provider (like Tito), and assign Discord roles. Add a new year or event by adding a YAML block — no code changes needed.

```
$ /join_2027

  Checking your ticket...
  ✓ Successfully joined RubyConf 2027 channels! Welcome, speaker!
```

---

## Table of Contents

- [Quick Start](#quick-start)
- [How It Works](#how-it-works)
- [Config Reference](#config-reference)
  - [conference](#conference)
  - [commands](#commands)
  - [verify](#verify)
  - [roles](#roles)
- [Slash Commands](#slash-commands)
- [Environment Variables](#environment-variables)
- [Deploying](#deploying)
  - [Heroku](#heroku)
  - [Fly.io](#flyio)
  - [Railway](#railway)
  - [Render](#render)
  - [Docker](#docker)
- [Debugging](#debugging)
- [Adding a New Year](#adding-a-new-year)
- [Forking for Your Conference](#forking-for-your-conference)

---

## Quick Start

**1. Create a Discord bot**

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications)
2. Create a new application → **Bot** tab → copy the token
3. Enable **Privileged Gateway Intents**: Server Members, Message Content
4. Under **OAuth2 → URL Generator**, select scope `bot` + `applications.commands` with permissions: `Manage Roles`, `Manage Channels`, `Send Messages`, `Manage Messages`
5. Open the generated URL and invite the bot to your server

> **Important:** The bot's role must be positioned **above** any roles it manages in your server's role hierarchy.

**2. Add bouncer to your Gemfile**

```ruby
gem 'bouncer', github: 'joshdholtz/bouncer'
```

```bash
bundle install
```

**3. Create a `bot.rb`**

```ruby
require 'bouncer'
Bouncer.new.run
```

**4. Configure bouncer**

```bash
cp bouncer.example.yml bouncer.yml
```

Fill in your Discord role IDs, Tito slug, and conference name.

**5. Set environment variables**

```bash
cp .env.example .env
```

```sh
DISCORD_BOT_TOKEN=your_bot_token
DISCORD_CLIENT_ID=your_client_id
DISCORD_GUILD_ID=your_guild_id
TITO_SECRET=your_tito_api_token
```

**6. Run**

```bash
ruby bot.rb
```

---

## How It Works

1. Attendee joins your Discord server and receives a welcome DM with instructions
2. They run `/join_YYYY` in your `#instructions` channel with their ticket email and reference number
3. bouncer validates the ticket against the configured provider (e.g. Tito)
4. The ticket's release title is matched against `release_types` to determine the role
5. The attendee receives their role and can access the conference channels

```
attendee runs /join_2027
       │
       ▼
  verify ticket (Tito API)
       │
       ├── not found → "Invalid ticket"
       │
       └── found → match release title → assign role
                                       └── is_speaker? → also assign speaker role
```

bouncer also auto-deletes non-admin messages posted directly in the instructions channel, keeping it clean.

---

## Config Reference

```yaml
conference:
  name: "My Conference"
  code_of_conduct_url: "https://myconference.com/code-of-conduct"
  instructions_channel: "instructions"

commands:
  - name: join_2027
    description: "Join 2027 conference channels"
    verify:
      provider: tito
      slug: "my-conference"
      year: "2027"
      release_types:
        stream: "Live Streaming"
        speaker: "Speaker"
    roles:
      default: "ATTENDEE_ROLE_ID"
      stream: "STREAM_ROLE_ID"
      speaker: "SPEAKER_ROLE_ID"
```

---

### `conference`

Top-level conference metadata.

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Conference name, used in welcome messages |
| `code_of_conduct_url` | no | Included in the welcome DM if set |
| `instructions_channel` | no | Channel name to guard (default: `"instructions"`) |

---

### `commands`

Array of slash commands to register. Each entry becomes one `/name` command in Discord.

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Slash command name (e.g. `join_2027`) |
| `description` | no | Shown in the Discord command picker |
| `verify` | yes | Verification provider config (see below) |
| `roles` | yes | Role IDs to assign based on ticket type |

---

### `verify`

Per-command verification config. The `provider` field selects the backend.

#### Tito

```yaml
verify:
  provider: tito
  slug: "my-conference"    # your Tito account slug
  year: "2027"             # the Tito event slug (usually the year)
  release_types:
    stream: "Live Streaming"   # substring match in release title → :stream type
    speaker: "Speaker"         # substring match → sets is_speaker: true
```

| Field | Description |
|-------|-------------|
| `provider` | `tito` |
| `slug` | Tito account/org slug |
| `year` | Tito event slug |
| `release_types` | Map of type name → release title substring. The special key `speaker` sets an extra speaker role flag rather than changing the primary type. |

The `ticket_reference` input accepts both `ABCD` and `ABCD-2` formats. If no `-N` suffix is provided, `-1` is appended automatically — `ABCD` becomes `ABCD-1`, but `ABCD-2` stays `ABCD-2`.

---

### `roles`

Discord role IDs to assign based on the verified ticket type.

```yaml
roles:
  default: "111222333444555"    # assigned to all verified attendees
  stream: "222333444555666"     # assigned when ticket type matches "stream" release_type
  speaker: "333444555666777"    # assigned in addition to primary role when is_speaker
```

| Key | Description |
|-----|-------------|
| `default` | Fallback role — always assigned if no other type matches |
| *(any release_type key)* | Assigned when the ticket's release title matches that type |
| `speaker` | Assigned in addition to the primary role when the ticket is a speaker ticket |

---

## Slash Commands

Each entry in `commands` registers one slash command with two inputs:

| Input | Description |
|-------|-------------|
| `ticket_purchase_email` | The email address used to buy the ticket |
| `ticket_reference` | The ticket reference number (e.g. `ABCD` or `ABCD-2`) |

Responses are ephemeral — only the attendee sees them.

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DISCORD_BOT_TOKEN` | yes | Bot token from the Developer Portal |
| `DISCORD_CLIENT_ID` | yes | Application client ID |
| `DISCORD_GUILD_ID` | yes | Discord server (guild) ID |
| `TITO_SECRET` | yes (Tito) | Tito API token |
| `BOUNCER_CONFIG` | no | Path to config file (default: `bouncer.yml`) |

---

## Deploying

bouncer is a long-running process with no HTTP server. Any platform that can run a Docker container or a background worker works.

`bouncer.yml` is gitignored — it contains your Discord role IDs. Each platform section below explains how to get it onto your host.

---

### Heroku

Click the **Deploy to Heroku** button at the top of this README. It reads `app.json` and prompts you for all required environment variables — including `BOUNCER_YML_B64`, which is your `bouncer.yml` encoded as base64.

Generate it before clicking deploy:

```bash
base64 < bouncer.yml
```

Paste the output into the `BOUNCER_YML_B64` field. The `Procfile` automatically decodes it to `bouncer.yml` at startup.

---

### Fly.io

**1. Launch**

```bash
fly launch --no-deploy
```

Edit the generated `fly.toml` — set `app` to your app name and `primary_region` to your preferred region.

**2. Set secrets**

```bash
fly secrets set \
  DISCORD_BOT_TOKEN=xxx \
  DISCORD_CLIENT_ID=xxx \
  DISCORD_GUILD_ID=xxx \
  TITO_SECRET=xxx
```

**3. Upload `bouncer.yml`**

```bash
fly secrets set BOUNCER_YML_B64="$(base64 < bouncer.yml)"
```

Then uncomment the `[processes]` block in `fly.toml` (it's already there, commented out):

**4. Deploy**

```bash
fly deploy
```

---

### Railway

**1. Fork this repo** and connect it to a new Railway project.

**2. Set environment variables** in the Railway dashboard:

```
DISCORD_BOT_TOKEN
DISCORD_CLIENT_ID
DISCORD_GUILD_ID
TITO_SECRET
```

**3. Add `bouncer.yml` as a config file**

In the Railway dashboard under **Variables**, add:

```
BOUNCER_CONFIG=/etc/bouncer/bouncer.yml
```

Then add a volume or use Railway's config file injection. The simplest approach is to base64-encode the config:

```bash
BOUNCER_YML_B64=$(base64 < bouncer.yml)
```

Set `BOUNCER_YML_B64` as a Railway variable. The `Procfile` included in this repo automatically decodes it to `bouncer.yml` at startup — Railway detects `Procfile` and runs the `worker` process.

---

### Render

Click the button at the top of this README, or go manually:

**1. Fork this repo** and connect it to Render.

**2. Deploy**

Render will detect `render.yaml` automatically. Fill in the secret environment variables in the Render dashboard:

```
DISCORD_BOT_TOKEN
DISCORD_CLIENT_ID
DISCORD_GUILD_ID
TITO_SECRET
```

**3. Add `bouncer.yml`**

In the Render dashboard, under **Secret Files**, add `bouncer.yml` mounted at `/etc/secrets/bouncer.yml`. The `render.yaml` already sets `BOUNCER_CONFIG` to point there.

Alternatively, set `BOUNCER_YML_B64` as an environment variable (base64-encoded config) and the startup command in `render.yaml` will decode it automatically.

---

### Docker

Build and run locally or on any container host:

```bash
docker build -t bouncer .

docker run -d \
  -e DISCORD_BOT_TOKEN=xxx \
  -e DISCORD_CLIENT_ID=xxx \
  -e DISCORD_GUILD_ID=xxx \
  -e TITO_SECRET=xxx \
  -v $(pwd)/bouncer.yml:/app/bouncer.yml \
  bouncer
```

The volume mount is the easiest way to get `bouncer.yml` into the container.

---

## Debugging

**Invalid ticket response** — check your bot's stdout logs. bouncer prints the Tito API URL for every lookup:

```
Tito lookup: https://api.tito.io/v3/my-conference/2027/tickets?...
```

If you see a Tito auth error, your `TITO_SECRET` is wrong or expired. If the URL looks right but returns no match, the email or reference doesn't match — confirm the attendee is searching by purchase email, not attendee email.

**Role not found** — on startup, bouncer checks all role IDs in `bouncer.yml` against your server and prints a warning for any that don't exist:

```
WARNING: Role ID '123456789' (default) from command 'join_2027' not found on server
```

**Messages not auto-deleting** — make sure the bot has `Manage Messages` permission in your instructions channel. Check `#instructions` channel permissions and the bot's role in your server hierarchy.

---

## Adding a New Year

Add a block to `bouncer.yml` and restart the bot. The slash command is registered automatically.

```yaml
commands:
  - name: join_2028
    description: "Join 2028 conference channels"
    verify:
      provider: tito
      slug: "my-conference"
      year: "2028"
      release_types:
        stream: "Live Streaming"
        speaker: "Speaker"
    roles:
      default: "ATTENDEE_ROLE_ID_2028"
      stream: "STREAM_ROLE_ID_2028"
      speaker: "SPEAKER_ROLE_ID_2028"
```

---

## Forking for Your Conference

bouncer handles ticket verification and role assignment. Everything else — trip channels, custom slash commands, event-specific logic — lives in your fork.

[Deep Dish Swift](https://deepdishswift.com) uses bouncer for their annual iOS conference Discord. Check out [deep-dish-discord-bot](https://github.com/joshdholtz/deep-dish-discord-bot) to see a fully configured fork.

### Adding custom slash commands

`Bouncer.new` returns a `Bot` instance. Call `bouncer.bot` to get the raw discordrb bot and register any additional commands before calling `bouncer.run`.

**Example: a `/make_trip_2027` command that creates a channel**

```ruby
require 'bouncer'

bouncer = Bouncer.new

TRIPS_CATEGORY_ID = ENV.fetch("DISCORD_TRIPS_CATEGORY_ID_2027")

bouncer.bot.register_application_command(:make_trip_2027, "Create a trip or event channel",
  server_id: ENV.fetch("DISCORD_GUILD_ID")) do |cmd|
  cmd.string("type", "Trip or Event", required: true, choices: { Trip: "trip", Event: "event" })
  cmd.string("name", "Short channel name (e.g. millennium-park)", required: true)
  cmd.string("date_and_time", "When is it? (e.g. Sunday 4pm)", required: true)
  cmd.string("description", "What are you planning?", required: true)
end

bouncer.bot.application_command(:make_trip_2027) do |event|
  event.defer(ephemeral: true)

  type        = event.options["type"]
  name        = event.options["name"].downcase.gsub(/[^a-z0-9-]/, "-").squeeze("-")
  date        = event.options["date_and_time"]
  description = event.options["description"]

  category = event.server.channels.find { |c| c.id.to_s == TRIPS_CATEGORY_ID }
  unless category
    event.edit_response(content: "Trips category not found. Contact an admin.")
    next
  end

  channel = event.server.create_channel(
    "#{type}-#{name}",
    0,                          # text channel
    topic: "#{date} — #{description}",
    parent_id: category.id
  )

  event.edit_response(content: "Created <##{channel.id}>!")
end
```

Then call `bouncer.run` at the end. `Bouncer.new` registers all `/join_*` commands from `bouncer.yml`; your `bouncer.bot` blocks add everything else.

See `example/bot.rb` in this repo for a full commented template.

---

## License

MIT
