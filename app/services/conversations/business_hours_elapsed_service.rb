class Conversations::BusinessHoursElapsedService
  def initialize(conversation)
    @conversation = conversation
    @inbox = conversation.inbox
  end

  # Returns elapsed business-hours minutes since last_activity_at.
  # Falls back to wall-clock minutes if working hours are not enabled.
  def elapsed_minutes
    return wall_clock_elapsed unless @inbox.working_hours_enabled?

    business_hours_elapsed
  end

  private

  def wall_clock_elapsed
    (Time.now.utc - @conversation.last_activity_at) / 60.0
  end

  def business_hours_elapsed
    tz = ActiveSupport::TimeZone[@inbox.timezone] || Time.zone
    from = @conversation.last_activity_at.in_time_zone(tz)
    now  = Time.now.in_time_zone(tz)

    # Index working hours by day_of_week for O(1) lookup
    schedule = @inbox.working_hours.index_by(&:day_of_week)

    total_minutes = 0.0
    cursor = from

    while cursor.to_date <= now.to_date
      wh = schedule[cursor.to_date.wday]
      total_minutes += open_minutes_for_day(wh, cursor, now)
      cursor = cursor.advance(days: 1).change(hour: 0, min: 0, sec: 0)
    end

    total_minutes
  end

  def open_minutes_for_day(wh, cursor, now)
    return 0.0 if wh.nil? || wh.closed_all_day?

    tz = ActiveSupport::TimeZone[@inbox.timezone] || Time.zone
    day_open  = cursor.change(hour: wh.open_hour,  min: wh.open_minutes,  sec: 0)
    day_close = cursor.in_time_zone(tz).change(hour: wh.close_hour, min: wh.close_minutes, sec: 0)

    window_start = [cursor, day_open].max
    window_end   = [now, day_close].min

    return 0.0 unless window_start < window_end

    (window_end - window_start) / 60.0
  end
end
