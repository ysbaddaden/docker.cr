module Docker
  class SSHClient < IO
    include IO::Buffered

    def initialize(user : String?, host : String)
      args =
        if user
          {"-o", "ConnectTimeout=30", "-l", user, "--", host, "docker", "system", "dial-stdio"}
        else
          {"-o", "ConnectTimeout=30", "--", host, "docker", "system", "dial-stdio"}
        end
      @process = Process.new("ssh", args, input: :pipe, output: :pipe, error: :inherit)
      @closed = false
    end

    def unbuffered_read(slice : Bytes) : Int32
      check_open
      @process.output.read(slice)
    end

    def unbuffered_write(slice : Bytes) : Nil
      check_open
      @process.input.write(slice)
    end

    def unbuffered_flush : Nil
      # nothing
    end

    def unbuffered_rewind : Nil
      raise Socket::Error.new("Can't rewind")
    end

    def unbuffered_close : Nil
      return if @closed
      @closed = true
      @process.terminate
    end

    def closed? : Bool
      @closed
    end
  end
end
