# frozen_string_literal: true

require "uchip/mcp2221"

class MCP4728
  def self.first
    # Find the first connected chip
    chip = UChip::MCP2221.first || raise("Couldn't find the chip!")

    new chip, chip.i2c_on(0x60)
  end

  attr_reader :chip, :i2c

  CHANNEL_NUM_TO_NAME = {
    0 => :A,
    1 => :B,
    2 => :C,
    3 => :D,
  }

  def initialize chip, i2c
    @chip = chip
    @i2c  = i2c
  end

  class DAC < Struct.new(:rdy, :por, :channel, :i2c_addr, :vref, :pd_sel, :gain_sel, :val, :eprom)
    def name
      CHANNEL_NUM_TO_NAME[channel]
    end

    def fast_write
      ((pd_sel << 4) | (val >> 8)).chr + (val & 0xFF).chr
    end
  end

  def set_vref a, b, c, d
    i2c.write ((1 << 7) | (a << 3) | (b << 2) | (c << 1) | (d << 0)).chr
    self
  end

  def fast_write channels
    i2c.write(channels.map(&:fast_write).join)
    self
  end

  def raw_write data
    i2c.write(data)
  end

  def read
    buf = i2c.read(24).bytes
    8.times.map do |i|
      eprom = !(i % 2).zero?
      current = decode(*buf.first(3), eprom)
      buf = buf.drop(3)
      current
    end
  end

  private

  def decode a, b, c, eprom
    rdy      = (a >> 7) & 0x1
    por      = (a >> 6) & 0x1
    channel  = (a >> 4) & 0x3
    i2c_addr = (a >> 0) & 0x7
    vref     = (b >> 7) & 0x1
    pd_sel   = (b >> 5) & 0x3
    gain_sel = (b >> 4) & 0x1
    val      = (((b >> 0) & 0xF) << 8) | c
    DAC.new(rdy, por, channel, i2c_addr, vref, pd_sel, gain_sel, val, eprom)
  end
end

chip = MCP4728.first
chip.set_vref 0, 0, 0, 0 # set everything to use VCC as VREF
channels = chip.read.reject(&:eprom)

buffers = 4095.times.map do |i|
  channels.each { |channel| channel.val = i }.map(&:fast_write).join
end

loop do
  buffers.each { |d| chip.raw_write d }
  buffers.reverse.each { |d| chip.raw_write d }
end
