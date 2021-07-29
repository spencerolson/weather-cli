require 'httparty'

class WeatherApi
  def initialize(args)
    @api_key = ENV['OPENWEATHER_API_KEY']
    @coords = { lat: ENV['MY_HOME_LAT'], long: ENV['MY_HOME_LONG'] }
    @debug_mode = args.include? "debug"
    @watch_mode = args.include? "watch"
    @hide_graph = args.include? "nograph"
    @hide_alerts = args.include? "noalerts"
    @show_graph = args.include? "graph"
    @show_lat_long = args.include? "location"
    @options = %w(watch location nograph noalerts graph debug help)
    @show_help = args.include? "help"
    @show_help_option = (args[1..-1] || []).find { |arg| @options.include?(arg) }
  end

  def self.run
    WeatherApi.new(ARGV).run
  end

  def run
    if @watch_mode
      break_loop = false
      while !break_loop do
        result = run_once
        break_loop = result[:break]
        system("clear") unless break_loop
        puts result[:summary]
        sleep 90 unless break_loop
      end
    else
      puts run_once[:summary]
    end
  end

  private

  def run_once
    return help if @show_help

    if !@coords[:lat] || !@coords[:long]
      return { summary: "Cannot fetch weather data without latitude and longitude! Please set ENV['MY_HOME_LAT'] and ENV['MY_HOME_LONG'].", break: true}
    end

    if !@api_key
      return { summary: "Cannot fetch weather data without an OpenWeather API Key! Please set ENV['OPENWEATHER_API_KEY'].", break: true }
    end

    {
      summary: minutely_precip_info[:summary],
      break: false
    }
  end

  def help
    help = @show_help_option ? detailed_help : general_help
    { summary: help, break: true }
  end

  def detailed_help
    label = "Option: `#{@show_help_option}`"
    description = {
      "watch" => "Refresh the data once every 90 seconds.",
      "location" => "Include latitude and longitude in the output.",
      "nograph" => "Never include the precipitation chart (default is to only include the chart if rain is expected in the next hour).",
      "noalerts" => "Hide weather alerts (default is to show them, if they exist).",
      "graph" => "Always include the precipitation chart (default is to only include the chart if rain is expected in the next hour).",
      "debug" => "Show detailed debugging information, such as raw response data from OpenWeatherApi requests.",
      "help" => "Show the available options."
    }.fetch(@show_help_option)

    [label, "", "Description: #{description}"]
  end

  def general_help
    ["Options: #{@options.join(", ")}", "", "To get more info for a particular option, try `weather help <option>`."]
  end

  def current_weather
    response_data = weather_response("weather", "units=imperial")
    puts "raw weather response: #{response_data.inspect}" if @debug_mode
    weather = response_data["weather"][0] || {}
    description = weather["description"]
    temp = response_data.dig("main", "temp")
    humidity = response_data.dig("main", "humidity")
    summary = ["#{temp}° | #{description} | #{humidity}% humidity"]

    if @debug_mode
      summary << ""
      summary << "[Ran at #{time_of_day(Time.now)}]"
    end

    { summary: summary }
  end

  def minutely_precip_info
    response_data = weather_response("onecall", "exclude=daily,current&units=imperial")
    puts "raw precip response: #{response_data.inspect}" if @debug_mode
    minutes = format_minutes(response_data)
    hours = format_hours(response_data)
    streaks = create_streaks(minutes)
    rain_summary = rain_summary(streaks, hours)
    alerts = alerts_summary(response_data)

    summary = if show_graph(streaks)
      [graph(minutes), "", rain_summary, ""].concat(current_weather[:summary])
    else
      [rain_summary, ""].concat(current_weather[:summary])
    end

    summary.concat(["", alerts]) unless alerts.empty?

    {
      minutes: minutes,
      streaks: streaks,
      hours: hours,
      summary: summary
    }
  end

  def alerts_summary(response_data)
    alerts = response_data.fetch('alerts', [])
    return "" if alerts.empty? || @hide_alerts

    alerts.map do |alert|
      header_footer = "<<< #{alert['event']} >>>"
      "#{header_footer}\n\n#{alert['description']}\n\n#{header_footer}\n\n"
    end.join
  end

  def weather_response(route, query_params = nil)
    url = "https://api.openweathermap.org/data/2.5/#{route}?lat=#{@coords[:lat]}&lon=#{@coords[:long]}&appid=#{@api_key}"
    url += "&#{query_params}" if query_params

    HTTParty.get(url).parsed_response
  end

  def graph(minutes)
    row_modifier = @show_lat_long ? 1 : 0
    graph = Array.new(6 + row_modifier) { Array.new(63, " ") }
    axis_idx = 5 + row_modifier
    light_idx = 4 + row_modifier
    moderate_idx = 3 + row_modifier
    heavy_idx = 2 + row_modifier
    violent_idx = 1 + row_modifier
    label_idx = 0
    lat_long_idx = 1

    rain_indicator = "*"
    left_bumper_indicator = "["
    right_bumper_indicator = "]"
    quartile_indicator = "+"

    no_bumper_rows = @show_lat_long ? [label_idx, lat_long_idx] : [label_idx]
    graph = graph.map.with_index do |graph_row, graph_idx|
      graph_row.map.with_index do |elem, idx|
        if idx == 0 && !no_bumper_rows.include?(graph_idx)
          graph_idx == axis_idx ? "  " : "#{left_bumper_indicator} "
        elsif idx == 62 && !no_bumper_rows.include?(graph_idx)
          graph_idx == axis_idx ? "  " : " #{right_bumper_indicator}"
        else
          elem
        end
      end
    end

    first_datapoint_time = nil
    last_datapoint_time = nil
    minutes.each_with_index do |minute_data, idx|
      first_datapoint_time = minute_data[:time] if idx == 0
      last_datapoint_time = minute_data[:time]

      insert_idx = idx + 1
      if idx % 15 == 0
        graph[axis_idx][insert_idx] = quartile_indicator
      end

      case rain_intensity(minute_data[:precip])
      when "light"
        graph[light_idx][insert_idx] = rain_indicator
      when "moderate"
        graph[light_idx][insert_idx] = rain_indicator
        graph[moderate_idx][insert_idx] = rain_indicator
      when "heavy"
        graph[light_idx][insert_idx] = rain_indicator
        graph[moderate_idx][insert_idx] = rain_indicator
        graph[heavy_idx][insert_idx] = rain_indicator
      when "violent"
        graph[light_idx][insert_idx] = rain_indicator
        graph[moderate_idx][insert_idx] = rain_indicator
        graph[heavy_idx][insert_idx] = rain_indicator
        graph[violent_idx][insert_idx] = rain_indicator
      end
    end

    label = "<< #{emoji("Rain")} #{first_datapoint_time} - #{last_datapoint_time} >>"
    graph[label_idx][19] = label

    if @show_lat_long
      graph[lat_long_idx][19] = location
    end

    graph.map { |graph_row| graph_row.join }
  end

  def rain_summary(streaks, hours)
    if @show_lat_long && !show_graph(streaks)
      puts location
    end

    minutely_streaks = streaks.map do |streak|
      base = "#{emoji(streak[:label])} #{streak[:from]} - #{streak[:to]}"
      if streak[:label] == "Rain"
        base + " (#{rain_intensity_avg(streak)})"
      else
        base
      end
    end

    hourly_temps = hours.map.with_index do |info, index|
      temp = info[:temp]

      case temp.length
      when 3
        buffer = ''
        pre_buffer = ''
      when 2
        buffer = ' '
        pre_buffer = ''
      when 1
        buffer = ' '
        pre_buffer = ' '
      end

      if index == 0
        "#{pre_buffer}#{temp}°#{buffer}"
      else
        if hours[index - 1][:temp] == temp
          arrow = "➡"
        else
          arrow = hours[index - 1][:temp] > temp ? "⬇" : "⬆"
        end

        "#{arrow}  #{pre_buffer}#{temp}°#{buffer}"
      end
    end.join(" ")

    hourly_times = hours.map do |info|
      time = info[:time]
      buffer = ' ' * (time.length < 4 ? 1 : 0)
      "#{time}#{buffer}"
    end.join("    ")

    [hourly_temps, hourly_times, ""].concat(minutely_streaks).join("\n")
  end

  def location
    "Loc: (#{@coords[:lat]},#{@coords[:long]})"
  end

  def emoji(label)
    label == "Rain" ? "☔" : "⛅"
  end

  def create_streaks(minutes)
    streaks = []
    last_time = nil
    current_streak = { precip_level: [] }
    minutes.each do |minute_data|
      puts minute_data if @debug_mode
      time = minute_data[:time]

      if current_streak[:label].nil?
        current_streak[:label] = minute_data[:rain_status]
        current_streak[:from] = time
        current_streak[:precip_level] << minute_data[:precip]
      elsif minute_data[:rain_status] != current_streak[:label]
        current_streak[:to] = time
        streaks << current_streak
        current_streak = {
          from: time,
          label: minute_data[:rain_status],
          precip_level: [minute_data[:precip]]
        }
      else
        current_streak[:precip_level] << minute_data[:precip]
      end

      last_time = time
    end

    if current_streak[:from] != last_time
      current_streak[:to] = last_time
      streaks << current_streak
    end

    streaks
  end

  def show_graph(streaks)
    return false if @hide_graph
    return true if @show_graph

    streaks.any? { |streak| streak[:label] == "Rain" }
  end

  def format_minutes(response)
    response["minutely"].map do |minute_data|
      precip_mm = minute_data["precipitation"]
      {
        precip: precip_mm,
        time: friendly_stamp(minute_data["dt"]),
        rain_status: precip_mm > 0 ? "Rain" : "No Rain"
      }
    end
  end

  def format_hours(response)
    response["hourly"].map.with_index do |hour_data, index|
      {
        index: index,
        time: friendly_stamp(hour_data["dt"], false),
        temp: hour_data["temp"].to_i.to_s
      }
    end[0..12].select { |data| data[:index] % 3 == 0 }
  end

  def friendly_stamp(timestamp, minutes = true)
    time = Time.at(timestamp).to_datetime
    time_of_day(time, minutes)
  end

  def time_of_day(time, minutes = false)
    minutes ? time.strftime("%-I:%M%p") : time.strftime("%-I%p")
  end

  def rain_intensity_avg(streak)
    precip = streak[:precip_level]
    avg_precip = precip.inject(0.0) { |sum, el| sum + el } / precip.size
    rain_intensity(avg_precip)
  end

  def rain_intensity(precip_mm)
    return "none" if precip_mm == 0

    case precip_mm
    when 0...2.5
      "light"
    when 2.5...7.6
      "moderate"
    when 7.6..50
      "heavy"
    else
      "violent"
    end
  end
end

WeatherApi.run
