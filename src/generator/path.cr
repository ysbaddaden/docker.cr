class Generator
  class Path
    getter method : String
    getter path : String
    getter operation : Operation

    def initialize(@method : String, @path : String, @operation : Operation, @nilable = false)
    end

    def nilable? : Bool
      @nilable
    end

    def to_crystal_method : String
      name = operation.id.not_nil!.underscore
      nilable? ? "#{name}?" : name
    end
  end
end
