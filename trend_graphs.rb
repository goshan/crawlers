#!/usr/bin/env ruby

require "bundler/setup"
require "gruff"
require "date"
require "fileutils"
require_relative "./cache_driver"

OUT_DIR = File.expand_path("graphs", __dir__)
FileUtils.mkdir_p(OUT_DIR)

COLOR_THEME = {
  all: "#D62728",          # red
  koto: "#1F77B4",         # blue-dark
  kameido: "#00e272",      # blue-light
  shinagawa: "#9467BD",    # purple-dark
  minamioi: "#C5B0D5",     # purple-light
  meguro: "#2CA02C",       # green-dark
  honcho: "#74C476"        # green-light
}.freeze



def build_xy_series(entries, key)
  entries.each_with_index.filter_map do |(date, payload), idx|
    value = payload.dig(:avgs, key)
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
  chart.title = "Price per Size (Last 30 days)"
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

entries = CacheDriver.new.last_30_days_metrics

if entries.empty?
  warn "No metrics found for the last 30 days"
  exit 1
end

series_map = COLOR_THEME.map { |key, color| [key, build_xy_series(entries, key)] }.to_h
render_combined_chart(File.join(OUT_DIR, "price_size_trend.png"), entries, series_map)

puts "Graphs generated in #{OUT_DIR} (combined PNG)"
