require "socket"
require "uri"
require "./ssh_client"

module Docker
  class Client
    DEFAULT_HOST      = "unix:///var/run/docker.sock"
    DEFAULT_CERT_PATH = "#{ENV["HOME"]}/.docker"

    class Pool
      def initialize(&@block : -> HTTP::Client)
        @mutex = Mutex.new(:unchecked)
        @deque = Deque(HTTP::Client).new
      end

      def using(&)
        http_client = nil

        loop do
          http_client = @mutex.synchronize { @deque.shift? }
          http_client ||= @block.call

          begin
            return yield(http_client)
          rescue ex : IO::Error
            http_client = nil
            raise ex unless broken_pipe?(ex)
          else
            @mutex.synchronize { @deque << http_client if http_client }
          end
        end
      end

      private def broken_pipe?(ex) : Bool
        case err = ex.os_error
        in Errno
          err.epipe?
        in WasiError
          err.pipe?
        in WinError
          err.error_broken_pipe? || err.error_no_data?
        in Nil
          false
        end
      end
    end

    getter url : URI
    setter verify_tls : Bool?
    setter cert_path : String?

    @ssl_context : OpenSSL::SSL::Context?

    def initialize(@raw_url : String = ENV.fetch("DOCKER_HOST", DEFAULT_HOST))
      @url = URI.parse(@raw_url)
      @pool = Pool.new { new_http_client }
    end

    def url=(raw_url) : URI
      @url = URI.parse(raw_url)
    end

    {% for method in %w[get post put head delete] %}
      def {{method.id}}(*args, **kwargs)
        @pool.using do |http_client|
          http_client.{{method.id}}(*args, **kwargs)
        end
      end

      def {{method.id}}(*args, **kwargs, &)
        @pool.using do |http_client|
          http_client.{{method.id}}(*args, **kwargs) { |response| yield response }
        end
      end
    {% end %}

    private def new_http_client : HTTP::Client
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
      when "ssh"
        raise "ssh host connection is not valid: no host specified" unless host = @url.host
        raise "ssh host connection is not valid: plain-text password is not supported" if @url.password
        HTTP::Client.new(SSHClient.new(@url.user, host), host: "localhost")
      else
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
