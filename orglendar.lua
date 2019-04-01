-- Calendar with Emacs org-mode agenda for Awesome WM
-- Inspired by and contributed from the org-awesome module, copyright of Damien Leone
-- Licensed under GPLv2
-- Version 1.1-awesome-git
-- @author Alexander Yakushev <yakushev.alex@gmail.com>

local awful = require("awful")
local util = awful.util
local format = string.format
local theme = require("beautiful")
local naughty = require("naughty")

local orglendar = { files = {},
                    colors = { text_color = theme.fg_normal or "#aaaaaa",
                               today_color = theme.fg_focus or "#FFFFFF",
                               event_color = "#7777ff",
                               active_event_color = "#888800",
                               scheduled_event_color = "#00FF00",
                               deadline_event_color = "#FF0000", },
                    fonts = { calendar_font = 'monospace 12',
                              todo_font = 'monospace 13', },
                    parse_on_show = true,
                    limit_todo_length = nil,
                    date_format = "%d-%m-%Y" }


local freq_table =
   { d = { lapse = 86400,
           occur = 5,
           next = function(t, i)
              local date = os.date("*t", t)
              return os.time{ day = date.day + i,
                              month = date.month,
                              year = date.year, }
   end },
     w = { lapse = 604800,
           occur = 3,
           next = function(t, i)
              return t + 604800 * i
     end },
     y = { lapse = 220752000,
           occur = 1,
           next = function(t, i)
              local date = os.date("*t", t)
              return os.time{ day = date.day,
                              month = date.month,
                              year = date.year + i, }
     end },
     m = { lapse = 2592000,
           occur = 1,
           next = function(t, i)
              local date = os.date("*t", t)
              return os.time{ day = date.day,
                              month = date.month + i,
                              year = date.year, }
     end }
   }

local calendar = nil
local todo = nil
local offset = 0

local function pop_spaces(s1, s2, maxsize)
   local sps = ""
   for i = 1, maxsize - string.len(s1) - string.len(s2) do
      sps = sps .. " "
   end
   return s1 .. sps .. s2
end

local function strip_time(time_obj)
   local tbl = os.date("*t", time_obj)
   return os.time{day = tbl.day,
                  month = tbl.month,
                  year = tbl.year}
end

function orglendar.parse_agenda()
   local list_tasks = {}
   local today = os.time()
   local task_name
   local patterns = { scheduled = "SCHEDULED:",
                      deadline = "DEADLINE:",
                      closed = "CLOSED:",}
   data = { tasks = {},
            dates = {},
            maxlen = 10 }
   for _, file in pairs(orglendar.files) do
      local fd = io.open(file, "r")
      local bool, new_task_name
      local cur_task = nil
      local not_yet_done
      if not fd then
         naughty.notify({ title = "Error in orglendar",
                          text = "Cannot open file " .. file,
         })
      else
         cur_task = nil
         local was_on_headline = false
         local was_in_block_after_headline = false
         local current_task_name = nil
         for line in fd:lines() do
            local on_headline = false
            local in_block_after_headline = false
            if not string.find(line, "^#%+") then
               -- Headline means eventually new task
               _, _, whole_task_name = string.find(line, "^%*+%s+(.+)")
               if whole_task_name then
                  on_headline = true
                  cur_task = { whole_name = whole_task_name,
                               ttypes = { }, }
                  find_str = "([^:]+)%s*:?([a-zA-Z_:-]*)"
                  local _, _, name, tags = string.find(cur_task.whole_name, find_str)
                  name = name:gsub("^%s*(.-)%s*$", "%1")
                  if tags ~= "" then
                     cur_task.tags = ":" .. tags
                  else
                     cur_task.tags = ""
                  end
                  cur_task.name = name
                  current_task_name = name
                  local length_name_and_tags = #cur_task.name + #cur_task.tags
                  if length_name_and_tags > data.maxlen then
                     data.maxlen = length_name_and_tags
                  end
                  -- Are we constructing a task, or before the headline of the next one?
               elseif was_on_headline or was_in_block_after_headline then
                  in_block_after_headline = false
                  for ttype, pattern in pairs(patterns) do
                     if string.find(line, pattern) then
                        in_block_after_headline = true
                        cur_task.ttypes[ttype] = {}
                        local find_str = pattern .. "%s+<(%d%d%d%d)%-(%d%d)%-(%d%d) %w%w%w ?(%d*)%:?(%d*)[^%+]*%+?([^>]*)>"
                        local _, _, y, m, d, h, min, recur = string.find(line, find_str)
                        if d then
                           -- If time is not there
                           if h ~= "" then
                              h = tonumber(h)
                           else
                              h = 23
                           end
                           if min ~= "" then
                              min = tonumber(min)
                           else
                              min = 59
                           end
                           cur_task.ttypes[ttype].date = os.time{day = tonumber(d),
                                                                 month = tonumber(m),
                                                                 year = tonumber(y),
                                                                 hour = h,
                                                                 min = min}
                           cur_task.ttypes[ttype].recur = recur
                        end
                     end
                  end
               end
               if (not on_headline and
                      not in_block_after_headline and
                   (was_on_headline or was_in_block_after_headline)) then
                  table.insert(list_tasks, cur_task)
                  cur_task = nil
               end
               -- Active timestamp?
               if not in_block_after_headline then
                  local find_str = "%s+<(%d%d%d%d)%-(%d%d)%-(%d%d) %w%w%w ?(%d*)%:?(%d*)[^%+]*%+?([^>]*)>"
                  local _, _, y, m, d, h, min, recur = string.find(line, find_str)
                  if d then
                     -- If time is not there
                     if h ~= "" then
                        h = tonumber(h)
                     else
                        h = 23
                     end
                     if min ~= "" then
                        min = tonumber(min)
                     else
                        min = 59
                     end
                     name = current_task_name or "Global active timestamp"
                     tags = ( cur_task and cur_task.tags ) or ""
                     actve_tstp = { name = name,
                                    tags=tags,

                                    ttypes = { active = {
                                                  date = os.time{
                                                     day = tonumber(d),
                                                     month = tonumber(m),
                                                     year = tonumber(y),
                                                     hour = h,
                                                     min = min},
                                                  recur = recur,
                                             }},
                     }
                     table.insert(list_tasks, actve_tstp)
                     cur_task = nil
                  end
               end
            end
            was_on_headline = on_headline
            was_in_block_after_headline = in_block_after_headline
         end
      end
      if cur_task then
         table.insert(list_tasks, cur_task)
         cur_task = nil
      end
   end
   return  list_tasks
end

function expand_recurrent_tasks(list_tasks)
   for _, cur_task in pairs(list_tasks) do
      if not cur_task.ttypes["closed"] and not string.find(cur_task.tags, ":ARCHIVE:") then
         for ttype, event_time in pairs(cur_task.ttypes) do
            if cur_task.ttypes[ttype].recur ~= "" then
               local _, _, interval, freq = string.find(cur_task.ttypes[ttype].recur, "(%d)(%w)")
               local now = os.time()
               local curr
               if freq == "d" then
                  curr = math.max(now, event_time)
               elseif freq == "w" then
                  local count = math.floor((now - event_time) / (freq_table.w.lapse * interval))
                  if count < 0 then count = 0 end
                  curr = event_time + count * (freq_table.w.lapse * interval)
               else
                  curr = event_time
               end
               while curr < now do
                  curr = freq_table[freq].next(curr, interval)
               end
               for i = 1, freq_table[freq].occur do
                  local curr_date = os.date("*t", curr)
                  table.insert(data.tasks, { name = cur_task.name,
                                             tags = cur_task.tags,
                                             date = cur_task.ttypes[ttype].date,
                                             ttype = ttype,
                                             recur = cur_task.ttypes[ttype].recur})
                  data.dates[strip_time(curr)] = true
                  curr = freq_table[freq].next(curr, interval)
               end
            else
               table.insert(data.tasks, { name = cur_task.name,
                                          tags = cur_task.tags,
                                          date = cur_task.ttypes[ttype].date,
                                          ttype = ttype,
                                          recur = cur_task.ttypes[ttype].recur})
               data.dates[strip_time(cur_task.ttypes[ttype].date)] = true
            end
         end
      end
   end
   table.sort(data.tasks, function (a,b) return a.date <b.date end)
end

local function create_calendar()
   local nbr_space_between_days = 2
   offset = offset or 0

   local now = os.date("*t")
   local cal_month = now.month + offset
   local cal_year = now.year
   if cal_month > 12 then
      cal_month = (cal_month % 12)
      cal_year = cal_year + 1
   elseif cal_month < 1 then
      cal_month = (cal_month + 12)
      cal_year = cal_year - 1
   end

   local last_day = tonumber(os.date("%d", os.time({ day = 1, year = cal_year,
                                                     month = cal_month + 1}) - 86400))
   local first_day = os.time({ day = 1, month = cal_month, year = cal_year})
   local first_day_in_week =
      (os.date("%w", first_day) + 6) % 7
   days_of_week = {"Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"}
   local space_between_days = ""
   for i=1,nbr_space_between_days do
      space_between_days = space_between_days .. " "
   end
   local result = days_of_week[1]
   for i, day in ipairs(days_of_week) do
      if i>1 then
         result = result .. space_between_days .. day
      end
   end
   result= result .. "\n"
   for i = 1, first_day_in_week do
      result = result .. "  " .. space_between_days
   end
   local this_month = false
   for day = 1, last_day do
      local last_in_week = (day + first_day_in_week) % 7 == 0
      local day_str = pop_spaces("", day, nbr_space_between_days) .. (last_in_week and "" or space_between_days)
      if cal_month == now.month and cal_year == now.year and day == now.day then
         this_month = true
         result = result ..
            format('<span weight="bold" foreground="%s">%s</span>',
                   orglendar.colors.today_color,day_str)
      elseif data.dates[os.time{day = day, month = cal_month, year = cal_year}] then
         result = result ..
            format('<span weight="bold" foreground="%s">%s</span>',
                   orglendar.colors.event_color, day_str)
      else
         result = result .. day_str
      end
      if last_in_week and day ~= last_day then
         result = result .. "\n"
      end
   end

   local header
   if this_month then
      header = os.date("%a, %d %b %Y")
   else
      header = os.date("%B %Y", first_day)
   end
   return header, format('<span font="%s" foreground="%s">%s</span>',
                         orglendar.fonts.calendar_font,
                         orglendar.colors.text_color,
                         result)
end

local function create_todo()
   local result = ""
   local maxlen = data.maxlen + 10
   if limit_todo_length and limit_todo_length < maxlen then
      maxlen = limit_todo_length
   end
   local prev_date, limit, tname, ttype
   for i, cur_task in pairs(data.tasks) do
      local tname = cur_task.name
      -- naughty.notify({ title = "OOOOOOOOO debug",
      --                  text = cur_task.name .. "\n" .. cur_task.ttypes[ttype].recur .. "\n",
      --                  timeout = 0, hover_timeout = 0.5,
      --                  screen = mouse.screen,
      -- })

      local ttype = cur_task.ttype
      if (not prev_date) or strip_time(prev_date) ~= strip_time(cur_task.date) then
         if prev_date then
            result = result .. '-----------\n'
         end
         --          naughty.notify({ title = "DEBUG",
         --                  text = cur_task.name .. "\n" .. cur_task.ttypes[ttype].recur .. "\n",
         --                  timeout = 0, hover_timeout = 0.5,
         --                  screen = mouse.screen,
         -- })
         result = result ..
            format('<span weight="bold" font="monospace 13" foreground="%s">%s</span>\n',
                   orglendar.colors[ttype.. "_event_color"],
                   pop_spaces(os.date(
                                 orglendar.date_format,
                                 cur_task.date
                                     ),
                              "(" .. ttype .. ")",
                              maxlen)
            )
      end
      limit = maxlen - string.len(cur_task.tags) - 3
      if limit < string.len(tname) then
         tname = string.sub(tname, 1, limit - 3) .. "..."
      end
      result = result .. ("<span foreground='%s'>%s</span>"):format(
         "#0000FF",
         pop_spaces("  - " .. tname, cur_task.tags, maxlen))

      if i ~= #data.tasks then
         result = result .. "\n"
      end
      prev_date = cur_task.date
   end
   if result == "" then
      result = " "
   end
   return format('<span font="%s" foreground="%s">%s</span>',
                 orglendar.fonts.todo_font,
                 orglendar.colors.text_color,
                 result)
end

function orglendar.hide()
   if calendar ~= nil then
      naughty.destroy(calendar)
      naughty.destroy(todo)
      calendar = nil
      offset = 0
   end
end

function orglendar.show(inc_offset)
   inc_offset = inc_offset or 0

   if not data or parse_on_show then
      expand_recurrent_tasks(orglendar.parse_agenda())
   end

   local save_offset = offset
   orglendar.hide()
   offset = save_offset + inc_offset
   local header, cal_text = create_calendar()
   calendar = naughty.notify({ title = header,
                               text = cal_text,
                               timeout = 0, hover_timeout = 0.5,
                               screen = mouse.screen,
   })
   todo = naughty.notify({ title = "TODO list",
                           text = create_todo(),
                           timeout = 0, hover_timeout = 0.5,
                           screen = mouse.screen,
                           position = "top_left"
   })
end

function orglendar.register(widget)
   widget:connect_signal("mouse::enter", function() orglendar.show(0) end)
   widget:connect_signal("mouse::leave", orglendar.hide)
   widget:buttons(
      util.table.join(
         awful.button({ }, 3, function()
               expand_recurrent_tasks(orglendar.parse_agenda())
               naughty.destroy(calendar)
               local header, cal_text = create_calendar()
               calendar = naughty.notify({ title = header,
                                           text = cal_text,
                                           timeout = 0, hover_timeout = 0.5,
                                           screen = mouse.screen, })
               naughty.destroy(todo)
               todo = naughty.notify({ title = "TODO list",
                                       text = create_todo(),
                                       timeout = 0, hover_timeout = 0.5,
                                       screen = mouse.screen, })
         end),
         awful.button({ }, 4, function()
               orglendar.show(-1)
         end),
         awful.button({ }, 5, function()
               orglendar.show(1)
   end)))
end

return orglendar
