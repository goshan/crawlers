#!/usr/bin/env ruby

require "bundler/setup"
require "mechanize"
require "nokogiri"
require_relative "./metrics_store"
require File.expand_path('../config', __FILE__)



THROTTLE_MAX_RETRY = Config.max_retry
THROTTLE_REQUEST_WINDOW = Config.requests_per_sleep
THROTTLE_SLEEP_SECONDS = Config.sleep_seconds

$fetch_counter = { count: 0 }

def reset_fetch_counter!
  $fetch_counter[:count] = 0
end

def fetch_with_throttle(agent, url)
  begin
    doc = agent.get(url).parser
  rescue StandardError => e
    puts "Skip #{url}, due to: #{e}"
    doc = nil
  end
  $fetch_counter[:count] += 1
  sleep(THROTTLE_SLEEP_SECONDS) if THROTTLE_REQUEST_WINDOW.positive? && ($fetch_counter[:count] % THROTTLE_REQUEST_WINDOW).zero?
  doc
end

def fetch_with_retry(agent, url, attemp=0)
  begin
    doc = agent.get(url).parser
  rescue StandardError => e
    if attemp < THROTTLE_MAX_RETRY
      puts "Retry #{url}, due to: #{e}"
      sleep(THROTTLE_SLEEP_SECONDS) if THROTTLE_REQUEST_WINDOW.positive?
      doc = fetch_with_retry(agent, url, attemp+1)
    else
      puts "Exceed retry limit, failed to fetch #{url}, due to: #{e}"
      doc = nil
    end
  end
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

    doc = fetch_with_retry(agent, current)
    next if doc.nil?

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

def ratio(price, size)
  return nil unless price.is_a?(Numeric) && size.is_a?(Numeric) && size.positive?
  price.to_f / size.to_f
end

def avg(values)
  return nil if values.empty?
  values.sum / values.size.to_f
end

def extract_categories(location)
  catetories = Config::LOCATION_CONFIG.filter_map { |key, cfg| key if location&.include?(cfg[:label]) }
end

def run_crawler(start_url, max_page=nil, sampling_rate)

  puts "Init agent..."
  agent = Mechanize.new
  agent.user_agent_alias = "Mac Safari"
  cache = MetricsStore.new

  reset_fetch_counter!
  puts "scaning from page: #{start_url}"
  puts "max page: #{max_page.inspect} and sampling rate: #{sampling_rate}"
  puts "throttle strategy: retry: #{THROTTLE_MAX_RETRY}, window: #{THROTTLE_REQUEST_WINDOW}, delay: #{THROTTLE_SLEEP_SECONDS}"
  deduped_links = collect_unique_paginated_links(agent, start_url, max_page, sampling_rate)
  puts "Detail links (#{deduped_links.size} found)"

  quiet_mode = Config.quiet_mode
  ratios_map = Config::LOCATION_CONFIG.map { |key, _| [key, []] }.to_h
  deduped_links.each do |a|
    text = a.text.strip
    text = a["title"].to_s.strip if text.empty?
    target_url = detail_url_for(a["href"], start_url)

    detail_doc = fetch_with_throttle(agent, target_url)
    next if detail_doc.nil?

    price = extract_price(detail_doc) || "-"
    size_raw = cell_text(detail_doc, "専有面積")
    size = size_raw ? size_raw[/[0-9.]+/].to_f : nil
    completed = cell_text(detail_doc, "築年月")
    location = cell_text(detail_doc, "所在地")

    unless quiet_mode
      puts "- #{text.empty? ? '[no text]' : text} | 価格: #{price} | 専有面積: #{size} | 築年月: #{completed} | 所在地: #{location} | #{target_url}"
    end

    ratio = ratio(price, size)
    next if ratio.nil?
    categories = extract_categories(location)
    ratios_map[:all] << ratio
    categories.each do |category| 
      ratios_map[category] << ratio unless ratios_map[category].nil?
    end
  end

  today = Date.today
  puts "\nMetrics:"
  ratios_map.each do |key, ratios|
    average = avg(ratios)
    count   = ratios.size
    puts "- Average price/size (#{Config::LOCATION_CONFIG[key][:label]}): #{average} (#{count} items)"
    cache.store_daily_metrics(date: today, location_key: key, average: average, count: count)
  end
end

if __FILE__ == $PROGRAM_NAME
  start_url = Config.start_url
  max_page = Config.max_page
  sampling_rate = Config.sampling_rate
  run_crawler(start_url, max_page, sampling_rate)
end
