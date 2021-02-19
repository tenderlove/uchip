require "uchip/mcp2221"

class SH1106
  WIDTH = 130
  HEIGHT = 64

  def self.find chip
    new chip.i2c_on(0x3C), HEIGHT, WIDTH
  end

  attr_reader :height

  def width
    @width - 2
  end

  def initialize i2c, height, width
    @i2c    = i2c
    @height = height
    @width  = width
    @pages  = ((height + 7) / 8).times.map {
      (0x00.chr * width).b
    }
  end

  def []= x, y, v
    page = @pages[y / 8]
    bit = 1 << (y % 8)
    x += 2

    if v == 0
      page.setbyte(x, page.getbyte(x) & ~(bit))
    else
      page.setbyte(x, page.getbyte(x) | bit)
    end
  end

  def draw
    @pages.each_with_index do |row, i|
      cmd 0xB0 + i # set row address
      cmd 0x00     # set lower column address
      cmd 0x10     # set upper column address
      @i2c.write(0x40.chr + row)
    end
  end

  def off
    cmd 0xAE
  end

  def on
    cmd 0xAF
  end

  def cmd b
    @i2c.write [0x0, b].pack('CC')
  end
end

class Drawing
  attr_reader :png

  def initialize png
    @png = png
  end

  def draw_line color, x0, y0, x1, y1
    if (y1 - y0).abs < (x1 - x0).abs
      if x0 > x1
        plot_line_low(color, x1, y1, x0, y0)
      else
        plot_line_low(color, x0, y0, x1, y1)
      end
    else
      if y0 > y1
        plot_line_high(color, x1, y1, x0, y0)
      else
        plot_line_high(color, x0, y0, x1, y1)
      end
    end
  end

  def draw_random_bezier num_points, color
    points = num_points.times.map { [rand(png.width - 1), rand(png.height - 1)] }
    draw_bezier points, color
  end

  def draw_bezier points, color
    points.each do |x, y|
      png[x, y] = 1
    end

    calc_x = make_bezier points.map(&:first)
    calc_y = make_bezier points.map(&:last)

    last_point = nil
    list = 0.step(1, 0.01).map { |i|
      x = calc_x.(i).round.clamp(0, png.width - 1)
      y = calc_y.(i).round.clamp(0, png.height - 1)
      if last_point
        draw_line(color, *last_point, x, y)
      end
      last_point = [x, y]
    }
  end

  private

  def plot_line_low color, x0, y0, x1, y1
    dx = x1 - x0
    dy = y1 - y0
    yi = 1

    if dy < 0
      yi = -1
      dy = -dy
    end

    d = (2 *dy) - dx
    y = y0
    x0.upto(x1) do |x|
      png[x, y] = color
      if d > 0
        y = y + yi
        d = d + (2 * (dy - dx))
      else
        d = d + 2 *dy
      end
    end
  end

  def plot_line_high color, x0, y0, x1, y1
    dx = x1 - x0
    dy = y1 - y0
    xi = 1

    if dx < 0
      xi = -1
      dx = -dx
    end

    d = (2 * dx) - dy
    x = x0

    y0.upto(y1) do |y|
      png[x, y] = color
      if d > 0
        x = x + xi
        d = d + (2 * (dx - dy))
      else
        d = d + 2*dx
      end
    end
  end

  def make_bezier points
    pow = points.length - 1
    coef = pow
    lambda { |t|
      m = 1 - t
      mp = t * coef * (m ** (pow - 1))

      total = (m ** pow) * points.first
      total += (t ** pow) * points.last

      points[1, points.length - 2].each { |x| total += x * mp }
      total
    }
  end
end

chip = UChip::MCP2221.first || raise("Couldn't find the chip!")
sh1106 = SH1106.find chip
drawing = Drawing.new sh1106
sh1106.on
drawing.draw_random_bezier 4, 1
drawing.draw_random_bezier 4, 1
drawing.draw_random_bezier 4, 1
sh1106.draw
#sh1106.thing

#sh1106.set_position 0, 0
