module Tito
  TicketResult = Struct.new(:type, :is_speaker, keyword_init: true)

  def self.validate_ticket(ticket_email, ticket_reference, year:, config:)
    tito_secret = ENV["TITO_SECRET"]
    slug = config.dig("ticketing", "tito_slug")
    release_types = config.dig("ticketing", "release_types") || {}

    speaker_keyword = release_types["speaker"] || "Speaker"
    stream_keyword  = release_types["stream"]  || "Live Streaming"

    ticket_reference += "-1" unless ticket_reference.include?("-")

    url = "https://api.tito.io/v3/#{slug}/#{year}/tickets?page[size]=500&q=#{ticket_email}&expand=release"

    puts "Tito lookup: #{url}"

    begin
      resp = RestClient.get(url, headers: {
        accept: :json,
        authorization: "Bearer #{tito_secret}"
      })

      body = JSON.parse(resp.body)
      tickets = body["tickets"].select { |t| t["reference"] == ticket_reference }
      return nil unless tickets.size == 1

      release_title = tickets.first.dig("release", "title") || ""
      is_speaker = release_title.downcase.include?(speaker_keyword.downcase)

      if release_title.downcase.include?(stream_keyword.downcase)
        return TicketResult.new(type: :stream, is_speaker: is_speaker)
      end

      TicketResult.new(type: :ticket, is_speaker: is_speaker)
    rescue RestClient::NotFound
      nil
    end
  end
end
