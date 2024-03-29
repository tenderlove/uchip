ENV["MT_NO_PLUGINS"] = "1"

require "minitest/autorun"
require "psych"
require "uchip/mcp2221"
require "forwardable"

class UChip::TestCase < Minitest::Test
  class Recorder
    attr_reader :ops

    def initialize dev
      @dev = dev
      @ops = []
    end

    def write bytes
      x = @dev.write bytes
      @ops << [__method__, { in: bytes, out: x }]
      x
    end

    def read_timeout size, timeout
      x = @dev.read_timeout size, timeout
      @ops << [__method__, { in: [size, timeout], out: x }]
      x
    end
  end

  class ReplayTest
    extend Forwardable

    attr_reader :tc, :recording
    def_delegators :@tc, :assert_equal

    def initialize tc, recording
      @tc = tc
      @recording = recording
    end

    def write bytes
      method, io = recording.shift
      assert_equal __method__, method
      assert_equal io[:in].b, bytes
      io[:out]
    end

    def read_timeout x, y
      method, io = recording.shift
      assert_equal __method__, method
      expected_x, expected_y = *io[:in]
      assert_equal expected_x, x
      assert_equal expected_y, y
      io[:out].b
    end
  end

  def make_real
    dev = MyHIDAPI.enumerate(0x04d8, 0x00dd).first
    UChip::MCP2221.new dev, dev.open
  end

  def make_replay recording
    dev = ReplayTest.new self, recording
    UChip::MCP2221.new Object.new, dev
  end

  def make_recording
    dev = MyHIDAPI.enumerate(0x04d8, 0x00dd).first
    @wrapper = Recorder.new dev.open
    UChip::MCP2221.new Object.new, @wrapper
  end
end
