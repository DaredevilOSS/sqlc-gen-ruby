# frozen_string_literal: true

module SqlcGenRuby
  # Small helpers for building indented Ruby / RBS source text.
  module Code
    MAX_ELEMENTS_PER_LINE = 5

    module_function

    INDENT = '  '

    # Indents every non-blank line (blank lines stay empty: no trailing whitespace).
    def indent(text)
      text.split("\n", -1).map { |l| l.strip.empty? ? '' : "#{INDENT}#{l}" }.join("\n")
    end

    def comma_join(items, wrap: false)
      return items.join(', ') if items.size < MAX_ELEMENTS_PER_LINE && !wrap

      "\n#{indent(items.join(",\n"))}\n"
    end

    # GetAuthor => get_author, userId => user_id, GetByID => get_by_id, HTTPCode => http_code, ABC => abc
    def snake_case(str)
      str.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([[:lower:]\d])([A-Z])/, '\1_\2').sub(/\A_+/, '').downcase
    end

    def upcase_first(str)
      raise ArgumentError, 'input cannot be empty' if str.empty?

      str[0].upcase + str[1..]
    end

    # authors => author, policies => policy, statuses => status, addresses => address, books => book
    def singularize(word)
      case word
      when /ies\z/ then word.sub(/ies\z/, 'y')
      when /(ss|sh|ch|x|z|u)es\z/ then word.sub(/es\z/, '')
      when /(ss|us|is)\z/ then word
      when /s\z/ then word.chomp('s')
      else word
      end
    end

    # node_postgres_types => NodePostgresTypes
    def camelize(word)
      word.split(/[^A-Za-z0-9]+/).reject(&:empty?).map { |w| w[0].upcase + w[1..] }.join
    end

    # Names an enum module cannot use for a value: the keywords BEGIN / END and its own ALL list.
    RESERVED_CONSTANTS = %w[BEGIN END ALL].freeze

    # 'Auto biography' => AUTO_BIOGRAPHY, 'end' => END_, '2x' => VALUE_2X (valid constant name)
    def constant_name(value)
      name = value.to_s.gsub(/[^A-Za-z0-9]+/, '_').gsub(/\A_+|_+\z/, '').upcase
      name = "VALUE_#{name}" if name.empty? || name.match?(/\A[0-9]/)
      RESERVED_CONSTANTS.include?(name) ? "#{name}_" : name
    end

    RUBY_KEYWORDS = %w[BEGIN END alias and begin break case class def defined? do else elsif end ensure false for if in
                       module next nil not or redo rescue retry return self super then true undef unless until when
                       while yield __FILE__ __LINE__ __ENCODING__].freeze

    # sqlc column / parameter name -> a valid keyword-argument name (userId -> user_id, class -> class_,
    # "Weird Name" -> weird_name, 2col -> _2col)
    def param_name(name)
      snake = snake_case(name)
      snake = identifier(snake.gsub(/[^\p{Word}]+/, '_').gsub(/_{2,}/, '_').delete_prefix('_')) unless snake.match?(LOCAL)
      RUBY_KEYWORDS.include?(snake) ? "#{snake}_" : snake
    end

    LOCAL = /\A[\p{Ll}_][\p{Word}]*\z/.freeze

    # Private hooks that building, copying and cloning a row call: a member with one of these names breaks them
    # (a column named `initialize` would make every row raise ArgumentError when it is built).
    CONSTRUCTION_METHODS = %w[initialize initialize_clone initialize_copy initialize_dup method_missing
                              respond_to_missing?].freeze

    # Methods of every row object (Object + Data): a column with one of these names would override it.
    OBJECT_METHODS = (%w[__id__ __send__ class clone deconstruct deconstruct_keys define_singleton_method display dup
                         enum_for eql? equal? extend freeze frozen? hash inspect instance_of? instance_variable_defined?
                         instance_variable_get instance_variable_set instance_variables is_a? itself kind_of? members
                         method methods nil? object_id public_method public_send respond_to? send singleton_class
                         singleton_method singleton_methods tap then to_enum to_h to_s with yield_self] +
                      CONSTRUCTION_METHODS).freeze
    KERNEL_METHODS = %w[format raise rand].freeze

    # Struct (rows on Ruby < 3.2) also has Enumerable and accessors such as #size / #values.
    STRUCT_METHODS = (OBJECT_METHODS + %w[all? any? chain chunk chunk_while collect collect_concat compact count cycle
                                          detect dig drop drop_while each each_cons each_entry each_pair each_slice
                                          each_with_index each_with_object entries filter filter_map find find_all
                                          find_index first flat_map grep grep_v group_by include? inject lazy length
                                          map max max_by member? min min_by minmax minmax_by none? one? partition
                                          reduce reject reverse_each select size slice_after slice_before slice_when
                                          sort sort_by sum take take_while tally to_a to_set uniq values values_at
                                          zip]).freeze

    # Column name -> attribute of a Data / Struct row: valid identifier (case kept), and never one of the row's own
    # methods (`class` -> class_, `hash` -> hash_).
    def member_name(name, struct: false)
      name = name.match?(/\A[\p{L}_][\p{Word}]*\z/) ? name : param_name(name)
      name = "#{name}_" while (struct ? STRUCT_METHODS : OBJECT_METHODS).include?(name)
      name
    end

    # Naming/MethodParameterName's default AllowedNames
    SHORT_NAMES = %w[as at by cc db id if in io ip of on os pp to].freeze

    # The Naming cops that names taken from the schema (a "UserId" column, a 2-letter parameter, non-ASCII) trip.
    def naming_cops(attributes: [], params: [])
      cops = []
      cops << 'Naming/MethodName' unless attributes.all? { |n| n.match?(/\A[\d[[:lower:]]_]+\z/) }
      cops << 'Naming/MethodParameterName' if params.any? { |n| n.length < 3 && !n.match?(/\d\z/) && !SHORT_NAMES.include?(n) }
      cops << 'Naming/AsciiIdentifiers' unless params.all?(&:ascii_only?)
      cops << 'Naming/VariableNumber' if attributes.any? { |n| n.match?(/_\d+\z/) } # code_2 (repeated parameters)
      cops
    end

    def without_cops(code, cops)
      return code if cops.empty?

      "# rubocop:disable #{cops.join(', ')}\n#{code}\n# rubocop:enable #{cops.join(', ')}"
    end

    def identifier(name)
      return '_' if name.empty?

      name.match?(/\A\p{Digit}/) ? "_#{name}" : name
    end

    # A file name as a CamelCase constant: underscores and other characters that are not valid in a constant start a
    # new word. 'admin_users' => AdminUsers, 'user-queries' => UserQueries, 'userQueries' => UserQueries,
    # '2024' => Q2024
    def constant_part(str)
      name = camelize(str)
      raise ArgumentError, "#{str.inspect} has no characters usable in a Ruby constant" if name.empty?

      name.match?(/\A[0-9]/) ? "Q#{name}" : name
    end

    # PostgreSQL keeps the first 63 bytes of a prepared statement name (NAMEDATALEN - 1).
    STATEMENT_NAME_BYTES = 63

    # Prepared statement name of a generated method, unique for every method of every class that can share a
    # connection: `Module::Class#method` cannot be spelled by another class or method (`::` and `#` never occur
    # inside a constant or method name). Names PostgreSQL would truncate become a prefix plus a 64-bit FNV-1a hash of
    # the full name after a `~`, which no full name contains.
    def statement_name(class_name, method)
      name = "#{class_name}##{method}"
      return name if name.bytesize <= STATEMENT_NAME_BYTES

      prefix = name.byteslice(0, STATEMENT_NAME_BYTES - 17).scrub('')
      "#{prefix}~#{fnv1a64(name)}"
    end

    FNV_OFFSET = 0xcbf29ce484222325
    FNV_PRIME = 0x100000001b3
    UINT64 = 0xffff_ffff_ffff_ffff

    def fnv1a64(text)
      text.each_byte.reduce(FNV_OFFSET) { |hash, byte| ((hash ^ byte) * FNV_PRIME) & UINT64 }.to_s(16).rjust(16, '0')
    end

    # "Line 1\nLine 2" => "# Line 1\n# Line 2" ('' for no comment)
    def comment(text)
      return '' if text.to_s.strip.empty?

      text.to_s.strip.lines.map { |l| "# #{l.rstrip}".rstrip }.join("\n")
    end

    # GetAuthor => GET_AUTHOR_SQL
    # Single-quoted Ruby String literal of any text (`it's` -> 'it\\'s').
    def string_literal(text) = "'#{text.gsub(/['\\\\]/) { |c| "\\#{c}" }}'"

    def sql_constant(query_name) = "#{snake_case(query_name).upcase}_SQL"

    def block(header, body)
      "#{header}\n#{indent(body)}\nend"
    end
  end
end
