require "uchip/mcp2221"

# Find the first connected chip
chip = UChip::MCP2221.first || raise("Couldn't find the chip!")

pin = chip.pin 0
pin.output!

loop do
  pin.value = 0
  pin.value = 1
  sleep 0.01
  pin.value = 0
  sleep 5
end
