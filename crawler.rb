#!/usr/bin/env ruby

require "bundler/setup"
require "mechanize"
require "nokogiri"
require_relative "./cache_driver"

URL = "https://suumo.jp/jj/bukken/ichiran/JJ012FC001/?ar=030&bs=011&cn=9999999&cnb=0&ekTjCd=&ekTjNm=&kb=1&kt=9999999&mb=0&mt=9999999&ta=13&tj=0&po=0&pj=1&pc=100".freeze

def collect_unique_paginated_links(agent, start_url, max_page=nil)
  visited_pages = {}
  page_queue = [start_url]
  collected_links = []
  current_page = 0

  while (current = page_queue.shift)
    next if visited_pages[current]
    visited_pages[current] = true

    current_page += 1
    break if max_page && current_page > max_page

    doc = agent.get(current).parser

    # Detect anchors under .property_unit-title (detail links) for this page.
    collected_links.concat(doc.css(".property_unit-title a"))

    # Enqueue additional pagination pages by numeric page links.
    numeric_page_links = doc.css(".pagination_set-nav a, .pagination_set a, a").select do |a|
      a.text.strip.match?(/^\d+$/) && a["href"]
    end

    numeric_page_links.each do |a|
      begin
        page_url = URI.join(current, a["href"]).to_s
        page_queue << page_url unless visited_pages[page_url]
      rescue URI::Error
        next
      end
    end
  end

  collected_links.reject { |a| a["href"].nil? }.uniq { |a| a["href"] }
end

def detail_url_for(anchor_href)
  base = URI.join(URL, anchor_href) rescue nil
  base ? URI.join(base.to_s, "bukkengaiyo/").to_s : "#{anchor_href}bukkengaiyo/"
end

def cell_text(doc, label)
  doc.at_xpath("//th[contains(normalize-space(.), '#{label}')]/following-sibling::td[1]")&.text&.gsub(/\s+/, " ")&.strip
end

def extract_price(doc)
  # Prefer hidden numeric amount if available.
  loan_value = doc.at_css("#jsiLoanAmount")&.[]("value")
  return loan_value.to_i if loan_value && !loan_value.empty?

  price_text = nil
  # Try price from the table that contains the 支払シミュレーション row (price row precedes it).
  sim_cell = doc.at_xpath("//td[contains(normalize-space(.), '支払シミュレーション')]")
  if sim_cell
    table = sim_cell.at_xpath("ancestor::table[1]")
    # In this table, price is typically on the 3rd row, first td.
    row = table&.css("tr")&.[](2)
    price_cell = row&.css("td")&.first
    price_text = price_cell&.text&.strip
  end

  price_text = cell_text(doc, "価格") if price_text.nil? || price_text.empty?
  unless price_text.nil? || price_text.empty?
    digits = price_text[/[0-9][0-9,.]*/]
    if digits
      amount = digits.delete(",").to_i
      return price_text.include?("万") ? amount * 10_000 : amount
    end
  end

  body = doc.to_html.force_encoding("UTF-8")
  if (match = body.match(/([0-9][0-9,.]*)(万円)/))
    return match[1].delete(",").to_i * 10_000
  end

  nil
end

def ratio(item)
  price = item[:price]
  size = item[:size]
  return nil unless price.is_a?(Numeric) && size.is_a?(Numeric) && size.positive?
  price.to_f / size.to_f
end

def avg(values)
  return nil if values.empty?
  values.sum / values.size.to_f
end




puts "Init..."
# First positional argument can specify max_page (integer, <=0 means all pages).
max_page = ARGV[0]&.to_i
max_page = nil if max_page && max_page <= 0
quiet = ENV["QUIET_MODE"] == "1"


agent = Mechanize.new
agent.user_agent_alias = "Mac Safari"
cache = CacheDriver.new
cache.clear

puts "Scaning all items link..."
deduped_links = collect_unique_paginated_links(agent, URL, max_page)

puts "Detail links (#{deduped_links.size} found):"
deduped_links.each do |a|
  text = a.text.strip
  text = a["title"].to_s.strip if text.empty?
  target_url = detail_url_for(a["href"])

  begin
    detail_doc = agent.get(target_url).parser
  rescue StandardError => e
    warn "Failed to fetch #{target_url}: #{e}"
    next
  end

  price = extract_price(detail_doc) || "-"
  size_raw = cell_text(detail_doc, "専有面積")
  size = size_raw ? size_raw[/[0-9.]+/].to_f : nil
  completed = cell_text(detail_doc, "築年月")
  location = cell_text(detail_doc, "所在地")

  cache.store_listing(
    url: target_url,
    title: (text.empty? ? nil : text),
    price: price,
    size: size,
    completed: completed,
    location: location
  )
  unless quiet
    puts "- #{text.empty? ? '[no text]' : text} | 価格: #{price} | 専有面積: #{size} | 築年月: #{completed} | 所在地: #{location} | #{target_url}"
  end
end

# Compute metrics after caching.
listings = cache.all_listings
all_ratios = listings.filter_map { |item| ratio(item) }
koto_ratios = listings.filter_map { |item| item[:location]&.include?("江東区") ? ratio(item) : nil }.compact
kamedo_ratios = listings.filter_map { |item| item[:location]&.include?("亀戸") ? ratio(item) : nil }.compact

all_avg = avg(all_ratios)
koto_avg = avg(koto_ratios)
kamedo_avg = avg(kamedo_ratios)

puts "\nMetrics:"
puts "- Average price/size (all): #{all_avg} (#{all_ratios.size} items)"
puts "- Average price/size (江東区): #{koto_avg} (#{koto_ratios.size} items)"
puts "- Average price/size (亀戸): #{kamedo_avg} (#{kamedo_ratios.size} items)"

today = Time.now.utc.strftime("%Y_%m_%d")
cache.store_daily_metrics(
  date: today,
  all_avg: all_avg,
  koto_avg: koto_avg,
  kamedo_avg: kamedo_avg,
  counts: {
    all: all_ratios.size,
    koto: koto_ratios.size,
    kamedo: kamedo_ratios.size
  }
)
