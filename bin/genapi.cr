require "swagger"
require "../src/generator"

# fixes a definition error in v1.41 and prior
def fix_network_operations(document)
  if params = document.paths["/networks/{id}/connect"]?.try(&.post).try(&.parameters)
    if param = params.find { |x| x.name == "container" }
      param.schema.title = "NetworkConnectRequest"
    end
  end

  if params = document.paths["/networks/{id}/disconnect"]?.try(&.post).try(&.parameters)
    if param = params.find { |x| x.name == "container" }
      param.schema.title = "NetworkDisconnectRequest"
    end
  end
end

def fix_services_inspect_previous_spec(document)
  properties = document.definitions["Service"].properties
  properties["PreviousSpec"] ||= properties["Spec"].dup
end

document = Swagger.from_file(ARGV[0])
fix_network_operations(document) if document.info.version.to_s < "1.42"
fix_services_inspect_previous_spec(document)

generator = Generator.new(document)

# TODO: Create schema modules to better support allOf (mixins)
# TODO: Some schema properties may need to specify a converter (e.g. `date`, `bytes`).

# 1. prepare global types
document.definitions.try &.each do |name, schema|
  generator.gen_type(name, schema)
end

# 2. prepare types for operations (requests)
document.paths.try &.each do |name, operation|
  generator.gen_path(name, operation)
end

# 2. prepare types for request bodies
generator.paths.each do |path|
  path.operation.arguments("body").each do |param|
    generator.to_crystal_type(param, param.schema.title.presence || path.operation.id)
  end
end

def simplify(type : String)
  type.gsub("::Docker::", "")
end

def sanitize_var_name(name : String)
  var_name = name
    .gsub("IPv4", "IPV4")
    .gsub("IPv6", "IPV6")
    .underscore
    .gsub(/[^_a-z0-9]/, '_')

  case var_name
  when "until"
    "_until"
  when "link_local_i_ps"
    "link_local_ips"
  else
    var_name
  end
end

# ACTUAL CODE GENERATION

puts "#########################################################################"
puts "#     WARNING: this file was generated automatically, do not modify     #"
puts "#########################################################################"
puts
puts "require \"json\""
puts "require \"uri\""
puts
puts "module Docker"

generator.aliases.each do |name, type|
  print "  alias "
  print name
  print " = "
  puts type
  puts
end

generator.enums.each do |name, constants|
  puts "  enum #{name}"
  constants.each do |constant|
    print "    "
    puts constant
  end
  puts "  end"
  puts
end

types = generator.definitions.keys.sort!

types.each_with_index do |type_name, i|
  mod = generator.definitions[type_name]
  next if mod.name == "ErrorResponse"

  puts unless i == 0
  puts "  class #{mod.name}"
  puts "    include JSON::Serializable"
  puts "    include JSON::Serializable::Unmapped" if mod.allow_unmapped?

  unless mod.properties.empty?
    mod.properties.each do |prop_key, prop_type|
      ivar_name = sanitize_var_name(prop_key)

      puts
      puts "    @[JSON::Field(key: \"#{prop_key}\")]" # unless prop_key == ivar_name
      puts "    property! #{ivar_name} : #{prop_type}"
    end

    puts
    print "    def initialize("
    mod.arguments.each_with_index do |(prop_key, prop_type, nilable), j|
      print ", " unless j == 0
      print '@'
      print sanitize_var_name(prop_key)
      print " : "
      print prop_type
      print " = nil" if nilable
    end
    puts ')'
    puts "    end"
  end

  puts "  end"
end

# TODO: generate mixin types that include the referred schemas (allOf)

puts
puts "  class Client"

generator.paths.each_with_index do |path, i|
  return_types = path.operation.responses
    .compact_map { |(response_type, codes)| response_type.presence if codes.first < 400 }

  return_type =
    case return_types.size
    when 0
      "Nil"
    when 1
      type = return_types.first
      #if type == "Bytes"
      #  path.nilable? ? "IO?" : "IO"
      #else
        path.nilable? ? "#{type}?" : type
      #end
    else
      type = return_types.join(" | ")
      path.nilable? ? "#{type} | Nil" : type
    end

  puts unless i == 0

  # generate the method definition / signature
  print "    def "
  print path.to_crystal_method
  print '('

  # TODO: support header arguments

  # TODO: method args & kwargs should have been preprocessed (making sure to
  #       have the required args first)
  path_params = path.operation.arguments("path")
  body_params = path.operation.arguments("body")
  query_params = path.operation.arguments("query")

  path_params.each_with_index do |param, j|
    print ", " unless j == 0
    print sanitize_var_name(param.name)
    print " : "
    print generator.to_crystal_type(param)
    print " = nil" unless param.required
  end

  body_params.each_with_index do |param, j|
    print ", " unless j == 0 && path_params.empty?

    print sanitize_var_name(param.name)
    print " : "
    print generator.to_crystal_type(param, param.schema.title.presence || path.operation.id)
    print " = nil" unless param.required
  end

  query_params.each_with_index do |param, j|
    if j == 0
      if path_params.empty? && body_params.empty?
        print "*, "
      else
        print ", *, "
      end
    else
      print ", "
    end

    print sanitize_var_name(param.name)
    print " : "
    print generator.to_crystal_type(param)
    print " = nil" unless param.required
  end

  print ") : "
  print return_type
  puts

  # generate the request (params, headers, body, actual request)
  resource = path.path.gsub(/\{(.+?)\}/, "\#{URI.encode_path_segment(\\1)}")

  unless query_params.empty?
    puts "      query = Params.build do |qs|"
    query_params.each do |param|
      print "        qs.add(#{param.name.inspect}, #{sanitize_var_name(param.name)}"
      print ", #{param.collectionFormat.inspect}" unless param.collectionFormat?.nil?
      print ')'
      print " unless #{sanitize_var_name(param.name)}.nil?" unless param.required?
      puts
    end
    puts "      end"
    resource = "#{resource}?\#{query}"
  end

  unless body_params.empty?
    puts "      headers = HTTP::Headers{\"Content-Type\" => \"application/json\"}"
  end

  # OPTIMIZE: 1. stream the HTTP response (client.get { |response| }
  # OPTIMIZE: 2. parse JSON from response.body_io directly
  # OPTIMIZE: 3. yield response when body is binary (Bytes)
  print "      "
  print path.method
  print '('
  print '"'
  print "#{document.basePath}#{resource}"
  print '"'

  unless body_params.empty?
    # there is only ever one body param and it's the actual request body
    print ", headers: headers, body: #{sanitize_var_name(body_params.first.name)}.to_json"
  end
  print ") do |response|"
  puts

  # process request responses
  puts "        case response.status_code"
  path.operation.responses.each do |(response_type, codes)|
    print "        when "
    codes.each_with_index do |code, j|
      print ", " unless j == 0
      print code
    end
    puts

    unless response_type.blank?
      if codes.first < 400
        if response_type == "Bytes"
          puts "          yield response.body_io"
        elsif response_type == "Bytes?"
          puts "          yield response.body_io?"
        else
          print "          "
          print simplify(response_type)
          puts ".from_json(response.body_io)"
        end
      else
        print "          raise "
        print simplify(response_type)
        puts ".from_json(response.body_io)"
      end
    end
  end
  puts "        else"
  puts "          unexpected_response(response)"
  puts "        end"
  puts "      end"
  puts "    end"
end
puts

puts "  end" # class Client
puts "end"   # module Docker
