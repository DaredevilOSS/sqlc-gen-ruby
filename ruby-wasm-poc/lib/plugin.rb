require_relative 'gen/plugin/codegen_pb'
require 'json'

module Plugin
  class Runner
    @options = {}
    
    def run
      request_bytes = $stdin.read.bytes
      generate_request = Plugin::GenerateRequest.decode(request_bytes)
      generate_response = generate(generate_request)
      $stdout.write(generate_response.encode)
    end

    private

    def generate(generate_request)
      @options = parse_options(generate_request['PluginOptions'])
      files = generate_files_from_queries(generate_request)
      generate_response = Plugin::GenerateResponse.new(:Files => files)
      generate_response.encode
    end

    def parse_options(plugin_options)
      plugin_options_str = plugin_options
                             .bytes.pack('C*')
                             .force_encoding('UTF-8')
      JSON.parse(plugin_options_str)
    end
    
    def generate_files_from_queries(generate_request)
      generate_request['Queries']
        .group_by { |query| query['Filename'] }
        .map { |filename, queries| generate_file(filename, queries) }
    end

    def generate_file(filename, queries)
      Plugin.OutputFile.new(:Name => filename, :Contents => "".bytes)
    end
  end
end
