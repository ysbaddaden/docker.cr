class Generator
  class Definition
    getter name : String
    getter properties : Hash(String, String)

    def initialize(
      @name : String,
      @properties : Hash(String, String),
      @allow_unmapped : Bool
    )
    end

    def allow_unmapped? : Bool
      @allow_unmapped
    end

    def arguments : Array({String, String, Bool})
      required = [] of {String, String, Bool}
      optional = [] of {String, String, Bool}

      properties.each do |prop_key, prop_type|
        if prop_type.includes?('?') || prop_type =~ /\bNil\b/
          optional << {prop_key, prop_type, true}
        else
          required << {prop_key, prop_type, false}
        end
      end

      required + optional
    end
  end
end
