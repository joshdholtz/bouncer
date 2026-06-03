module Providers
  module Tito
    Result = Struct.new(:type, :extra, keyword_init: true)

    def self.verify(email, reference, config:)
      secret = ENV["TITO_SECRET"]
      slug   = config["slug"]
      year   = config["year"]
      release_types = config["release_types"] || {}

      reference += "-1" unless reference.include?("-")

      url = "https://api.tito.io/v3/#{slug}/#{year}/tickets?page[size]=500&q=#{email}&expand=release"
      puts "Tito lookup: #{url}"

      begin
        resp = RestClient.get(url, headers: {
          accept: :json,
          authorization: "Bearer #{secret}"
        })

        tickets = JSON.parse(resp.body)["tickets"].select { |t| t["reference"] == reference }
        return nil unless tickets.size == 1

        release_title = tickets.first.dig("release", "title") || ""

        type = :default
        release_types.each do |type_name, keyword|
          next unless type_name != "speaker"
          if release_title.downcase.include?(keyword.downcase)
            type = type_name.to_sym
            break
          end
        end

        speaker_keyword = release_types["speaker"]
        is_speaker = speaker_keyword && release_title.downcase.include?(speaker_keyword.downcase)

        Result.new(type: type, extra: { is_speaker: is_speaker })
      rescue RestClient::NotFound
        nil
      rescue RestClient::Unauthorized, RestClient::Forbidden => e
        puts "Tito auth error: #{e.message}"
        nil
      rescue RestClient::Exception => e
        puts "Tito API error (#{e.http_code}): #{e.message}"
        nil
      rescue StandardError => e
        puts "Tito request failed: #{e.message}"
        nil
      end
    end
  end
end
