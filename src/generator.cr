require "./generator/*"

class Generator
  include Schemas
  include Types
  include Paths

  def initialize(@swagger : Swagger)
  end
end
