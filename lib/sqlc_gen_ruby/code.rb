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

    def snake_case(str)
      str.gsub(/([A-Z])/, '_\1').sub(/\A_+/, '').downcase
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

    # 'Auto biography' => AUTO_BIOGRAPHY (valid constant name)
    def constant_name(value)
      name = value.to_s.gsub(/[^A-Za-z0-9]+/, '_').gsub(/\A_+|_+\z/, '').upcase
      name = "VALUE_#{name}" if name.empty? || name.match?(/\A[0-9]/)
      name
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

    # Public methods of every row object (Object + Data): a column with one of these names would override it.
    OBJECT_METHODS = %w[__id__ __send__ class clone deconstruct deconstruct_keys define_singleton_method display dup
                        enum_for eql? equal? extend freeze frozen? hash inspect instance_of? instance_variable_defined?
                        instance_variable_get instance_variable_set instance_variables is_a? itself kind_of? members
                        method methods nil? object_id public_method public_send respond_to? send singleton_class
                        singleton_method singleton_methods tap then to_enum to_h to_s with yield_self].freeze

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

    def identifier(name)
      return '_' if name.empty?

      name.match?(/\A\p{Digit}/) ? "_#{name}" : name
    end

    # 'user-queries' => User_queries is invalid; runs of characters that are not valid in a constant start a new word:
    # 'user-queries' => UserQueries, 'my_queries' => My_queries (unchanged), '2024' => Q2024
    def constant_part(str)
      words = str.split(/[^A-Za-z0-9_]+/).reject(&:empty?)
      raise ArgumentError, "#{str.inspect} has no characters usable in a Ruby constant" if words.empty?

      name = words.map { |w| upcase_first(w) }.join
      name.match?(/\A[0-9_]/) ? "Q#{name}" : name
    end

    # GetAuthor => GET_AUTHOR_SQL
    def sql_constant(query_name) = "#{snake_case(query_name).upcase}_SQL"

    def block(header, body)
      "#{header}\n#{indent(body)}\nend"
    end
  end
end
