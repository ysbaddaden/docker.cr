class Generator
  class Operation
    getter id : String?
    getter parameters : Array(Swagger::Parameter)
    getter responses : Hash(String, Array(Int32))

    def initialize(
      @id : String?,
      @parameters : Array(Swagger::Parameter),
      @responses : Hash(String, Array(Int32))
    )
    end

    def arguments(location : String) : Array(Swagger::Parameter)
      parameters.select { |x| x.in == location }
    end
  end
end
