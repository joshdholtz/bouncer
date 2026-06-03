require 'dotenv'
Dotenv.load

require_relative 'bouncer/version'
require_relative 'bouncer/providers/tito'
require_relative 'bouncer/bot'

module Bouncer
  def self.new(config_path = nil)
    Bot.new(config_path)
  end
end
