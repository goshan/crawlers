#!/usr/bin/env ruby

require "bundler/setup"
require "mechanize"
require "nokogiri"
require_relative "./cache_driver"

def start_url_from_env
  url = ENV["URL"]
  url = url.strip if url.respond_to?(:strip)
  url = nil if url && url.empty?
  raise "Start URL is required. Set the URL environment variable." unless url
  url
end

def max_page_from_env
  raw = ENV["MAX_PAGE"]
  return nil unless raw
  count = Integer(raw)
  count <= 0 ? nil : count
rescue ArgumentError, TypeError
  nil
end

def sampling_rate_from_env(default: 1.0)
  raw = ENV["SAMPLING_RATE"]
  return default unless raw
  Float(raw)
rescue ArgumentError, TypeError
  default
end

def quiet_mode_from_env(default: false)
  raw = ENV["QUIET_MODE"]
  return default if raw.nil?
  raw == "1"
end

def sleep_seconds_from_env(default: 10.0)
  raw = ENV["SLEEP_SECONDS"]
  return default unless raw
  seconds = Float(raw)
  seconds.negative? ? default : seconds
rescue ArgumentError, TypeError
  default
end

def requests_per_sleep_from_env(default: 10)
  raw = ENV["REQUESTS_PER_SLEEP"]
  return default unless raw
  count = Integer(raw)
  count <= 0 ? default : count
rescue ArgumentError, TypeError
  default
end

THROTTLE_REQUEST_WINDOW = requests_per_sleep_from_env
THROTTLE_SLEEP_SECONDS = sleep_seconds_from_env

$fetch_counter = { count: 0 }

def reset_fetch_counter!
  $fetch_counter[:count] = 0
end

def fetch_with_throttle(agent, url)
  page = agent.get(url)
  $fetch_counter[:count] += 1
  sleep(THROTTLE_SLEEP_SECONDS) if THROTTLE_REQUEST_WINDOW.positive? && ($fetch_counter[:count] % THROTTLE_REQUEST_WINDOW).zero?
  page
end

def collect_unique_paginated_links(agent, start_url, max_page=nil, sampling_rate=1.0)
  sampling_rate = sampling_rate.to_f
  visited_pages = {}
  page_queue = [start_url]
  collected_links = []
  current_page = 0

  while (current = page_queue.shift)
    next if visited_pages[current]
    visited_pages[current] = true

    current_page += 1
    break if max_page && current_page > max_page

    doc = fetch_with_throttle(agent, current).parser

    # Detect anchors under .property_unit-title (detail links) for this page.
    page_links = doc.css(".property_unit-title a")
    sample_count = (page_links.size * sampling_rate).ceil
    sample_count = 0 if sample_count.negative?
    sample_count = page_links.size if sample_count > page_links.size
    collected_links.concat(page_links.to_a.sample(sample_count))

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

def detail_url_for(anchor_href, base_url)
  base = URI.join(base_url, anchor_href) rescue nil
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

def run_crawler(start_url, max_page=nil, sampling_rate)

  puts "Init agent..."
  agent = Mechanize.new
  agent.user_agent_alias = "Mac Safari"
  cache = CacheDriver.new
  cache.clear

  reset_fetch_counter!
  puts "scaning from page: #{start_url} with max page: #{max_page} and sampling rate: #{sampling_rate}"
  puts "throttle strategy: window: #{THROTTLE_REQUEST_WINDOW}, delay: #{THROTTLE_SLEEP_SECONDS}"
  deduped_links = collect_unique_paginated_links(agent, start_url, max_page, sampling_rate)

  quiet_mode = quiet_mode_from_env
  puts "Detail links (#{deduped_links.size} found):"
  deduped_links.each do |a|
    text = a.text.strip
    text = a["title"].to_s.strip if text.empty?
    target_url = detail_url_for(a["href"], start_url)

    begin
      detail_doc = fetch_with_throttle(agent, target_url).parser
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
    unless quiet_mode
      puts "- #{text.empty? ? '[no text]' : text} | 価格: #{price} | 専有面積: #{size} | 築年月: #{completed} | 所在地: #{location} | #{target_url}"
    end
  end

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
end

if __FILE__ == $PROGRAM_NAME
  start_url = start_url_from_env
  max_page = max_page_from_env
  sampling_rate = sampling_rate_from_env
  run_crawler(start_url, max_page, sampling_rate)
end
