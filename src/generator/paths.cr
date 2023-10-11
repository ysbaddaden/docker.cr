class Generator
  getter paths = Array(Path).new

  module Paths
    def gen_path(path : String, item : Swagger::PathItem) : Nil
      {% for method in %w[get post put patch delete head options] %}
        if op = item.{{method.id}}
          nilable = {{method}} == "get" && op.responses.has_key?("404")
          @paths << Path.new({{method}}, path, gen_operation(op, item.parameters, nilable), nilable)
        end
      {% end %}
    end

    private def gen_operation(op : Swagger::Operation, parameters : Array(Swagger::Parameter)?, nilable : Bool = false) : Operation
      Operation.new(
        op.operationId,
        gen_parameters(parameters, op.parameters),
        gen_responses(op.responses, nilable),
      )
    end

    private def gen_parameters(defaults : Array(Swagger::Parameter), parameters : Array(Swagger::Parameter))
      parameters.reduce(defaults.dup) do |a, e|
        if index = a.index { |x| x.name == e.name && x.in == e.in }
          a[index] = e
        else
          a << e
        end
        a
      end
    end

    private def gen_parameters(a : Array(Swagger::Parameter), b : Nil)
      a
    end

    private def gen_parameters(a : Nil, b : Array(Swagger::Parameter))
      b
    end

    private def gen_parameters(a : Nil, b : Nil)
      [] of Swagger::Parameter
    end

    private def gen_responses(responses, nilable)
      result = {} of String => Array(Int32)

      responses.each do |code, response|
        type =
          case response
          in Swagger::Response
            if schema = response.schema?
              gen_type(schema)
              to_response_crystal_type(response.schema)
            end
          in Swagger::Reference
            to_crystal_type(response)
          end

        if nilable && code == "404"
          type = nil
        end

        result[type.to_s] ||= [] of Int32
        result[type.to_s] << code.to_i
      end

      result
    end
  end
end
