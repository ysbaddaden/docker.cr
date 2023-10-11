require "socket"
require "uri"

module Docker
  class Client
    delegate :get, :post, :put, :patch, :head, to: http_client

    DEFAULT_HOST      = "unix:///var/run/docker.sock"
    DEFAULT_CERT_PATH = "#{ENV["HOME"]}/.docker"

    getter url : URI
    setter verify_tls : Bool?
    setter cert_path : String?

    @ssl_context : OpenSSL::SSL::Context?

    def initialize(@raw_url : String = ENV.fetch("DOCKER_HOST", DEFAULT_HOST))
      @url = URI.parse(@raw_url)
    end

    def url=(raw_url) : URI
      @url = URI.parse(raw_url)
    end

    def http_client : HTTP::Client
      # OPTIMIZE: memoize http client (beware of long connections failing)
      case @url.scheme
      when "unix"
        HTTP::Client.unix(@url.path)
      when "tcp", "http", "https"
        if verify_tls?
          HTTP::Client.new(@url.host.not_nil!, @url.port || 2376, true).tap do |client|
            client.ssl_context = ssl_context
          end
        else
          HTTP::Client.new(@url.host.not_nil!, @url.port || 2375, false)
        end
      else
        # TODO: support ssh (?)
        raise "unsupported protocol #{@url.scheme}"
      end
    end

    private def ssl_context
      @ssl_context ||= begin
        ctx = OpenSSL::SSL::Context::Client.new(LibSSL.tlsv1_method)
        ctx.private_key = key_file_path
        ctx.ca_file = ca_file_path
        ctx.certificate_file = cert_file_path
        ctx
      end
    end

    private def verify_tls?
      if @verify_tls.nil?
        @verify_tls = ENV.fetch("DOCKER_TLS_VERIFY", "0").to_i == 1
      else
        !!@verify_tls
      end
    end

    private def cert_path
      @cert_path ||= ENV.fetch("DOCKER_CERT_PATH", DEFAULT_CERT_PATH)
    end

    private def ca_file_path
      "#{cert_path}/ca.pem"
    end

    private def key_file_path
      "#{cert_path}/key.pem"
    end

    private def cert_file_path
      "#{cert_path}/cert.pem"
    end

    protected def unexpected_response(response : HTTP::Client::Response)
      raise "Unexpected HTTP response status #{response.status_code} (#{response.status})"
    end
  end
end
