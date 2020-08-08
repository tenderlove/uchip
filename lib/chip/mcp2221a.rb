require "logger"
require 'myhidapi'

module Chip
  class MCP2221A
    extend Enumerable

    class Error < StandardError; end
    class CommandNotSupported < Error; end

    def self.each
      MyHIDAPI.enumerate(0x04d8, 0x00dd).each { |dev| yield new dev }
    end

    def initialize dev
      @dev = dev
      @handle = dev.open
    end

    def usb_manufacturer
      handle.manufacturer
    end

    def usb_product
      handle.product
    end

    NULL_BUF_62 = [0x0] * 62

    def read_flash section
      retries = 0
      loop do
        buf = [0xB0, section].pack('C*')
        buf << ("\x0".b * (64 - buf.bytesize))

        break if handle.write buf
        retries += 1
        raise "Too many retries" if retries > 3
      end
      buf = @handle.read_timeout 64, 300 # 300 ms timeout
      raise "Nothing read!" unless buf
      raise CommandNotSupported unless buf.start_with?("\xB0\x0".b)
      buf
    end

    class ChipSettings
      def initialize bytes
        @bytes = bytes
      end

      def inspect
        to_s.sub(/>$/, " #{decode(@bytes).inspect}>")
      end

      def decode bytes
        {
          :cdc                          => (bytes.first >> 7),
          :led_uart_rx                  => (bytes.first >> 6) & 1,
          :led_uart_tx                  => (bytes.first >> 5) & 1,
          :led_i2c                      => (bytes.first >> 4) & 1,
          :sspnd                        => (bytes.first >> 3) & 1,
          :usbcfg                       => (bytes.first >> 2) & 1,
          :security                     => bytes.first & 0x3,
          :clock_output_divider         => bytes[1] & 0x1F,
          :dac_reference_voltage        => (bytes[2] >> 6) & 0x3,
          :dac_reference_option         => (bytes[2] >> 5) & 0x1,
          :dac_power_up_value           => bytes[2] & 0x1F,
          :interrupt_detection_negative => (bytes[3] >> 6) & 0x1,
          :interrupt_detection_positive => (bytes[3] >> 5) & 0x1,
          :adc_reference_voltage        => (bytes[3] >> 3) & 0x3,
          :dac_voltage                  => (bytes[3] >> 2) & 0x1,
          :vid                          => bytes[4] + (bytes[5] << 8),
          :pid                          => bytes[6] + (bytes[7] << 8),
          :usb_power_attributes         => bytes[8],
          :usb_requested_mas            => bytes[9],
        }
      end
    end

    module FlashData
      CHIP_SETTINGS         = 0x00
      GP_SETTINGS           = 0x01
      MANUFACTURER          = 0x02
      PRODUCT               = 0x03
      SERIAL_NUMBER         = 0x04
      FACTORY_SERIAL_NUMBER = 0x05
    end

    def chip_settings
      buf = read_flash(FlashData::CHIP_SETTINGS).bytes
        .drop(2) # response header
        .drop(2) # not care (according to data sheet)
        .first(10)
      ChipSettings.new buf
    end

    class GPSettings
      def initialize bytes
        @bytes = bytes
      end

      def inspect
        to_s.sub(/>$/, " #{decode(@bytes).inspect}>")
      end

      def decode bytes
        4.times.each_with_object({}) { |i, o|
          o[:"gp#{i}_output_value"] = (bytes[i] >> 4) & 0x1
          o[:"gp#{i}_direction"]    = (bytes[i] >> 3) & 0x1
          o[:"gp#{i}_designation"]  = (bytes[i] >> 0) & 0x3
        }
      end
    end

    def gp_settings
      buf = read_flash(FlashData::GP_SETTINGS).bytes
        .drop(2) # response header
        .drop(2) # structure length, don't care
        .first(4)
      GPSettings.new buf
    end

    def manufacturer
      byte_count, _, *rest = read_flash(FlashData::MANUFACTURER).bytes
        .drop(2) # response header
      rest[0, byte_count - 2].pack('U*')
    end

    def product
      byte_count, _, *rest = read_flash(FlashData::PRODUCT).bytes
        .drop(2) # response header
      rest[0, byte_count - 2].pack('U*')
    end

    def serial_number
      byte_count, _, *rest = read_flash(FlashData::SERIAL_NUMBER).bytes
        .drop(2) # response header
      rest[0, byte_count - 2].pack('U*')
    end

    def factory_serial_number
      byte_count, _, *rest = read_flash(FlashData::FACTORY_SERIAL_NUMBER).bytes
        .drop(2) # response header
      rest[0, byte_count - 2].pack('U*')
    end

    private

    attr_reader :handle
  end
end

chip = Chip::MCP2221A.first
p chip.chip_settings
p chip.gp_settings
puts chip.manufacturer
puts chip.product
puts chip.serial_number
puts chip.factory_serial_number
