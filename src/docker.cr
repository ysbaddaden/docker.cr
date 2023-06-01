require "json"
require "openssl"
require "http"
require "./core_ext/**"
require "./docker/*"

module Docker
  def self.client
    Docker::Client.new
  end
end
