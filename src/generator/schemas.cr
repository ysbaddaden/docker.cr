class Generator
  module Schemas
    getter aliases = Hash(String, String).new
    getter definitions = Hash(String, Definition).new
    getter enums = Hash(String, Array(String)).new

    def gen_type(schema : Swagger::Schema) : Nil
      if schema.ref?
        return
      end

      if subschemas = schema.allOf?
        # STDERR.puts [:gen_type, :allOf, schema]
        return
      end

      case schema.type?
      when "array"
        items = schema.items
        gen_type(items) if items.is_a?(Swagger::Schema)
      when "object"
        # FIXME: should call a method to generate a type name when missing
        if title = schema.title
          gen_type(title, schema)
        else
          # STDERR.puts [:gen_type, schema]
        end
      end
    end

    def gen_type(name : String, schema : Swagger::Schema) : Nil
      case schema.type?
      when "object"
        if properties = schema.properties?
          gen_type(name, properties, schema.required, !!schema.additionalProperties)
        elsif subschemas = schema.allOf?
          gen_allof(name, subschemas)
        else
          case prop = schema.additionalProperties
          when Bool
            @aliases[name] = "Hash(String, JSON::Any)"
          when Swagger::Schema
            if type = to_crystal_type(prop, prefix: "")
              @aliases[name] = "Hash(String, #{type})"
            else
              @aliases[name] = "Hash(String, JSON::Any)"
            end
          end
        end
      when "array"
        if type = to_crystal_type(schema, prefix: name.gsub(/s$/, ""))
          @aliases[name] = type
        end
      when "integer"
        @aliases[name] = integer_to_crystal(schema.format)
      when "string"
        if schema.enum?
          gen_enum(name, schema)
        else
          # STDERR.puts schema.inspect
        end
      else
        if subschemas = schema.allOf?
          gen_allof(name, subschemas)
        else
          # STDERR.puts [:gen_type, schema]
        end
        # if crystal_type = to_crystal_type(schema, prefix: name)
        #   ALIASES[name] = crystal_type
        # end
      end
    end

    def gen_enum(name : String, schema : Swagger::Schema) : Nil
      @enums[name] = schema.enum.map(&.as_s?.try(&.camelcase)).compact
    end

    def gen_type(
      name : String,
      properties : Hash(String, Swagger::Schema),
      required : Array(String)?,
      additionalProperties : Bool
    ) : Nil
      @definitions[name] = Definition.new(
        name,
        gen_properties(properties, name, required),
        additionalProperties
      )
    end

    private def gen_allof(name, subschemas)
      properties = {} of String => Swagger::Schema
      required = nil
      additionalProperties = false

      subschemas.not_nil!.each do |subschema|
        if _ref = subschema.ref?
          ref = @swagger.find(_ref)
          props = ref.responds_to?(:schema) ? ref.schema.properties : ref.properties
          props.each { |k, v| properties[k] = v }
        elsif subschema.type == "object"
          if subschema.properties?
            subschema.properties.each { |k, v| properties[k] = v }
            additionalProperties ||= !!subschema.additionalProperties
            required = subschema.required
          else
            additionalProperties = true
          end
        else
          # TODO: ???
        end
      end

      gen_type(name, properties, required, additionalProperties)
    end

    private def gen_properties(props, prefix, required)
      properties = {} of String => String
      required ||= [] of String

      props.each do |name, schema|
        properties[name] = to_crystal_type(
          schema,
          prefix: "#{prefix}::#{name.camelcase}",
          required: required.includes?(name)
        )
      end

      properties
    end
  end
end
