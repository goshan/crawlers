#!/usr/bin/env ruby

require "bundler/setup"
require "gruff"
require "date"
require "fileutils"
require_relative "./cache_driver"

OUT_DIR = File.expand_path("graphs", __dir__)
FileUtils.mkdir_p(OUT_DIR)

COLOR_THEME = {
  all: "#fe6a35",     # orange
  koto: "#2790cf",      # blue
  kameido: "#00e272"   # green
}.freeze

def build_xy_series(entries, key)
  entries.each_with_index.filter_map do |(date, payload), idx|
    value = payload[key]
    next unless value
    [[idx, value.to_f], date]
  end
end

def labels_for(entries)
  entries.each_with_index.to_h { |(date, _), idx| [idx, date.strftime("%m/%d")] }
end

def render_combined_chart(path, entries, series_map)
  return if entries.empty?

  chart = Gruff::Line.new(900)
  chart.theme = {
    colors: COLOR_THEME.values,
    marker_color: "#6b7280",
    font_color: "#111827",
    background_colors: "#ffffff"
  }
  chart.title = "Price per Size (Last 7 days)"
  chart.marker_font_size = 14
  chart.title_font_size = 18
  chart.labels = labels_for(entries)
  chart.legend_box_size = 16
  chart.line_width = 3

  all_values = []
  series_map.each do |key, data|
    next if data.empty?
    points = data.map(&:first)
    values = points.map { |(_, v)| v }
    all_values.concat(values)
    chart.dataxy(key.to_s.capitalize, points, COLOR_THEME[key])
  end

  return if all_values.empty?

  chart.minimum_value = [all_values.min * 0.95, 0].max
  chart.maximum_value = all_values.max * 1.05

  chart.write(path)
end

entries = CacheDriver.new.last_7_days_metrics

if entries.empty?
  warn "No metrics found for the last 7 days"
  exit 1
end

series_map = {
  all: build_xy_series(entries, :all_avg),
  koto: build_xy_series(entries, :koto_avg),
  kameido: build_xy_series(entries, :kamedo_avg)
}

render_combined_chart(File.join(OUT_DIR, "price_size_trend.png"), entries, series_map)

puts "Graphs generated in #{OUT_DIR} (combined PNG)"
