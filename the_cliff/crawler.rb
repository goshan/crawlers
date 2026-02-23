#!/usr/bin/env ruby
require "ferrum"
require "json"
require_relative "config"

RESULT_FILE = File.expand_path("last_result.json", __dir__)

# ─── Utilities ───────────────────────────────────────────────────────────────

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def save_result(status:, message:, dates: nil, expected: nil, available: nil)
  result = {
    status:     status,
    message:    message,
    check_in:   dates&.first,
    check_out:  dates&.last,
    expected:   expected,
    available:  available,
    timestamp:  Time.now.iso8601
  }
  File.write(RESULT_FILE, JSON.pretty_generate(result))
  log "Result saved to #{RESULT_FILE}"
  result
end

def wait_for(browser, selector, timeout: Config.timeout)
  deadline = Time.now + timeout
  loop do
    node = browser.at_css(selector)
    return node if node
    raise "Timeout waiting for #{selector}" if Time.now > deadline
    sleep 0.5
  end
end

def wait_for_network_idle(browser)
  browser.network.wait_for_idle(timeout: Config.timeout)
rescue Ferrum::TimeoutError
  log "Network idle timeout (continuing anyway)"
end

# ─── Steps ───────────────────────────────────────────────────────────────────

def build_url
  base = Config.house_url
  "#{base}?start_date=#{Config.check_in_date}&end_date=#{Config.check_out_date}"
end

def get_available_rooms(browser)
  url = build_url
  log "Navigating to: #{url}"
  browser.goto(url)
  wait_for_network_idle(browser)
  sleep 3

  log "Checking availability..."
  available_rooms = browser.evaluate(<<~JS)
    (() => {
      const booking = document.querySelector('section#booking') ||
                      document.getElementById('booking') ||
                      document;
      const item = Array.from(booking.children).find(el => el.querySelector('h4').textContent.trim() === '1')
      if (!item) return -1;

      const text = item.textContent;
      if (text.includes('SOLD OUT') || text.includes('完売') || text.includes('満室')) return 0;
      if (text.includes('Add to Cart')) return -2;

      const select = item.querySelector('select');
      if (!select) return 0;
      const rooms = Array.from(item.querySelector('select').children).filter(el => el.getAttribute('disabled') !== 'disabled');
      return rooms.length;
    })()
  JS

  log "Availability rooms: #{available_rooms}"
  available_rooms
end

# Unused, in developing
def rush_booking(browser)
  booking_result = browser.evaluate(<<~JS)
    (() => {
      const booking = document.querySelector('section#booking') ||
                      document.getElementById('booking') ||
                      document;
      const item = Array.from(booking.children).find(el => el.querySelector('h4').textContent.trim() === '1')

      item.querySelector('button.add-room-button').click();
      item.querySelector('select.select-adult').value = 2
      item.querySelector('select.select-children').value = 1

      const book_btn = document.querySelector('button[title="Book Now"]')
      if (!book_btn) return false; 
      book_btn.click();
      return true;
    })()
  JS
  unless booking_result 
    return false
  end

  wait_for_network_idle(browser)
  sleep 3
  log "Booking form loaded (URL: #{browser.url})"
  unless browser.url.include?("https://thecliff.airhost.co/en/checkout/address")
    log "not booking form, could not rush a room"
    return false
  end

  log "Filling login form..."
  first_name_input = wait_for(browser, 'input[type="text"]#airhost_order_preferred_first_name')
  first_name_input.focus.type("Han")

  last_name_input = wait_for(browser, 'input[type="text"]#airhost_order_preferred_last_name')
  last_name_input.focus.type("Qiu")

  email_input = wait_for(browser, 'input[type="email"]#airhost_order_email')
  email_input.focus.type("goshan.hanqiu@gmail.com")

  phone_input = wait_for(browser, 'input[type="text"]#airhost_order_preferred_phone')
  phone_intpu.focus.type("07013835564")


  js = <<~JS
    (() => {
      const btn = document.querySelector('button[type="submit"]');
      if (!btn) return false;
      btn.click();
      return true;
    })()
  JS
  result = browser.evaluate(js)
  unless result
    return false
  end

  wait_for_network_idle(browser)
  sleep 3
  log "Payment form loaded (URL: #{browser.url})"
  unless browser.url.include?("https://thecliff.airhost.co/en/checkout/payment")
    return false
  end
      
  true
end

# ─── Main ────────────────────────────────────────────────────────────────────

begin
  log "Starting The Cliff availability checker"
  log "  House URL:   #{Config.house_url}"
  log "  Check-in:    #{Config.check_in_date}"
  log "  Check-out:   #{Config.check_out_date}"
  log "  Rooms:       #{Config.num_rooms}"
  log "  Headless:    #{Config.headless}"
  log ""

  browser = Ferrum::Browser.new(
    headless: Config.headless,
    timeout:  Config.timeout,
    pending_connection_errors: false,
    window_size: [1440, 900]
  )

  dates = [Config.check_in_date, Config.check_out_date]
  expected_rooms = Config.num_rooms
  available_rooms = get_available_rooms(browser)
  status = nil
  message = nil

  case available_rooms
  when -2
    status = "rush"
    message = "There might be chance, rush to check"
  when -1
    status = "not_found"
    message = "Room item '1' not found on the page — page structure may have changed"
  when 0
    status = "sold_out"
    message = "Room is sold out"
  else
    available = available_rooms >= expected_rooms
    if available
      status = "available"
      message = "Room is available!"
    else
      status = "not_enough"
      message = "Room is available, but not enough for expected number"
    end
  end

  log "Result: #{status}"
  save_result(
    status:    status,
    message:   message,
    dates:     dates,
    expected:  expected_rooms,
    available: available_rooms
  )
rescue => e
  log "ERROR: #{e.class}: #{e.message}"
  log e.backtrace.first(5).join("\n")
  save_result(status: "error", message: "#{e.class}: #{e.message}")
ensure
  if browser
    log "Closing browser..."
    browser.quit
  end
end

log "Done."
