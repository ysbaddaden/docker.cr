class Generator
  module Types
    def to_crystal_type(schema : Swagger::Schema, *, required : Bool, prefix : String) : String
      if (type = to_crystal_type(schema, prefix: prefix).presence) && !type.ends_with?("::")
        if !schema.nullable? || required
          type
        else
          "#{type}?"
        end
      else
        # STDERR.puts "WARN: failed to convert #{schema.inspect}"
        "JSON::Any"
      end
    end

    def to_crystal_type(param : Swagger::Parameter, name : String? = nil) : String
      ctype =
        case type = param.type?
        when "array"
          array_to_crystal(param, prefix: "")
          # when "object"
          #   object_to_crystal(param.schema, prefix: param.schema.title.to_s)
        when "boolean"
          "Bool"
        when "integer"
          integer_to_crystal(param.format)
        when "number"
          number_to_crystal(param.format)
        when "string"
          string_to_crystal(param.format)
        else
          if schema = param.schema?
            return to_crystal_type(schema, required: param.required, prefix: (schema.title || name).to_s)
          else
            # STDERR.puts "WARN: failed to convert #{param.inspect}"
            "JSON::Any"
          end
        end
      if param.required
        ctype
      else
        "#{ctype}?"
      end
    end

    def to_crystal_type(schema : Swagger::Schema, *, prefix : String) : String?
      if schema.ref? =~ %r{^#/definitions/(.+?)$}
        return $1
      end

      if subschemas = schema.allOf?
        gen_allof(prefix, subschemas)
        return prefix
      end

      case type = schema.type?
      when "array"
        array_to_crystal(schema, prefix: prefix)
      when "object"
        object_to_crystal(schema, prefix: prefix)
      when "boolean"
        "Bool"
      when "integer"
        integer_to_crystal(schema.format)
      when "number"
        number_to_crystal(schema.format)
      when "string"
        string_to_crystal(schema.format)
      else
        raise "unsupported schema #{schema}"
      end
    end

    protected def integer_to_crystal(format : String?) : String
      case format
      when "int8"
        "Int8"
      when "int16"
        "Int16"
      when "int32"
        "Int32"
      when "int64"
        "Int64"
      when "uint8"
        "UInt8"
      when "uint16"
        "UInt16"
      when "uint32"
        "UInt32"
      when "uint64"
        "UInt64"
      else
        "Int64"
      end
    end

    protected def number_to_crystal(format : String?) : String
      case format
      when "float"
        "Float32"
      when "double"
        "Float64"
      else
        "Float64"
      end
    end

    protected def string_to_crystal(format : String?) : String
      case format
      when "date"
        "Time" # "Date"
      when "date-time", "dateTime"
        "Time"
      when "binary"
        "Bytes"
      else
        "String"
      end
    end

    protected def array_to_crystal(schema, prefix) : String
      case items = schema.items
      in Array
        "Array(#{items.join(" | ")})"
      in Swagger::Schema
        # FIXME: required array.items
        "Array(#{to_crystal_type(items, prefix: prefix)})"
      end
    end

    protected def object_to_crystal(schema, prefix) : String
      unless schema.properties?
        case prop = schema.additionalProperties
        when Swagger::Schema
          type = to_crystal_type(prop, prefix: "").presence || "JSON::Any"
          return "Hash(String, #{type})"
        end
      end

      if prefix.presence
        properties = schema.properties? || {} of String => Swagger::Schema
        gen_type(prefix, properties, schema.required, !!schema.additionalProperties)
        prefix
      else
        "JSON::Any"
      end
    end

    def to_response_crystal_type(schema)
      case schema.type?
      when "array"
        if (items = schema.items?).is_a?(Swagger::Schema)
          return "Array(#{to_crystal_type(items, required: true, prefix: items.title.to_s)})"
        end
      end

      type = to_crystal_type(schema, required: true, prefix: schema.title.to_s)
      if type.ends_with?("::")
        "JSON::Any"
      else
        type
      end
    end
  end
end
