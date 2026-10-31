# frozen_string_literal: true

module SqlcGenRuby
  # Small helpers for building indented Ruby / RBS source text.
  module Code
    MAX_ELEMENTS_PER_LINE = 5

    module_function

    def indent(text)
      text.split("\n", -1).map { |l| "\t#{l}" }.join("\n")
    end

    # Strips from every line as many leading characters as the first line has
    # leading whitespace (keeps multi-line values aligned after being indented).
    def dedent_to_first_line(text)
      lines = text.split("\n", -1)
      n = lines.first[/\A\s*/].length
      lines.map { |l| l[n..] || '' }.join("\n")
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

    def block(header, body)
      "#{header}\n#{indent(body)}\nend"
    end
  end
end
