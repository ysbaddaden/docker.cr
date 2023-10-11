module Docker
  class ErrorResponse < Exception
    def self.new(pull : JSON::PullParser)
      message = nil
      pull.read_object do |key|
        if key == "message"
          message = pull.read_string
        end
      end
      new message.not_nil!
    end
  end
end
