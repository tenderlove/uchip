# UChip

This is a library for controlling Microchip Chips.  Specifically the MCP2221 and
MCP2221A.

## Examples

See the `examples` folder for more examples, but here is an example of using
GP0 as a GPIO:


```ruby
require "uchip/mcp2221"

def hit_bell pin
  pin.value = 0
  pin.value = 1
  sleep 0.009
  pin.value = 0
end

# Find the first connected chip
chip = UChip::MCP2221.first || raise("Couldn't find the chip!")

pin = chip.pin 0
pin.output!

loop do
  hit_bell pin
  sleep 2
end
```

## Problems

Right now this library doesn't support DAC or ADC, but it should be trivial to
implement.
