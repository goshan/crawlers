#!/usr/bin/env ruby
require "ferrum"
require "json"
require_relative "config"

RESULT_FILE = File.expand_path("last_result.json", __dir__)

# ─── Utilities ───────────────────────────────────────────────────────────────

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def save_result(status:, message:, plan_name: nil, dates: nil)
  result = {
    status: status,
    message: message,
    plan_name: plan_name,
    check_in: dates&.first,
    check_out: dates&.last,
    timestamp: Time.now.iso8601
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

def wait_for_text(browser, text, tag: "*", timeout: Config.timeout)
  deadline = Time.now + timeout
  loop do
    node = find_by_text(browser, text, tag: tag)
    return node if node
    raise "Timeout waiting for text '#{text}'" if Time.now > deadline
    sleep 0.5
  end
end

def find_by_text(browser, text, tag: "*")
  js = <<~JS
    (() => {
      const els = document.querySelectorAll('#{tag}');
      for (const el of els) {
        if (el.textContent.includes('#{text.gsub("'", "\\\\'")}') && el.offsetParent !== null) {
          return el;
        }
      }
      return null;
    })()
  JS
  browser.evaluate(js)
rescue Ferrum::JavaScriptError
  nil
end

def find_all_by_text(browser, text, tag: "*")
  js = <<~JS
    (() => {
      const els = document.querySelectorAll('#{tag}');
      const matches = [];
      for (const el of els) {
        if (el.textContent.includes('#{text.gsub("'", "\\\\'")}') && el.offsetParent !== null) {
          matches.push(el);
        }
      }
      return matches;
    })()
  JS
  browser.evaluate(js) || []
rescue Ferrum::JavaScriptError
  []
end

def click_by_text(browser, text, tag: "*")
  js = <<~JS
    (() => {
      const els = document.querySelectorAll('#{tag}');
      for (const el of els) {
        if (el.textContent.includes('#{text.gsub("'", "\\\\'")}') && el.offsetParent !== null) {
          el.click();
          return true;
        }
      }
      return false;
    })()
  JS
  browser.evaluate(js)
rescue Ferrum::JavaScriptError
  false
end

def click_innermost_by_text(browser, text, tag: "*")
  js = <<~JS
    (() => {
      const els = document.querySelectorAll('#{tag}');
      let best = null;
      let bestLen = Infinity;
      for (const el of els) {
        const t = el.textContent;
        if (t.includes('#{text.gsub("'", "\\\\'")}') && el.offsetParent !== null) {
          if (t.length < bestLen) {
            best = el;
            bestLen = t.length;
          }
        }
      }
      if (best) { best.click(); return true; }
      return false;
    })()
  JS
  browser.evaluate(js)
rescue Ferrum::JavaScriptError
  false
end

def wait_for_network_idle(browser)
  browser.network.wait_for_idle(timeout: Config.timeout)
rescue Ferrum::TimeoutError
  log "Network idle timeout (continuing anyway)"
end

# ─── Steps ───────────────────────────────────────────────────────────────────

def login(browser)
  log "Step 1: Navigating to login page..."
  browser.page.go_to(Config.login_url)
  wait_for_network_idle(browser)
  sleep 2

  log "Filling login form..."
  email_input = wait_for(browser, 'input[type="email"], input[name="email"], input[name="session[email]"]')
  email_input.focus.type(Config.email)

  password_input = wait_for(browser, 'input[type="password"], input[name="password"], input[name="session[password]"]')
  password_input.focus.type(Config.password)

  submit_clicked = click_by_text(browser, "ログイン", tag: "button")
  unless submit_clicked
    log "Submit button not found by text, trying Enter key..."
    password_input.focus
    browser.keyboard.type(:Enter)
  end

  wait_for_network_idle(browser)
  sleep 3

  if browser.url.include?("sessions/new")
    save_result(status: "error", message: "Login failed — still on login page")
    exit 1
  end
  log "Login successful (redirected to: #{browser.url})"
end

def navigate_to_campsite(browser)
  log "Step 2: Navigating to campsite page..."
  browser.page.go_to(Config.campsite_url)
  wait_for_network_idle(browser)
  sleep 3
  log "Campsite page loaded"
end

def get_plans(browser)
  plans = browser.evaluate(<<~JS)
    (() => {
      const h4s = Array.from(document.querySelectorAll('h4[class^="CampsiteDetailPlan_plan-title"]'));
      return h4s.map((h4, i) => {
        const title = h4.textContent.trim();
        const li = h4.closest('li');
        const btn = li ? li.querySelector('a, button') : null;
        return { index: i, title: title, has_li: !!li, btn_text: btn ? btn.textContent.trim() : null };
      });
    })()
  JS

  if plans.empty?
    save_result(status: "error", message: "No plans found in プラン一覧 section")
    exit 1
  end

  log "Found #{plans.length} plan(s):"
  plans.each { |p| log "  Plan #{p['index']}: #{p['title']}" }
  plans
end

def list_plans(browser)
  log "Step 3: Scrolling to プラン一覧 section..."

  browser.evaluate(<<~JS)
    (() => {
      const headings = Array.from(document.querySelectorAll('h2'));
      const h2 = headings.find(h => h.textContent.includes('プラン一覧'));
      if (h2) h2.scrollIntoView({ behavior: 'smooth', block: 'start' });
    })()
  JS
  wait_for(browser, 'h4[class^="CampsiteDetailPlan_plan-title"]')
  sleep 1

  get_plans(browser)
end

def click_calendar_date(browser, date)
  target_month_label = "#{date.year}年 #{date.month}月"
  log "Looking for target month: #{target_month_label}"

  12.times do |attempt|
    month_visible = browser.evaluate(<<~JS)
      (() => {
        const dateBox = document.querySelector('[class*="DateSelectBox_calendar__"]');
        if (!dateBox) return false;
        return dateBox.textContent.includes('#{target_month_label}');
      })()
    JS
    break if month_visible

    log "  Month not visible, clicking next (attempt #{attempt + 1})..."
    clicked = browser.evaluate(<<~JS)
      (() => {
        const dateBox = document.querySelector('[class*="DateSelectBox_calendar__"]');
        if (!dateBox) return false;
        const next = dateBox.querySelector('[class*="Calendar_calendar-next"]');
        if (!next) return false;
        const nextBtn = next.parentElement;
        if (!nextBtn) return false;
        nextBtn.click();
        return true;
      })()
    JS

    unless clicked
      log "  Could not find next-month button"
      break
    end

    sleep 0.5
  end
  log "Found target month: #{target_month_label}"

  day_str = date.day.to_s
  log "Clicking day: #{day_str}"

  result = browser.evaluate(<<~JS)
    (() => {
      const dateBox = document.querySelector('[class*="DateSelectBox_calendar__"]');
      if (!dateBox) return false;
      const cells = dateBox.querySelectorAll('[class*="Calendar_calendar-day__"]');
      if (!cells || cells.length == 0) return false;
      for (const c of cells) {
        if (!c.firstElementChild.className.includes("Calendar_is-not-current-month") && c.textContent == "#{day_str}") {
          c.firstElementChild.click();
          return true;
        }
      }
      return false;
    })()
  JS
  log "Date click result: #{result}"
  result
end

def select_dates(browser)
  check_in  = Date.parse(Config.check_in_date)
  check_out = Date.parse(Config.check_out_date)

  log "Step 4: Selecting dates..."
  log "  Check-in:  #{check_in}"
  log "  Check-out: #{check_out}"

  sleep 1
  log "Opening calendar..."
  date_input_el = browser.at_css('[class*="DateSelectBox_input-area"]')
  if date_input_el
    date_input_el.click
  else
    save_result(status: "error", message: "Could not find the button to open the calendar")
    exit 1
  end
  sleep 2

  calendar_open = false
  3.times do
    if browser.evaluate("!!document.querySelector('[class*=\"DateSelectBox_calendar\"]')")
      calendar_open = true
      break
    end
    sleep 0.5
  end

  unless calendar_open
    save_result(status: "error", message: "Could not open the calendar")
    exit 1
  end
  log "Calendar opened"
  sleep 0.5

  log "Clicking check-in date: #{check_in}"
  unless click_calendar_date(browser, check_in)
    save_result(status: "error", message: "Could not select the check-in date")
    exit 1
  end
  sleep 0.5

  log "Clicking check-out date: #{check_out}"
  unless click_calendar_date(browser, check_out)
    save_result(status: "error", message: "Could not select the check-out date")
    exit 1
  end

  sleep 2
  wait_for_network_idle(browser)
end

def find_plan_for_book(browser)
  log "Step 5: Re-listing plans after date selection and go to book page if found target plan '#{Config.target_plan_name}'..."
  plans = get_plans(browser)

  plan_index = nil
  plans.each do |plan|
    if plan["title"].include?(Config.target_plan_name)
      log "  Found target plan at index #{plan['index']}"
      plan_index = plan["index"]
      break
    end
  end

  if plan_index.nil?
    log "Target plan not found, unavailable in the target schedule"
    save_result(
      status: "unavailable",
      message: "Target plan '#{Config.target_plan_name}' unavailable in the target dates",
      plan_name: Config.target_plan_name,
      dates: [Config.check_in_date, Config.check_out_date]
    )
    exit 1
  end

  clicked = browser.evaluate(<<~JS)
    (() => {
      const h4s = Array.from(document.querySelectorAll('h4[class^="CampsiteDetailPlan_plan-title"]'));
      const h4 = h4s[#{plan_index}];
      if (!h4) return false;
      const li = h4.closest('li');
      if (!li) return false;
      const btn = Array.from(li.querySelectorAll('a, button')).find(b => b.textContent.includes('予約へ進む'));
      if (btn) { btn.click(); return true; }
      return false;
    })()
  JS

  unless clicked
    save_result(status: "error", message: "Could not click booking button")
    exit 1
  end

  wait_for_network_idle(browser)
  sleep 3
  log "Booking form loaded (URL: #{browser.url})"
  if browser.url.include?(Config.book_url)
    log "Target plan confirmed"
    save_result(
      status: "success",
      message: "Plan is now available on the target dates!",
      plan_name: Config.target_plan_name,
      dates: [Config.check_in_date, Config.check_out_date]
    )
  else
    log "Booking form url not match"
    save_result(status: "error", message: "Navigated to a different page after clicking booking, the web page structure might get changed")
  end
end

# ─── Main ────────────────────────────────────────────────────────────────────

begin
  log "Starting nap-camp booking crawler"
  log "  Campsite URL: #{Config.campsite_url}"
  log "  Target plan:  #{Config.target_plan_name}"
  log "  Check-in:     #{Config.check_in_date}"
  log "  Check-out:    #{Config.check_out_date}"
  log "  Headless:     #{Config.headless}"
  log ""

  browser = Ferrum::Browser.new(
    headless: Config.headless,
    timeout: Config.timeout,
    pending_connection_errors: false,
    window_size: [1440, 900]
  )

  login(browser)
  navigate_to_campsite(browser)
  list_plans(browser)
  select_dates(browser)
  find_plan_for_book(browser)
rescue => e
  log "ERROR: #{e.class}: #{e.message}"
  log e.backtrace.first(5).join("\n")
  save_result(status: "error", message: "#{e.class}: #{e.message}")
  exit 1

ensure
  if browser
    log "Closing browser..."
    browser.quit
  end
end

log "Done."
