#!/usr/bin/env ruby

require "bundler/setup"
require "json"
require "date"
require_relative "./cache_driver"

OUT_DIR = File.expand_path("graphs", __dir__)
Dir.mkdir(OUT_DIR) unless Dir.exist?(OUT_DIR)

def build_series(entries, key)
  entries.map do |date, payload|
    value = payload[key]
    next nil unless value
    [date, value.to_f]
  end.compact
end

def render_svg(path, title:, series:)
  width = 700
  height = 320
  margin = 50
  inner_w = width - margin * 2
  inner_h = height - margin * 2

  return if series.empty?

  dates, values = series.transpose
  min_v, max_v = [values.min, values.max]
  range = (max_v - min_v)
  range = 1 if range.zero?

  x_step = series.size > 1 ? inner_w.to_f / (series.size - 1) : 0

  points = series.each_with_index.map do |(_, v), idx|
    x = margin + idx * x_step
    y = margin + inner_h - ((v - min_v) / range * inner_h)
    [x, y]
  end

  File.open(path, "w") do |f|
    f.puts <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}">
        <style>
          text { font-family: Arial, sans-serif; font-size: 12px; fill: #333; }
          .title { font-size: 16px; font-weight: bold; }
          .axis { stroke: #444; stroke-width: 1; }
          .grid { stroke: #ccc; stroke-width: 0.5; }
          .line { fill: none; stroke: #1f77b4; stroke-width: 2; }
          .dot { fill: #d62728; }
        </style>
        <text x="#{margin}" y="25" class="title">#{title}</text>
        <line x1="#{margin}" y1="#{margin}" x2="#{margin}" y2="#{height - margin}" class="axis"/>
        <line x1="#{margin}" y1="#{height - margin}" x2="#{width - margin}" y2="#{height - margin}" class="axis"/>
    SVG

    # Grid and y labels
    5.times do |i|
      y = margin + i * (inner_h / 4.0)
      value = max_v - i * (range / 4.0)
      f.puts %Q(  <line x1="#{margin}" y1="#{y}" x2="#{width - margin}" y2="#{y}" class="grid"/>)
      f.puts %Q(  <text x="#{margin - 10}" y="#{y + 4}" text-anchor="end">#{value.round(2)}</text>)
    end

    # X labels and vertical grid
    series.each_with_index do |(date, _), idx|
      x = margin + idx * x_step
      f.puts %Q(  <line x1="#{x}" y1="#{margin}" x2="#{x}" y2="#{height - margin}" class="grid"/>)
      f.puts %Q(  <text x="#{x}" y="#{height - margin + 15}" text-anchor="middle">#{date.strftime('%m/%d')}</text>)
    end

    path_d = points.map.with_index do |(x, y), idx|
      cmd = idx.zero? ? "M" : "L"
      "#{cmd} #{x} #{y}"
    end.join(" ")
    f.puts %Q(  <path d="#{path_d}" class="line"/>)

    points.each do |x, y|
      f.puts %Q(  <circle cx="#{x}" cy="#{y}" r="3" class="dot"/>)
    end

    f.puts "</svg>"
  end
end

entries = CacheDriver.new.last_7_days_metrics

if entries.empty?
  warn "No metrics found for the last 7 days"
  exit 1
end

all_series = build_series(entries, :all_avg)
koto_series = build_series(entries, :koto_avg)
kamedo_series = build_series(entries, :kamedo_avg)

render_svg(File.join(OUT_DIR, "all_trend.svg"), title: "Tokyo: Price/Size (Last 7 days)", series: all_series) unless all_series.empty?
render_svg(File.join(OUT_DIR, "koto_trend.svg"), title: "Kodo-ku: Price/Size (Last 7 days)", series: koto_series) unless koto_series.empty?
render_svg(File.join(OUT_DIR, "kamedo_trend.svg"), title: "Kamedo: Price/Size (Last 7 days)", series: kamedo_series) unless kamedo_series.empty?

def convert_svg_to_png(svg_path)
  png_path = svg_path.sub(/\.svg\z/, ".png")
  system("convert", svg_path, png_path)
  png_path
end

Dir.glob(File.join(OUT_DIR, "*.svg")).each do |svg|
  convert_svg_to_png(svg)
end

puts "Graphs generated in #{OUT_DIR} (SVG and PNG)"
