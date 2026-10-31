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
      str[0].upcase + str[1..]
    end

    def block(header, body)
      "#{header}\n#{indent(body)}\nend"
    end
  end
end
