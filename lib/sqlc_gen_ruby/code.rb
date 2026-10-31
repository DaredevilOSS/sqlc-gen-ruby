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

    def comma_join(items)
      return items.join(', ') if items.size < MAX_ELEMENTS_PER_LINE

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

    # sqlc column / parameter name -> a valid keyword-argument name (userId -> user_id, class -> class_)
    def param_name(name)
      snake = snake_case(name)
      RUBY_KEYWORDS.include?(snake) ? "#{snake}_" : snake
    end

    # GetAuthor => GET_AUTHOR_SQL
    def sql_constant(query_name) = "#{snake_case(query_name).upcase}_SQL"

    def block(header, body)
      "#{header}\n#{indent(body)}\nend"
    end
  end
end
