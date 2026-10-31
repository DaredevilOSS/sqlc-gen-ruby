#!/usr/bin/env ruby
# frozen_string_literal: true

# Removes debug info (DWARF `.debug_*` custom sections) and the `name` section from a WebAssembly module.
# They are ~18 MB of the 34 MB prebuilt ruby.wasm and are not needed at runtime.
# Dependency-free so the build only needs Ruby (no wabt / binaryen).
#
#   ruby strip_wasm.rb in.wasm [out.wasm]   (default: in place)
DROP = ->(name) { name == 'name' || name.start_with?('.debug') }

def read_leb(data, pos)
  result = 0
  shift = 0
  loop do
    byte = data.getbyte(pos)
    pos += 1
    result |= (byte & 0x7f) << shift
    shift += 7
    return [result, pos] if byte < 0x80
  end
end

input = ARGV.fetch(0)
output = ARGV[1] || input
data = File.binread(input)
abort "#{input}: not a wasm module" unless data.byteslice(0, 4) == "\0asm".b

out = data.byteslice(0, 8)
pos = 8
dropped = 0
while pos < data.bytesize
  id = data.getbyte(pos)
  size, payload = read_leb(data, pos + 1)
  section_end = payload + size
  drop = false
  if id.zero?
    name_len, name_start = read_leb(data, payload)
    drop = DROP.call(data.byteslice(name_start, name_len))
  end
  if drop
    dropped += section_end - pos
  else
    out << data.byteslice(pos, section_end - pos)
  end
  pos = section_end
end
File.binwrite(output, out)
warn "strip_wasm: #{data.bytesize} -> #{out.bytesize} bytes (removed #{dropped})"
